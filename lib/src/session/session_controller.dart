import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../api/midi_message.dart';
import '../api/rtp_midi_config.dart';
import '../rtp/midi_command_codec.dart';
import '../rtp/rtp_header.dart';
import '../rtp/rtp_midi_payload.dart';
import '../rtp/sysex_reassembly.dart';
import '../transport/transport.dart';
import 'clock_sync.dart';
import 'exchange_packet.dart';
import 'invitation_protocol.dart';
import 'session_state.dart';

/// Orchestrates a single RTP-MIDI session lifecycle.
///
/// This is the imperative shell that connects the pure functional session
/// state machine to the transport layer. It:
/// - Listens for incoming packets on both ports
/// - Decodes packets and feeds events to the state machine
/// - Interprets [SessionEffect]s by calling transport methods and managing timers
/// - Exposes streams for session state changes
///
/// All protocol logic lives in the pure functions ([transition],
/// [createInvitation], [createCk0], etc.). This class only wires them up
/// to real I/O.
class SessionController {
  final Transport _transport;
  final RtpMidiConfig _config;
  final int _localSsrc;

  SessionState _state = SessionState.idle;

  /// Remote peer information, populated during the handshake.
  String _remoteName = '';
  String _remoteAddress = '';
  int _remoteControlPort = 0;
  int _remoteDataPort = 0;
  int _remoteSsrc = 0;

  /// The initiator token for the current invitation exchange.
  int _initiatorToken = 0;

  /// Invitation retry tracking.
  int _invitationAttempt = 0;

  /// Latest clock sync result.
  ClockSyncResult? _lastSyncResult;

  /// Active timers.
  Timer? _retryTimer;
  Timer? _clockSyncTimeoutTimer;
  Timer? _periodicClockSyncTimer;

  /// Stream subscriptions for transport messages.
  StreamSubscription<Datagram>? _controlSub;
  StreamSubscription<Datagram>? _dataSub;

  /// State change stream.
  final _stateController = StreamController<SessionState>.broadcast();

  /// Incoming MIDI message stream.
  final _midiController = StreamController<MidiMessage>.broadcast();

  /// Outgoing RTP sequence number (uint16, wrapping, random start per RFC 3550).
  int _outgoingSequenceNumber = _random.nextInt(0xFFFF);

  /// SysEx reassembler for multi-packet SysEx messages.
  final _sysExReassembler = SysExReassembler();

  /// Whether this controller has been disposed.
  bool _disposed = false;

