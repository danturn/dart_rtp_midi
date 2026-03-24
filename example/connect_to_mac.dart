/// Connect to a macOS Network MIDI session.
///
/// Usage:
///   dart run example/connect_to_mac.dart [ip] [port]
///
/// Setup on the remote Mac:
///   1. Open Audio MIDI Setup > Window > Show MIDI Studio > double-click Network
///   2. Create a session (e.g. "Cubase MIDI"), tick the checkbox to enable it
///   3. Note the port (usually 5004)
///
/// Then run this on your local machine:
///   dart run example/connect_to_mac.dart 192.168.1.50 5004
library;

import 'dart:io';

import 'package:dart_rtp_midi/rtp_midi.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/connect_to_mac.dart <ip> [port]');
    print('');
    print('Example: dart run example/connect_to_mac.dart 192.168.1.50 5004');
    exit(1);
  }

  final address = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  print('Connecting to $address:$port ...');

  final client = RtpMidiClient(
    config: const RtpMidiConfig(name: 'Dart RTP-MIDI Test'),
  );

  try {
    final session = await client.connectToAddress(address, port);
    print('Connected to "${session.remoteName}" '
        'at ${session.remoteAddress}:${session.remoteControlPort}');
    print('State: ${session.state}');

    session.onStateChanged.listen((state) {
      print('State changed: $state');
      if (state == SessionState.disconnected) {
        print('Session ended.');
        exit(0);
      }
    });

    print('');
    print('Session is active. Press Ctrl+C to disconnect.');
    print('(MIDI send/receive is not yet implemented — Phase 2)');

    // Keep alive until Ctrl+C
    ProcessSignal.sigint.watch().listen((_) async {
      print('\nDisconnecting...');
      await session.disconnect();
      await client.dispose();
      exit(0);
    });
  } catch (e) {
    print('Failed to connect: $e');
    await client.dispose();
    exit(1);
  }
}
