/// Host an RTP-MIDI session and wait for incoming connections.
///
/// Usage:
///   dart run example/host_session.dart [port]
///
/// Then on the remote Mac:
///   1. Open Audio MIDI Setup > Window > Show MIDI Studio > double-click Network
///   2. Under "Directory", click "+" to add a contact
///   3. Enter this machine's IP address and the port shown below
///   4. Select the contact and click "Connect"
library;

import 'dart:io';

import 'package:rtp_midi/rtp_midi.dart';

void main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 5004;

  final host = RtpMidiHost(
    config: RtpMidiConfig(name: 'Dart RTP-MIDI Host', port: port),
  );

  await host.start();

  // Show local IP addresses so you know what to enter on the other Mac
  final interfaces = await NetworkInterface.list();
  final ips = interfaces
      .expand((i) => i.addresses)
      .where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback)
      .map((a) => a.address)
      .toList();

  print('RTP-MIDI Host started');
  print('  Name: Dart RTP-MIDI Host');
  print('  Control port: ${host.controlPort}');
  print('  Data port:    ${host.dataPort}');
  print('  Local IPs:    ${ips.join(", ")}');
  print('');
  print('On the other Mac, add a contact with one of the IPs above');
  print('and port ${host.controlPort}, then click Connect.');
  print('');
  print('Waiting for connections... (Ctrl+C to stop)');

  host.onSessionConnected.listen((session) {
    print('');
    print('>>> Session connected: "${session.remoteName}" '
        'from ${session.remoteAddress}:${session.remoteControlPort}');
    print('    State: ${session.state}');

    session.onStateChanged.listen((state) {
      print('    [${session.remoteName}] State: $state');
    });
  });

  ProcessSignal.sigint.watch().listen((_) async {
    print('\nStopping host...');
    await host.stop();
    exit(0);
  });
}