  /// Creates a session controller.
  ///
  /// [transport] must already be bound. [localSsrc] is the SSRC identifier
  /// for this endpoint.
  SessionController({
    required Transport transport,
    required RtpMidiConfig config,
    required int localSsrc,
  })  : _transport = transport,
        _config = config,
        _localSsrc = localSsrc {
    _controlSub = _transport.onControlMessage.listen(_onControlMessage);
    _dataSub = _transport.onDataMessage.listen(_onDataMessage);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// The current session state.
  SessionState get state => _state;

  /// Stream of state changes.
  Stream<SessionState> get onStateChanged => _stateController.stream;

  /// The human-readable name of the remote peer, or empty if not yet known.
  String get remoteName => _remoteName;

  /// The network address of the remote peer, or empty if not yet known.
  String get remoteAddress => _remoteAddress;

  /// The remote peer's control port.
  int get remoteControlPort => _remoteControlPort;

  /// The remote peer's data port.
  int get remoteDataPort => _remoteDataPort;

  /// The remote peer's SSRC.
  int get remoteSsrc => _remoteSsrc;

  /// The most recent clock synchronization result, if any.
  ClockSyncResult? get lastSyncResult => _lastSyncResult;

  /// Stream of incoming MIDI messages from the remote peer.
  Stream<MidiMessage> get onMidiMessage => _midiController.stream;

  /// Send a MIDI message to the remote peer.
  ///
  /// The message is wrapped in an RTP-MIDI payload and sent via the data port.
  /// Does nothing if the session is not in a connected/ready state.
  void sendMidi(MidiMessage message) {
    if (_state != SessionState.ready &&
        _state != SessionState.connected &&
        _state != SessionState.synchronizing) {
      return;
    }

    final payload = RtpMidiPayload(
      header: RtpHeader(
        sequenceNumber: _nextSequenceNumber(),
        timestamp: _rtpTimestamp(),
        ssrc: _localSsrc,
        marker: false,
      ),
      commands: [TimestampedMidiCommand(0, message)],
    );

    _transport.sendData(
      payload.encode(),
      _remoteAddress,
      _remoteDataPort,
    );
  }

  /// Initiate an outbound connection to [address]:[port] (control port).
  ///
  /// The data port is assumed to be [port] + 1, per the RTP-MIDI convention.
  Future<void> invite(String address, int port) async {
    if (_state != SessionState.idle) return;

    _remoteAddress = address;
    _remoteControlPort = port;
    _remoteDataPort = port + 1;
    _initiatorToken = _generateToken();
    _invitationAttempt = 0;

    _applyEvent(SessionEvent.sendInvitation);
  }

  /// Accept an incoming invitation.
  ///
  /// Called by the host when an IN packet arrives on the control port.
  /// The controller will send OK and wait for the data-port IN.
  Future<void> acceptInvitation(
    ExchangePacket invitation,
    String address,
    int port,
  ) async {
    if (_state != SessionState.idle) return;

    _remoteAddress = address;
    _remoteControlPort = port;
    _remoteDataPort = port + 1;
    _remoteSsrc = invitation.ssrc;
    _remoteName = invitation.name;
    _initiatorToken = invitation.initiatorToken;

    // Send OK on the control port.
    _sendPacketOnControl(createOk(
      initiatorToken: _initiatorToken,
      ssrc: _localSsrc,
      name: _config.name,
    ));

    // Move directly to invitingData — we are the responder, so we wait
    // for the remote to send IN on the data port.
    _setState(SessionState.invitingData);
  }

  /// Disconnect from the remote peer.
  Future<void> disconnect() async {
    if (_state == SessionState.disconnected ||
        _state == SessionState.disconnecting ||
        _state == SessionState.idle) {
      return;
    }
    _applyEvent(SessionEvent.byeSent);
  }

  /// Release all resources.
  ///
  /// After calling dispose, this controller must not be used again.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _cancelAllTimers();
    await _controlSub?.cancel();
    await _dataSub?.cancel();
    await _stateController.close();
    await _midiController.close();
    _sysExReassembler.reset();
  }

  // ---------------------------------------------------------------------------
  // Packet handling
  // ---------------------------------------------------------------------------

  void _onControlMessage(Datagram datagram) {
    if (_disposed) return;

    // Only process packets from the expected remote peer (or any peer if idle).
    if (_state != SessionState.idle && datagram.address != _remoteAddress) {
      return;
    }

    final isClock = isClockSyncPacket(datagram.data);
    if (isClock == true) {
      _handleClockSyncPacket(datagram, isControlPort: true);
      return;
    }

    final packet = ExchangePacket.decode(datagram.data);
    if (packet == null) return;

    _handleExchangePacket(packet, datagram.address, datagram.port,
        isControlPort: true);
  }

  void _onDataMessage(Datagram datagram) {
    if (_disposed) return;

    if (_state == SessionState.idle) return;
    if (datagram.address != _remoteAddress) return;

    final data = datagram.data;

    // Check for clock sync or exchange packets (0xFFFF signature).
    final isClock = isClockSyncPacket(data);
    if (isClock == true) {
      _handleClockSyncPacket(datagram, isControlPort: false);
      return;
    }
    if (isClock == false) {
      // It's an exchange packet (has 0xFFFF signature but not CK).
      final packet = ExchangePacket.decode(data);
      if (packet != null) {
        _handleExchangePacket(packet, datagram.address, datagram.port,
            isControlPort: false);
      }
      return;
    }

    // Not a session protocol packet — check for RTP (version 2).
    if (data.length >= 13 && (data[0] & 0xC0) == 0x80) {
      _handleRtpMidiPacket(data);
    }
  }

  void _handleExchangePacket(
    ExchangePacket packet,
    String address,
    int port, {
    required bool isControlPort,
  }) {
    switch (packet.command) {
      case ExchangeCommand.invitation:
        _handleIncomingInvitation(packet, address, port,
            isControlPort: isControlPort);

      case ExchangeCommand.ok:
        _handleOk(packet, isControlPort: isControlPort);

      case ExchangeCommand.no:
        _handleNo(isControlPort: isControlPort);

      case ExchangeCommand.bye:
        _applyEvent(SessionEvent.byeReceived);
    }
  }

