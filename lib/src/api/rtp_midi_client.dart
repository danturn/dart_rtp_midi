import 'dart:async';
import 'dart:math';

import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../transport/udp_transport.dart';
import 'mdns.dart';
import 'rtp_midi_config.dart';
import 'rtp_midi_session.dart';

/// A discovered RTP-MIDI service on the network.
class RtpMidiService {
  /// The advertised service name.
  final String name;

  /// The host address of the service.
  final String address;

  /// The control port of the service.
  final int port;

  /// Creates a discovered service entry.
  const RtpMidiService({
    required this.name,
    required this.address,
    required this.port,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtpMidiService &&
          name == other.name &&
          address == other.address &&
          port == other.port;

  @override
  int get hashCode => Object.hash(name, address, port);

  @override
  String toString() => 'RtpMidiService(name: "$name", $address:$port)';
}

/// Discovers and connects to remote RTP-MIDI sessions.
///
/// The client:
/// - Uses an [MdnsDiscoverer] to discover `_apple-midi._udp` services
/// - Creates a [UdpTransport] and [SessionController] for each connection
/// - Drives the invitation protocol to establish a session
/// - Returns a connected [RtpMidiSession]
///
/// Provide an [MdnsDiscoverer] implementation to enable network discovery.
/// If not provided, [discoverSessions] returns an empty stream, but direct
/// connections via [connectToAddress] still work.
class RtpMidiClient {
  /// Configuration for this client.
  final RtpMidiConfig config;

  /// The mDNS discoverer for finding services on the network.
  final MdnsDiscoverer _discoverer;

  final int _localSsrc;
  final _activeSessions = <SessionController>[];
  bool _disposed = false;

  /// Creates an RTP-MIDI client with the given [config].
  ///
  /// An optional [discoverer] enables mDNS service discovery. If not
  /// provided, a [NoOpMdnsDiscoverer] is used (no discovery).
  RtpMidiClient({
    required this.config,
    MdnsDiscoverer? discoverer,
  })  : _discoverer = discoverer ?? NoOpMdnsDiscoverer(),
        _localSsrc = _generateSsrc();

  /// Discover available RTP-MIDI sessions on the local network.
  ///
  /// Returns a stream that emits [RtpMidiService] entries as they are found.
  /// The stream remains open until [dispose] is called or the discovery is
  /// stopped.
  ///
  /// Requires an [MdnsDiscoverer] to have been provided at construction time.
  Stream<RtpMidiService> discoverSessions() {
    return _discoverer.discover('_apple-midi._udp').map(
          (info) => RtpMidiService(
            name: info.name,
            address: info.address,
            port: info.port,
          ),
        );
  }

  /// Connect to a discovered [service].
  ///
  /// Creates a transport, binds it, and drives the invitation protocol.
  /// Returns a connected [RtpMidiSession] or throws if the connection fails.
  Future<RtpMidiSession> connect(RtpMidiService service) {
    return connectToAddress(service.address, service.port);
  }

  /// Connect to a known address and control port.
  ///
  /// Creates a transport, binds it, and drives the invitation protocol.
  /// Returns a connected [RtpMidiSession] or throws a [TimeoutException]
  /// if the invitation is not accepted within the retry limit.
  Future<RtpMidiSession> connectToAddress(String address, int port) async {
    if (_disposed) {
      throw StateError('RtpMidiClient has been disposed');
    }

    // Each outbound connection gets its own transport on an ephemeral port.
    final transport = UdpTransport();
    await transport.bind();

    final controller = SessionController(
      transport: transport,
      config: config,
      localSsrc: _localSsrc,
    );

    _activeSessions.add(controller);

    // Wait for the session to reach connected (or better) or disconnected.
    final completer = Completer<RtpMidiSession>();

    // Single subscription that handles the connect-or-fail decision.
    late StreamSubscription<SessionState> connectSub;
    connectSub = controller.onStateChanged.listen((state) {
      if (completer.isCompleted) return;

      if (state == SessionState.connected || state == SessionState.ready) {
        connectSub.cancel();
        completer.complete(RtpMidiSession(controller));
      } else if (state == SessionState.disconnected) {
        connectSub.cancel();
        _activeSessions.remove(controller);
        controller.dispose();
        transport.close();
        completer.completeError(
          TimeoutException('Failed to connect to $address:$port'),
        );
      }
    });

    // Separate listener for lifecycle cleanup after connection.
    controller.onStateChanged.listen((state) {
      if (state == SessionState.disconnected) {
        _activeSessions.remove(controller);
        controller.dispose();
        transport.close();
      }
    });

    // Start the invitation handshake.
    await controller.invite(address, port);

    return completer.future;
  }

  /// Stop discovery and disconnect all active sessions.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Stop mDNS discovery.
    await _discoverer.stop();

    // Disconnect all sessions.
    for (final controller in List.of(_activeSessions)) {
      await controller.disconnect();
      await controller.dispose();
    }
    _activeSessions.clear();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  static final _random = Random();

  static int _generateSsrc() => _random.nextInt(0xFFFFFFFF);
}
