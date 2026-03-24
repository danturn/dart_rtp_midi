/// Loopback test: host + client on localhost.
///
/// Validates the full invitation + clock sync handshake
/// without needing a second machine.
///
/// Usage:
///   dart run example/loopback_test.dart
library;

import 'dart:io';

import 'package:dart_rtp_midi/rtp_midi.dart';

void main() async {
  print('=== RTP-MIDI Loopback Test ===');
  print('');

  // Start a host
  final host = RtpMidiHost(
    config: const RtpMidiConfig(name: 'Loopback Host', port: 5004),
  );
  await host.start();
  print('[Host] Listening on port ${host.controlPort}/${host.dataPort}');

  host.onSessionConnected.listen((session) {
    print('[Host] Inbound session from "${session.remoteName}" '
        '(${session.remoteAddress})');
    session.onStateChanged.listen((state) {
      print('[Host] Session state: $state');
    });
  });

  // Connect a client to the host
  final client = RtpMidiClient(
    config: const RtpMidiConfig(name: 'Loopback Client'),
  );

  print('[Client] Connecting to localhost:${host.controlPort}...');

  try {
    final session =
        await client.connectToAddress('127.0.0.1', host.controlPort);
    print('[Client] Connected to "${session.remoteName}"');
    print('[Client] State: ${session.state}');

    session.onStateChanged.listen((state) {
      print('[Client] Session state: $state');
    });

    // Let clock sync run for a few cycles
    print('');
    print('Session established. Letting clock sync run for 5 seconds...');
    await Future<void>.delayed(const Duration(seconds: 5));

    print('');
    print('Disconnecting...');
    await session.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } catch (e) {
    print('[Client] Failed: $e');
  }

  await client.dispose();
  await host.stop();
  print('');
  print('=== Test complete ===');
  exit(0);
}
