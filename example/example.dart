/// Minimal RTP-MIDI example: host a session and echo incoming MIDI.
///
/// Usage:
///   dart run example/example.dart
library;

import 'package:rtp_midi/rtp_midi.dart';

void main() async {
  final host = RtpMidiHost(
    config: const RtpMidiConfig(name: 'Dart RTP-MIDI', port: 5004),
  );

  await host.start();
  print('Listening on port ${host.controlPort}');

  host.onSessionConnected.listen((session) {
    print('Connected: ${session.remoteName}');

    session.onMidiMessage.listen((msg) {
      print('Received: $msg');
      // Echo it back
      session.send(msg);
    });

    session.onStateChanged.listen((state) {
      if (state == SessionState.ready) {
        session.send(const NoteOn(channel: 0, note: 60, velocity: 100));
      }
    });
  });
}
