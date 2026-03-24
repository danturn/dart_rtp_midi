# dart_rtp_midi

Cross-platform [RTP-MIDI](https://www.rfc-editor.org/rfc/rfc6295) implementation in pure Dart. Network MIDI transport for iOS, Android, macOS, Windows, and Linux.

The first open-source RTP-MIDI library for Dart/Flutter — connect to macOS Network MIDI sessions, rtpMIDI (Windows), DAWs, and hardware over WiFi.

## Status: Work in Progress

> **This library is under active development and is not yet ready for production use.**
>
> **What works now (Phase 1):**
> - Session discovery, invitation handshake (IN/OK/NO/BY), and graceful disconnect
> - Clock synchronization (CK0/CK1/CK2 three-way exchange)
> - Host mode (accept inbound connections) and Client mode (discover/connect outbound)
> - Full state machine with exponential backoff retries
>
> **What does NOT work yet:**
> - Sending or receiving MIDI messages (Phase 2)
> - Recovery journal for packet loss resilience (Phases 3-4)
> - SysEx fragmentation/reassembly
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
  print('Connected: ${session.remoteName} (${session.remoteAddress})');
  session.onStateChanged.listen((state) {
    print('State: $state');
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

// Or discover via mDNS (requires MdnsDiscoverer implementation)
client.discoverSessions().listen((service) {
  print('Found: ${service.name} at ${service.address}:${service.port}');
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

## Compatibility Targets

Will be tested against (once MIDI payload is implemented):
- macOS Audio MIDI Setup (Network MIDI)
- rtpMIDI for Windows
- Cubase, Logic Pro

## Roadmap

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | **Session management** — invitation handshake, clock sync, bye, state machine | Done |
| 2 | **RTP MIDI payload** — send/receive MIDI messages, RTP header, delta timestamps, SysEx fragmentation | Next |
| 3 | **Recovery journal: system chapters** — D, V, Q, F, X chapters for system message resilience | Planned |
| 4 | **Recovery journal: channel chapters** — P, C, M, W, N, E, T, A chapters for channel message resilience | Planned |
| 5 | **Integration + checkpoint management** — wire journal into send/receive pipeline, receiver feedback | Planned |
| 6 | **Polish + publish** — docs, examples, pub.dev package, CI, interop testing | Planned |

## License

MIT
