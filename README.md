# dart_rtp_midi

Cross-platform [RTP-MIDI](https://www.rfc-editor.org/rfc/rfc6295) implementation in pure Dart. Network MIDI transport for iOS, Android, macOS, Windows, and Linux.

The first open-source RTP-MIDI library for Dart/Flutter — connect to macOS Network MIDI sessions, rtpMIDI (Windows), DAWs, and hardware over WiFi.

## Status: Work in Progress

> **This library is under active development and is not yet ready for production use.**
>
> **What works now (Phases 1-4):**
> - Session discovery, invitation handshake (IN/OK/NO/BY), and graceful disconnect
> - Clock synchronization (CK0/CK1/CK2 three-way exchange)
> - Host mode (accept inbound connections) and Client mode (discover/connect outbound)
> - Full state machine with exponential backoff retries
> - Send and receive all MIDI 1.0 messages (channel voice, system common, system real-time, SysEx)
> - RTP header codec, variable-length delta timestamps, SysEx reassembly
> - Recovery journal codecs: journal header + system chapters (D, V, Q, F, X) + channel chapters (P, C, M, W, N, E, T, A)
>
> **What does NOT work yet:**
> - Wire journal into send/receive pipeline (Phase 5)
> - Published on pub.dev
>
> See [Roadmap](#roadmap) below for the full plan.

## Quick Start

### Host (accept incoming connections)

```dart
import 'package:dart_rtp_midi/rtp_midi.dart';

final host = RtpMidiHost(
  config: RtpMidiConfig(name: 'My Dart Session', port: 5004),
);

await host.start();
print('Listening on port ${host.controlPort}');

host.onSessionConnected.listen((session) {
  print('Connected: ${session.remoteName}');

  session.onMidiMessage.listen((msg) {
    print('Received: $msg');
  });

  session.onStateChanged.listen((state) {
    if (state == SessionState.ready) {
      session.send(NoteOn(channel: 0, note: 60, velocity: 100));
    }
  });
});
```

### Client (discover and connect)

```dart
import 'package:dart_rtp_midi/rtp_midi.dart';

final client = RtpMidiClient(
  config: RtpMidiConfig(name: 'My Dart Client'),
);

// Connect to a known address
final session = await client.connectToAddress('192.168.1.50', 5004);
print('Connected to ${session.remoteName}');

// Wait for startup sync (required for Apple compatibility)
await session.onReady;

// Send MIDI
session.send(NoteOn(channel: 0, note: 60, velocity: 100));
session.send(ControlChange(channel: 0, controller: 7, value: 100));

// Receive MIDI
session.onMidiMessage.listen((msg) {
  print('Received: $msg');
});
```

### Configuration

```dart
const config = RtpMidiConfig(
  name: 'My Session',         // Session name visible to peers
  port: 5004,                 // Control port (even); 0 = auto-assign
  clockSyncInterval: Duration(seconds: 10),
  maxInvitationRetries: 12,
  invitationRetryBaseInterval: Duration(milliseconds: 1500),
  sessionTimeout: Duration(seconds: 60),
);
```

## Architecture

```
┌─────────────────────────────────────────┐
│           Public API Layer              │
│  RtpMidiHost · RtpMidiClient · Session  │
├─────────────────────────────────────────┤
│         Session Management              │
│  mDNS discovery · Invitation (IN/OK/    │
│  NO/BY) · Clock sync (CK0/CK1/CK2)    │
├─────────────────────────────────────────┤
│          RTP MIDI Payload               │
│  RTP header · MIDI command section ·    │
│  Delta timestamps · SysEx fragmentation │
├─────────────────────────────────────────┤
│         Recovery Journal                │
│  System chapters (D,V,Q,F,X) ·         │
│  Channel chapters (P,C,M,W,N,E,T,A) ·  │
│  Checkpoint management                  │
├─────────────────────────────────────────┤
│           UDP Transport                 │
│  dart:io RawDatagramSocket · Control    │
│  port (even) + Data port (odd)          │
└─────────────────────────────────────────┘
```

The library follows **functional core / imperative shell**:

- **Functional core** — packet codecs, state machine, clock sync math are pure functions with no IO. Thoroughly unit tested.
- **Imperative shell** — UDP sockets, timers, and mDNS are thin wrappers that delegate all logic to the core.

## mDNS

Service discovery and registration use abstract interfaces (`MdnsBroadcaster` / `MdnsDiscoverer`). Implement them with your preferred mDNS library:

- **Flutter**: [bonsoir](https://pub.dev/packages/bonsoir)
- **Pure Dart**: [multicast_dns](https://pub.dev/packages/multicast_dns)

No-op implementations are provided for direct-connection-only use cases.

The service type is `_apple-midi._udp`.

## Session Lifecycle

```
idle → invitingControl → invitingData → connected → synchronizing → ready
                                                                      │
                                                              disconnecting
                                                                      │
                                                               disconnected
```

Sessions use a two-phase invitation (control port, then data port) followed by periodic CK0/CK1/CK2 clock synchronization, matching Apple's RTP-MIDI implementation.

Apple's CoreMIDI requires multiple rapid clock sync exchanges at startup before it routes MIDI. The library handles this automatically — `session.onReady` completes when the remote peer is ready to accept MIDI.

## Testing

720 tests covering all codecs, state machine, recovery journal (system + channel chapters), and MIDI roundtrip integration.

```bash
dart test                            # Run all tests
dart format --set-exit-if-changed .  # Check formatting
dart analyze --fatal-infos .         # Check for lint issues
```

For real-device validation against macOS Network MIDI:

```bash
# On the Mac: capture decoded MIDI output
brew install receivemidi
receivemidi dev "Network Session"

# From Dart: send every MIDI message type
dart run example/midi_message_test.dart 192.168.1.50 5004
```

## Apple Compatibility

Verified against macOS 26.3 Network MIDI (Audio MIDI Setup + MIDI Monitor). All MIDI 1.0 message types confirmed working: Note On/Off, Control Change, Program Change, Pitch Bend, Channel/Poly Aftertouch, SysEx, and all System Real-Time messages.

Key Apple-specific requirements handled automatically:
- Rapid startup clock sync (6 exchanges, matching [rtpmidid](https://github.com/davidmoreno/rtpmidid))
- RTP marker bit M=0 (RFC 6295)
- Random sequence number start (RFC 3550)

## Roadmap

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | **Session management** — invitation handshake, clock sync, bye, state machine | Done |
| 2 | **RTP MIDI payload** — send/receive MIDI messages, RTP header, delta timestamps, SysEx reassembly | Done |
| 3 | **Recovery journal: system chapters** — D, V, Q, F, X chapters for system message resilience | Done |
| 4 | **Recovery journal: channel chapters** — P, C, M, W, N, E, T, A chapters for channel message resilience | Done |
| 5 | **Integration + checkpoint management** — wire journal into send/receive pipeline, receiver feedback | Planned |
| 6 | **Polish + publish** — docs, examples, pub.dev package, CI, interop testing | Planned |

## License

MIT
