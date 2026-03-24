/// Cross-platform RTP-MIDI (RFC 6295) implementation in pure Dart.
///
/// Use [RtpMidiHost] to listen for inbound connections, or [RtpMidiClient]
/// to discover and connect to remote sessions. Both expose [RtpMidiSession]
/// objects for interacting with connected peers.
///
/// ```dart
/// // Listen for inbound connections:
/// final host = RtpMidiHost(config: RtpMidiConfig(name: 'My App', port: 5004));
/// await host.start();
/// host.onSessionConnected.listen((session) {
///   print('Connected to ${session.remoteName}');
/// });
///
/// // Connect to a known peer:
/// final client = RtpMidiClient(config: RtpMidiConfig(name: 'My App'));
/// final session = await client.connectToAddress('192.168.1.100', 5004);
/// ```
library;

// Public API
export 'src/api/mdns.dart'
    show
        MdnsBroadcaster,
        MdnsDiscoverer,
        MdnsServiceInfo,
        NoOpMdnsBroadcaster,
        NoOpMdnsDiscoverer;
export 'src/api/midi_message.dart';
export 'src/api/rtp_midi_client.dart' show RtpMidiClient, RtpMidiService;
export 'src/api/rtp_midi_config.dart' show RtpMidiConfig;
export 'src/api/rtp_midi_host.dart' show RtpMidiHost;
export 'src/api/rtp_midi_session.dart' show RtpMidiSession;

// Session state (needed by consumers to react to state changes)
export 'src/session/session_state.dart' show SessionState;

// Transport (for advanced usage or testing with custom transports)
export 'src/transport/transport.dart' show Transport, Datagram;