  void _handleIncomingInvitation(
    ExchangePacket packet,
    String address,
    int port, {
    required bool isControlPort,
  }) {
    if (isControlPort) {
      // Control-port invitation — this is handled by the Host, which calls
      // acceptInvitation(). If we're already in a session and receive a
      // duplicate IN, re-send OK.
      if (_state == SessionState.invitingData && packet.ssrc == _remoteSsrc) {
        _sendPacketOnControl(createOk(
          initiatorToken: packet.initiatorToken,
          ssrc: _localSsrc,
          name: _config.name,
        ));
      }
    } else {
      // Data-port invitation from the remote peer (we are the responder).
      if (_state == SessionState.invitingData) {
        _remoteSsrc = packet.ssrc;
        _remoteName = packet.name;
        _remoteDataPort = port;

        // Send OK on the data port.
        _sendPacketOnData(createOk(
          initiatorToken: packet.initiatorToken,
          ssrc: _localSsrc,
          name: _config.name,
        ));

        // Transition: data OK received (from our perspective as responder,
        // receiving the data IN and sending OK completes the handshake).
        _applyEvent(SessionEvent.dataOkReceived);
      }
    }
  }

  void _handleOk(ExchangePacket packet, {required bool isControlPort}) {
    // Verify the token matches our outstanding invitation.
    if (packet.initiatorToken != _initiatorToken) return;

    _remoteSsrc = packet.ssrc;
    _remoteName = packet.name;

    if (isControlPort) {
      _applyEvent(SessionEvent.controlOkReceived);
    } else {
      _applyEvent(SessionEvent.dataOkReceived);
    }
  }

  void _handleNo({required bool isControlPort}) {
    if (isControlPort) {
      _applyEvent(SessionEvent.controlNoReceived);
    } else {
      _applyEvent(SessionEvent.dataNoReceived);
    }
  }

  // ---------------------------------------------------------------------------
  // Clock sync handling
  // ---------------------------------------------------------------------------

  void _handleClockSyncPacket(Datagram datagram,
      {required bool isControlPort}) {
    // Apple's implementation exchanges clock sync on the data port,
    // but we accept CK packets on either port for maximum compatibility.

    final ck = ClockSyncPacket.decode(datagram.data);
    if (ck == null) return;

    switch (ck.count) {
      case 0:
        // We received CK0 — respond with CK1.
        final ck1 = createCk1(
          ssrc: _localSsrc,
          timestamp1: ck.timestamp1,
          timestamp2: _currentTimestamp(),
        );
        _sendClockSyncPacket(ck1);

      case 1:
        // We received CK1 — respond with CK2 and compute offset.
        final now = _currentTimestamp();
        final ck2 = createCk2(
          ssrc: _localSsrc,
          timestamp1: ck.timestamp1,
          timestamp2: ck.timestamp2,
          timestamp3: now,
        );
        _sendClockSyncPacket(ck2);
        _lastSyncResult = computeOffset(ck2);
        _applyEvent(SessionEvent.clockSyncComplete);

      case 2:
        // We received CK2 (we were the responder for this exchange).
        _lastSyncResult = computeOffset(ck);
        _applyEvent(SessionEvent.clockSyncComplete);
    }
  }

  void _sendClockSyncPacket(ClockSyncPacket packet) {
    // Apple's implementation exchanges clock sync on the data port.
    _transport.sendData(
      packet.encode(),
      _remoteAddress,
      _remoteDataPort,
    );
  }

  /// Returns the current time as a 64-bit timestamp in 100-microsecond ticks.
  int _currentTimestamp() {
    return DateTime.now().microsecondsSinceEpoch ~/ 100;
  }

  // ---------------------------------------------------------------------------
  // RTP-MIDI packet handling
  // ---------------------------------------------------------------------------

