import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../api/midi_message.dart';
import '../api/rtp_midi_config.dart';
import '../api/session_error.dart';
import '../rtp/midi_command_codec.dart';
import '../rtp/rtp_header.dart';
import '../rtp/rtp_midi_payload.dart';
import '../rtp/journal/journal_builder.dart';
import '../rtp/journal/journal_recovery.dart';
import '../rtp/journal/midi_state.dart';
import '../rtp/journal/sequence_tracker.dart';
import '../rtp/journal/seq_compare.dart';
import '../rtp/journal/state_trim.dart';
import '../rtp/journal/state_update.dart';
import '../rtp/sysex_reassembly.dart';
import '../transport/transport.dart';
import 'clock_sync.dart';
import 'exchange_packet.dart';
import 'invitation_protocol.dart';
import 'rs_packet.dart';
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

  /// Error stream.
  final _errorController = StreamController<SessionError>.broadcast();

  /// Outgoing RTP sequence number (uint16, wrapping, random start per RFC 3550).
  int _outgoingSequenceNumber = _random.nextInt(0xFFFF);

  /// SysEx reassembler for multi-packet SysEx messages.
  final _sysExReassembler = SysExReassembler();

  /// Whether startup rapid sync has been sent.
  bool _startupSyncDone = false;

  /// Number of completed clock sync exchanges since connection.
  int _completedSyncCount = 0;

  /// Completes when enough startup sync exchanges have finished for
  /// Apple's CoreMIDI to route MIDI (requires ~6 exchanges).
  final _startupSyncCompleter = Completer<void>();

  /// The minimum number of completed CK exchanges before MIDI routing
  /// is considered active (matches rtpmidid's behavior).
  static const int _startupSyncThreshold = 6;

  /// Whether this controller has been disposed.
  bool _disposed = false;

  /// Recovery journal state: tracks MIDI state for outgoing packets.
  MidiState _senderState = MidiState.empty;

  /// Recovery journal state: tracks MIDI state as received.
  MidiState _receiverState = MidiState.empty;

  /// Detects sequence number gaps in incoming packets.
  SequenceTracker _sequenceTracker = SequenceTracker.initial;

  /// Checkpoint sequence number for the recovery journal (first packet sent).
  int? _checkpointSeqNum;

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

  /// Completes when enough startup clock sync exchanges have finished
  /// for the remote peer to accept MIDI data.
  ///
  /// Apple's CoreMIDI requires multiple clock sync exchanges before it
  /// routes MIDI. Await this before sending to ensure delivery.
  Future<void> get onReady => _startupSyncCompleter.future;

  /// Stream of incoming MIDI messages from the remote peer.
  Stream<MidiMessage> get onMidiMessage => _midiController.stream;

  /// Stream of errors encountered during the session.
  Stream<SessionError> get onError => _errorController.stream;

  /// Send a MIDI message to the remote peer.
  ///
  /// The message is wrapped in an RTP-MIDI payload and sent via the data port.
  /// Does nothing if the session is not in a connected/ready state.
  void sendMidi(MidiMessage message) {
    if (_state != SessionState.ready &&
        _state != SessionState.connected &&
        _state != SessionState.synchronizing) {
      _emitError(ProtocolViolation(
        message: 'Cannot send MIDI in state $_state',
        address: _remoteAddress,
        port: _remoteDataPort,
        reason: ProtocolViolationReason.sendBeforeReady,
      ));
      return;
    }

    final seqNum = _nextSequenceNumber();
    _senderState = updateState(_senderState, message, seq: seqNum);
    _checkpointSeqNum ??= seqNum;
    final journalBytes = buildJournal(_senderState, _checkpointSeqNum!);

    final payload = RtpMidiPayload(
      header: RtpHeader(
        sequenceNumber: seqNum,
        timestamp: _rtpTimestamp(),
        ssrc: _localSsrc,
        marker: false,
      ),
      commands: [TimestampedMidiCommand(0, message)],
      hasJournal: journalBytes != null,
      journalData: journalBytes,
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
    await _errorController.close();
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
    if (isClock == false) {
      // Has 0xFFFF signature but not CK — check for RS before exchange.
      if (isRsPacket(datagram.data)) {
        _handleRsPacket(datagram.data);
        return;
      }
      ExchangePacket? packet;
      try {
        packet = ExchangePacket.decode(datagram.data);
      } on FormatException {
        _emitError(MalformedPacket(
          message: 'Invalid UTF-8 in exchange packet on control port',
          address: datagram.address,
          port: datagram.port,
          rawBytes: datagram.data,
          packetType: PacketType.exchange,
        ));
        return;
      }
      if (packet != null) {
        _handleExchangePacket(packet, datagram.address, datagram.port,
            isControlPort: true);
      } else {
        _emitError(MalformedPacket(
          message: 'Failed to decode exchange packet on control port',
          address: datagram.address,
          port: datagram.port,
          rawBytes: datagram.data,
          packetType: PacketType.exchange,
        ));
      }
      return;
    }
    // isClock == null: not a session protocol packet, ignore.
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
      ExchangePacket? packet;
      try {
        packet = ExchangePacket.decode(data);
      } on FormatException {
        _emitError(MalformedPacket(
          message: 'Invalid UTF-8 in exchange packet on data port',
          address: datagram.address,
          port: datagram.port,
          rawBytes: data,
          packetType: PacketType.exchange,
        ));
        return;
      }
      if (packet != null) {
        _handleExchangePacket(packet, datagram.address, datagram.port,
            isControlPort: false);
      } else {
        _emitError(MalformedPacket(
          message: 'Failed to decode exchange packet on data port',
          address: datagram.address,
          port: datagram.port,
          rawBytes: data,
          packetType: PacketType.exchange,
        ));
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
        _emitError(PeerDisconnected(
          message: 'Remote peer sent BYE',
          address: address,
          port: port,
          reason: PeerDisconnectedReason.byeReceived,
        ));
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
    if (packet.initiatorToken != _initiatorToken) {
      _emitError(ProtocolViolation(
        message: 'OK response has wrong initiator token '
            '(expected 0x${_initiatorToken.toRadixString(16)}, '
            'got 0x${packet.initiatorToken.toRadixString(16)})',
        address: _remoteAddress,
        port: isControlPort ? _remoteControlPort : _remoteDataPort,
        rawBytes: packet.encode(),
        reason: ProtocolViolationReason.tokenMismatch,
      ));
      return;
    }

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
      _emitError(ConnectionFailed(
        message: 'Invitation rejected on control port',
        address: _remoteAddress,
        port: _remoteControlPort,
        reason: ConnectionFailedReason.rejected,
      ));
      _applyEvent(SessionEvent.controlNoReceived);
    } else {
      _emitError(ConnectionFailed(
        message: 'Invitation rejected on data port',
        address: _remoteAddress,
        port: _remoteDataPort,
        reason: ConnectionFailedReason.dataHandshakeFailed,
      ));
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
    if (ck == null) {
      _emitError(MalformedPacket(
        message: 'Failed to decode clock sync packet',
        address: datagram.address,
        port: datagram.port,
        rawBytes: datagram.data,
        packetType: PacketType.clockSync,
      ));
      return;
    }

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
        _completedSyncCount++;
        _checkStartupSyncComplete();
        _applyEvent(SessionEvent.clockSyncComplete);

      case 2:
        // We received CK2 (we were the responder for this exchange).
        _lastSyncResult = computeOffset(ck);
        _completedSyncCount++;
        _checkStartupSyncComplete();
        _applyEvent(SessionEvent.clockSyncComplete);
    }
  }

  void _checkStartupSyncComplete() {
    if (!_startupSyncCompleter.isCompleted &&
        _completedSyncCount >= _startupSyncThreshold) {
      _startupSyncCompleter.complete();
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
    if (payload == null) {
      _emitError(MalformedPacket(
        message: 'Failed to decode RTP-MIDI packet',
        address: _remoteAddress,
        port: _remoteDataPort,
        rawBytes: data,
        packetType: PacketType.rtpMidi,
      ));
      return;
    }

    final (nextTracker, gap) = SequenceTracker.process(
        _sequenceTracker, payload.header.sequenceNumber);
    _sequenceTracker = nextTracker;

    // On gap with journal present, compute corrective messages.
    if (gap && payload.journalData != null) {
      final corrective =
          recoverFromJournal(payload.journalData!, _receiverState);
      for (final msg in corrective) {
        _receiverState = updateState(_receiverState, msg);
        if (!_midiController.isClosed) {
          _midiController.add(msg);
        }
      }
      // Mark journal as processed so late-join recovery stops.
      if (!_sequenceTracker.hasProcessedJournal) {
        _sequenceTracker = _sequenceTracker.withJournalProcessed();
      }
    }

    // Emit regular commands and update receiver state.
    for (final cmd in payload.commands) {
      _receiverState = updateState(_receiverState, cmd.message);
      if (!_midiController.isClosed) {
        _midiController.add(cmd.message);
      }
    }

    // Send RS (Receiver Feedback) when journal data is present,
    // telling the sender we've received up to this seqnum.
    if (payload.journalData != null) {
      final rs = RsPacket(
        ssrc: _localSsrc,
        sequenceNumber: payload.header.sequenceNumber,
      );
      _transport.sendControl(
        rs.encode(),
        _remoteAddress,
        _remoteControlPort,
      );
    }
  }

  void _handleRsPacket(Uint8List data) {
    final rs = RsPacket.decode(data);
    if (rs == null) return; // Can't happen: isRsPacket() has same guards.
    final confirmedSeq = rs.sequenceNumber;
    if (_checkpointSeqNum != null &&
        seqAtOrAfter(confirmedSeq, _checkpointSeqNum!)) {
      _checkpointSeqNum = confirmedSeq;
      _senderState = trimState(_senderState, confirmedSeq);
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
      _emitError(ConnectionFailed(
        message: 'No response after ${_config.maxInvitationRetries} retries',
        address: _remoteAddress,
        port: _remoteControlPort,
        reason: ConnectionFailedReason.timeout,
      ));
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
    _clockSyncTimeoutTimer = Timer(_config.clockSyncTimeout, () {
      if (_disposed) return;
      _emitError(ProtocolViolation(
        message: 'Clock sync timed out',
        address: _remoteAddress,
        port: _remoteDataPort,
        reason: ProtocolViolationReason.clockSyncTimeout,
      ));
      _applyEvent(SessionEvent.clockSyncTimeout);
    });
  }

  void _schedulePeriodicClockSync() {
    _periodicClockSyncTimer?.cancel();

    // On first ready, send rapid startup sync exchanges.
    // Apple's doc: "During startup, the initiator should send synchronization
    // exchanges more frequently" — required for Apple to route MIDI.
    if (!_startupSyncDone) {
      _startupSyncDone = true;
      for (var i = 0; i < 5; i++) {
        Future.delayed(Duration(milliseconds: 100 * (i + 1)), () {
          if (_disposed) return;
          _doSendClockSync();
        });
      }
    }

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

  void _emitError(SessionError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }
}
