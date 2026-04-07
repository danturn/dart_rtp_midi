/// Connects to a remote RTP-MIDI session and prints received MIDI messages,
/// one per line, in a stable format suitable for automated diffing.
///
/// Used by tool/e2e_midi_test.sh for the receive-direction test.
///
/// Usage: dart run tool/midi_listener.dart [ip] [port]
library;

import 'dart:async';
import 'dart:io';

import 'package:rtp_midi/rtp_midi.dart';

void main(List<String> args) async {
  final address = args.isNotEmpty ? args[0] : '127.0.0.1';
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  final client = RtpMidiClient(
    config: const RtpMidiConfig(name: 'Dart MIDI Listener'),
  );

  try {
    final session = await client.connectToAddress(address, port);

    if (session.state != SessionState.ready) {
      await session.onStateChanged
          .firstWhere((s) => s == SessionState.ready)
          .timeout(const Duration(seconds: 10));
    }

    // Print each received message on its own line.
    session.onMidiMessage.listen((msg) {
      stdout.writeln(msg.toString());
    });

    // Stay alive until killed by the test script.
    await Future.delayed(const Duration(seconds: 30));

    await session.disconnect();
    await client.dispose();
  } catch (e) {
    stderr.writeln('Error: $e');
    await client.dispose();
    exit(1);
  }
}