  void _handleRtpMidiPacket(Uint8List data) {
    final payload = RtpMidiPayload.decode(data);
    if (payload == null) return;

    for (final cmd in payload.commands) {
      if (!_midiController.isClosed) {
        _midiController.add(cmd.message);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------

  void _applyEvent(SessionEvent event) {
    final result = transition(_state, event);
    _setState(result.newState);
    _executeEffects(result.effects);
  }

  void _setState(SessionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  // ---------------------------------------------------------------------------
  // Effect execution
  // ---------------------------------------------------------------------------

  void _executeEffects(List<SessionEffect> effects) {
    for (final effect in effects) {
      switch (effect) {
        case SessionEffect.sendControlInvitation:
          _doSendControlInvitation();

        case SessionEffect.sendDataInvitation:
          _doSendDataInvitation();

        case SessionEffect.sendClockSync:
          _doSendClockSync();

        case SessionEffect.sendBye:
          _doSendBye();

        case SessionEffect.emitConnected:
          // State already emitted via _setState.
          break;

        case SessionEffect.emitSynchronized:
          // State already emitted via _setState.
          break;

        case SessionEffect.emitDisconnected:
          // State already emitted via _setState.
          break;

        case SessionEffect.scheduleInvitationRetry:
          _scheduleInvitationRetry();

        case SessionEffect.scheduleClockSyncTimeout:
          _scheduleClockSyncTimeout();

        case SessionEffect.schedulePeriodicClockSync:
          _schedulePeriodicClockSync();

        case SessionEffect.cancelTimers:
          _cancelAllTimers();

        case SessionEffect.emitError:
          // State already emitted via _setState.
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Effect implementations
  // ---------------------------------------------------------------------------

  void _doSendControlInvitation() {
    final packet = createInvitation(
      initiatorToken: _initiatorToken,
      ssrc: _localSsrc,
      name: _config.name,
    );
    _sendPacketOnControl(packet);
  }

  void _doSendDataInvitation() {
    final packet = createInvitation(
      initiatorToken: _initiatorToken,
      ssrc: _localSsrc,
      name: _config.name,
    );
    _sendPacketOnData(packet);
  }

  void _doSendClockSync() {
    final ck0 = createCk0(
      ssrc: _localSsrc,
      timestamp1: _currentTimestamp(),
    );
    _sendClockSyncPacket(ck0);
  }

  void _doSendBye() {
    final bye = createBye(
      initiatorToken: _initiatorToken,
      ssrc: _localSsrc,
      name: _config.name,
    );
    _sendPacketOnControl(bye);
    _sendPacketOnData(bye);
  }

  void _sendPacketOnControl(ExchangePacket packet) {
    _transport.sendControl(
      packet.encode(),
      _remoteAddress,
      _remoteControlPort,
    );
  }

  void _sendPacketOnData(ExchangePacket packet) {
    _transport.sendData(
      packet.encode(),
      _remoteAddress,
      _remoteDataPort,
    );
  }

  // ---------------------------------------------------------------------------
  // Timer management
  // ---------------------------------------------------------------------------

  void _scheduleInvitationRetry() {
    _retryTimer?.cancel();

    final delay = nextRetryDelay(
      attempt: _invitationAttempt,
      baseInterval: _config.invitationRetryBaseInterval,
      maxRetries: _config.maxInvitationRetries,
    );

    if (delay == null) {
      // Max retries exhausted.
      _applyEvent(SessionEvent.timeout);
      return;
    }

    _invitationAttempt++;

    _retryTimer = Timer(delay, () {
      if (_disposed) return;

      // Re-send the invitation on the appropriate port.
      if (_state == SessionState.invitingControl) {
        _doSendControlInvitation();
        _scheduleInvitationRetry();
      } else if (_state == SessionState.invitingData) {
        _doSendDataInvitation();
        _scheduleInvitationRetry();
      }
    });
  }

  void _scheduleClockSyncTimeout() {
    _clockSyncTimeoutTimer?.cancel();
    _clockSyncTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      _applyEvent(SessionEvent.clockSyncTimeout);
    });
  }

  void _schedulePeriodicClockSync() {
    _periodicClockSyncTimer?.cancel();
    _periodicClockSyncTimer = Timer(_config.clockSyncInterval, () {
      if (_disposed) return;
      // Trigger a new clock sync exchange via the state machine.
      // The ready state uses sendInvitation event to trigger periodic sync.
      _applyEvent(SessionEvent.sendInvitation);
    });
  }

  void _cancelAllTimers() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _clockSyncTimeoutTimer?.cancel();
    _clockSyncTimeoutTimer = null;
    _periodicClockSyncTimer?.cancel();
    _periodicClockSyncTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static final _random = Random();

  int _generateToken() => _random.nextInt(0xFFFFFFFF);

  /// Returns the current time as a 32-bit RTP timestamp (100µs ticks, truncated).
  int _rtpTimestamp() {
    return _currentTimestamp() & 0xFFFFFFFF;
  }

  /// Returns the next outgoing sequence number (wrapping uint16).
  int _nextSequenceNumber() {
    final seq = _outgoingSequenceNumber;
    _outgoingSequenceNumber = (_outgoingSequenceNumber + 1) & 0xFFFF;
    return seq;
  }
}
