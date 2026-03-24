/// Runs as an RTP-MIDI host. The Mac connects TO us via Audio MIDI Setup.
///
/// Usage: dart run tool/host_test.dart [port]
///
/// Then on the Mac: Audio MIDI Setup > Network > add this machine
/// to the Directory, select it, click Connect.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_rtp_midi/rtp_midi.dart';

void main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 5004;

  final host = RtpMidiHost(
    config: RtpMidiConfig(name: 'Dart Host Test', port: port),
  );

  await host.start();
  print('Hosting on port $port (data: ${port + 1})');
  print('Local IP: ${await _getLocalIP()}');
  print('');
  print('On the Mac:');
  print('  1. Audio MIDI Setup > Network');
  print('  2. Under "Sessions and Directories", click "+"');
  print('  3. Enter this machine\'s IP and port $port');
  print('  4. Select it and click "Connect"');
  print('');
  print('Waiting for connection...');
  print('(Sessions: ${host.sessions.length})');

  host.onSessionConnected.listen((session) {
    print('');
    print('Connected: ${session.remoteName} (${session.remoteAddress})');

    session.onStateChanged.listen((state) {
      print('State: $state');

      if (state == SessionState.ready) {
        print('');
        print('Session ready! Sending Note On C4...');
        session.send(const NoteOn(channel: 0, note: 60, velocity: 100));
        print('Sent.');

        // Also listen for incoming MIDI.
        session.onMidiMessage.listen((msg) {
          print('MIDI received: $msg');
        });
      }
    });
  });

  // Keep alive.
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await host.stop();
    exit(0);
  });
}

Future<String> _getLocalIP() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }
  return '127.0.0.1';
}
