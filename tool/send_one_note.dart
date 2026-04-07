/// Connects, sends one Note On C4, waits, disconnects. Nothing else.
///
/// Usage: dart run tool/send_one_note.dart [ip] [port]
library;

import 'dart:async';
import 'dart:io';

import 'package:rtp_midi/rtp_midi.dart';
import 'package:rtp_midi/src/session/session_controller.dart';
import 'package:rtp_midi/src/transport/udp_transport.dart';

void main(List<String> args) async {
  final address = args.isNotEmpty ? args[0] : '192.168.1.89';
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  final isIPv6 = address.contains(':');
  final transport = UdpTransport(
    port: 0,
    bindAddress: isIPv6 ? '::' : '0.0.0.0',
  );
  await transport.bind();

  final controller = SessionController(
    transport: transport,
    config: const RtpMidiConfig(name: 'Dart Note Test'),
    localSsrc: DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF,
  );

  await controller.invite(address, port);

  try {
    await controller.onStateChanged
        .firstWhere((s) => s == SessionState.ready)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    print('Timed out');
    exit(1);
  }

  // Wait for startup sync exchanges to complete (Apple needs multiple).
  print('Ready. Waiting for startup sync...');
  await controller.onReady;

  print('Sending Note On C4...');
  controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
  print('Sent. Waiting 5s...');

  await Future.delayed(const Duration(seconds: 5));

  await controller.disconnect();
  await Future.delayed(const Duration(milliseconds: 500));
  await controller.dispose();
  await transport.close();
  print('Done.');
}
