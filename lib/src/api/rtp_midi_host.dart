import 'dart:async';
import 'dart:math';

import '../session/exchange_packet.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../transport/transport.dart';
import '../transport/udp_transport.dart';
import 'mdns.dart';
import 'rtp_midi_config.dart';
import 'rtp_midi_session.dart';

/// Listens for inbound RTP-MIDI connections and manages sessions.
///
/// The host:
/// - Binds a [Transport] on the configured port pair
/// - Optionally registers an mDNS service (`_apple-midi._udp`) via the
///   supplied [MdnsBroadcaster] so peers can discover it
/// - Listens for incoming invitation packets on the control port
/// - Creates a [SessionController] for each accepted session
/// - Exposes a stream of newly connected [RtpMidiSession]s
class RtpMidiHost {
  /// Configuration for this host.
  final RtpMidiConfig config;

  /// The mDNS broadcaster for service registration.
  ///
  /// Pass a [NoOpMdnsBroadcaster] to skip mDNS registration.
  final MdnsBroadcaster _broadcaster;

  final int _localSsrc;
  Transport? _transport;

  final _sessions = <SessionController>[];
  final _sessionStream = StreamController<RtpMidiSession>.broadcast();
  StreamSubscription<Datagram>? _controlSub;

  bool _running = false;

  /// Set of controller hash codes that have already been emitted as connected.
  final _emittedControllers = <int>{};

  /// Creates an RTP-MIDI host with the given [config].
  ///
  /// An optional [broadcaster] is used to register the service via mDNS.
  /// If not provided, a [NoOpMdnsBroadcaster] is used (no mDNS advertisement).
  ///
  /// Call [start] to begin listening for connections.
  RtpMidiHost({
    required this.config,
    MdnsBroadcaster? broadcaster,
  })  : _broadcaster = broadcaster ?? NoOpMdnsBroadcaster(),
        _localSsrc = _generateSsrc();

  /// Whether the host is currently listening.
  bool get isRunning => _running;

  /// The local control port, or 0 if not yet started.
  int get controlPort => _transport?.controlPort ?? 0;

  /// The local data port, or 0 if not yet started.
  int get dataPort => _transport?.dataPort ?? 0;

  /// Start listening for inbound connections.
  ///
  /// Binds the transport, registers mDNS, and begins accepting invitations.
  Future<void> start() async {
    if (_running) return;

    final transport = UdpTransport(port: config.port);
    await transport.bind();
    _transport = transport;

    // Listen for incoming exchange packets on the control port.
    _controlSub = transport.onControlMessage.listen(_onControlMessage);

    // Register the mDNS service.
    await _broadcaster.start(
      name: config.name,
      type: '_apple-midi._udp',
      port: transport.controlPort,
    );

    _running = true;
  }

  /// Stop listening and clean up all resources.
  ///
  /// Disconnects all active sessions, unregisters mDNS, and closes the
  /// transport.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    // Stop mDNS broadcast.
    await _broadcaster.stop();

    // Disconnect all sessions.
    for (final controller in List.of(_sessions)) {
      await controller.disconnect();
      await controller.dispose();
    }
    _sessions.clear();
    _emittedControllers.clear();

    // Stop listening and close transport.
    await _controlSub?.cancel();
    _controlSub = null;
    await _transport?.close();
    _transport = null;

    await _sessionStream.close();
  }

  /// Stream of newly connected sessions.
  ///
  /// A session is emitted once both the control and data port handshakes
  /// complete (i.e., the session reaches the [SessionState.connected] state).
  /// Each session is emitted at most once.
  Stream<RtpMidiSession> get onSessionConnected => _sessionStream.stream;

  /// Currently active sessions (connected or synchronizing).
  List<RtpMidiSession> get sessions =>
      _sessions.map(RtpMidiSession.new).toList(growable: false);

  // ---------------------------------------------------------------------------
  // Incoming packet handling
  // ---------------------------------------------------------------------------

  void _onControlMessage(Datagram datagram) {
    // Only handle exchange packets (not clock sync -- those are handled
    // by individual SessionControllers).
    final isClock = isClockSyncPacket(datagram.data);
    if (isClock == true) return;

    final packet = ExchangePacket.decode(datagram.data);
    if (packet == null) return;

    if (packet.command == ExchangeCommand.invitation) {
      _handleInvitation(packet, datagram.address, datagram.port);
    }
    // OK, NO, and BYE on the control port are handled by each session's
    // own transport listener.
  }

  void _handleInvitation(
    ExchangePacket invitation,
    String address,
    int port,
  ) {
    final transport = _transport;
    if (transport == null) return;

    // Check if we already have a session with this peer.
    final existing = _sessions.where(
      (c) => c.remoteAddress == address && c.remoteSsrc == invitation.ssrc,
    );
    if (existing.isNotEmpty) {
      // Already have a session -- the controller will handle the duplicate IN.
      return;
    }

    // Create a new session controller for this inbound connection.
    final controller = SessionController(
      transport: transport,
      config: config,
      localSsrc: _localSsrc,
    );

    _sessions.add(controller);
    final controllerId = identityHashCode(controller);

    // Listen for state changes to detect connection and cleanup.
    controller.onStateChanged.listen((state) {
      if (state == SessionState.connected || state == SessionState.ready) {
        // Emit the session at most once.
        if (_emittedControllers.add(controllerId)) {
          if (!_sessionStream.isClosed) {
            _sessionStream.add(RtpMidiSession(controller));
          }
        }
      } else if (state == SessionState.disconnected) {
        _sessions.remove(controller);
        _emittedControllers.remove(controllerId);
        controller.dispose();
      }
    });

    // Accept the invitation -- this sends OK on the control port and
    // transitions the controller to await the data-port IN.
    controller.acceptInvitation(invitation, address, port);
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static final _random = Random();

  static int _generateSsrc() => _random.nextInt(0xFFFFFFFF);
}
