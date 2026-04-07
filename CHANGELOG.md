## 0.1.0

- Initial release
- Session lifecycle: invitation handshake (IN/OK/NO/BY), clock sync (CK0/CK1/CK2), graceful disconnect
- Host mode (accept inbound) and Client mode (discover/connect outbound)
- All MIDI 1.0 messages: channel voice, system common, system real-time, SysEx with reassembly
- Recovery journal: system chapters (D, V, Q, F, X) and channel chapters (P, C, M, W, N, E, T, A)
- Packet loss detection with corrective MIDI emission
- Apple CoreMIDI compatibility (rapid startup sync, RFC-compliant headers)
- Abstract mDNS interfaces for pluggable service discovery
