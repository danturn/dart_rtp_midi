/// Smoke test for RS (Receiver Feedback) journal trimming with Apple CoreMIDI.
///
/// Usage: `dart run example/rs_smoke_test.dart <ip> [port]`
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:dart_rtp_midi/src/session/rs_packet.dart';
import 'package:dart_rtp_midi/src/session/session_controller.dart';
import 'package:dart_rtp_midi/src/transport/udp_transport.dart';
import 'package:dart_rtp_midi/rtp_midi.dart';

class SpyTransport implements Transport {
  final UdpTransport _inner;
  final List<Uint8List> dataSends = [];

  SpyTransport(this._inner);

  @override
  int get controlPort => _inner.controlPort;
  @override
  int get dataPort => _inner.dataPort;
  @override
  Stream<Datagram> get onControlMessage => _inner.onControlMessage;
  @override
  Stream<Datagram> get onDataMessage => _inner.onDataMessage;
  @override
  Future<void> bind() => _inner.bind();
  @override
  Future<void> close() => _inner.close();

  @override
  void sendControl(Uint8List data, String address, int port) {
    _inner.sendControl(data, address, port);
  }

  @override
  void sendData(Uint8List data, String address, int port) {
    dataSends.add(Uint8List.fromList(data));
    _inner.sendData(data, address, port);
  }
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/rs_smoke_test.dart <ip> [port]');
    exit(1);
  }

  final address = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  print('RS Smoke Test — Trimming Validation');
  print('======================================\n');

  final transport = SpyTransport(UdpTransport());
  await transport.bind();

  final controller = SessionController(
    transport: transport,
    config: const RtpMidiConfig(name: 'RS Smoke Test'),
    localSsrc: 0xDEAD0001,
  );

  final rsPackets = <RsPacket>[];
  transport.onControlMessage.listen((datagram) {
    if (isRsPacket(datagram.data)) {
      final rs = RsPacket.decode(datagram.data);
      if (rs != null) rsPackets.add(rs);
    }
  });

  final readyCompleter = Completer<void>();
  controller.onStateChanged.listen((state) {
    if (state == SessionState.ready && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }
    if (state == SessionState.disconnected && !readyCompleter.isCompleted) {
      readyCompleter.completeError('Disconnected');
    }
  });

  await controller.invite(address, port);
  try {
    await readyCompleter.future.timeout(const Duration(seconds: 10));
  } catch (e) {
    print('FAIL: $e');
    await controller.dispose();
    await transport.close();
    exit(1);
  }
  print('Connected.\n');

  // --- Phase 1: Send diverse messages to build up state ---
  print('Phase 1: Building up journal state...');
  controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
  await Future.delayed(const Duration(milliseconds: 100));
  controller
      .sendMidi(const ControlChange(channel: 0, controller: 7, value: 80));
  await Future.delayed(const Duration(milliseconds: 100));
  controller.sendMidi(const ProgramChange(channel: 0, program: 42));
  await Future.delayed(const Duration(milliseconds: 100));
  controller.sendMidi(const PitchBend(channel: 0, value: 8192));
  await Future.delayed(const Duration(milliseconds: 100));
  controller.sendMidi(const ChannelAftertouch(channel: 0, pressure: 64));
  await Future.delayed(const Duration(milliseconds: 100));
  controller.sendMidi(const PolyAftertouch(channel: 0, note: 60, pressure: 50));
  await Future.delayed(const Duration(milliseconds: 100));
  controller.sendMidi(const NoteOn(channel: 9, note: 36, velocity: 127));
  await Future.delayed(const Duration(milliseconds: 100));

  final phase1Size = _lastJournalSize(transport.dataSends);
  print('  7 diverse messages sent. Journal: $phase1Size bytes');
  print('  (chapters N, C, P, W, T, A across 2 channels)');

  // --- Phase 2: Wait for Apple RS ---
  print('\nPhase 2: Waiting for Apple RS (up to 5s)...');
  final rsBefore = rsPackets.length;
  for (var i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    if (rsPackets.length > rsBefore) break;
  }

  final rsReceived = rsPackets.length - rsBefore;
  if (rsReceived > 0) {
    print('  Received $rsReceived RS packet(s)');
    for (final rs in rsPackets.skip(rsBefore)) {
      print('    seqnum=${rs.sequenceNumber}');
    }
  } else {
    print('  No RS received');
  }

  // --- Phase 3: Send one new message, measure ---
  print('\nPhase 3: Sending 1 new CC after RS...');
  controller
      .sendMidi(const ControlChange(channel: 0, controller: 1, value: 64));

  final phase3Size = _lastJournalSize(transport.dataSends);
  print('  Journal: $phase3Size bytes');

  // --- Results ---
  print('');
  print('=' * 50);
  if (rsReceived > 0) {
    print('Apple sent RS: YES ($rsReceived packets)');
    print('Journal before RS: $phase1Size bytes');
    print('Journal after RS:  $phase3Size bytes');
    if (phase3Size < phase1Size) {
      print('Trimming: PASS ($phase1Size → $phase3Size)');
    } else {
      print('Trimming: journal did not shrink');
      print('  (RS may have confirmed seqnum before our diverse messages)');
    }
  } else {
    print('Apple sent RS: NO');
    print('Journal encoding works: $phase1Size bytes');
  }
  print('=' * 50);

  await controller.disconnect();
  await controller.dispose();
  await transport.close();
}

int _lastJournalSize(List<Uint8List> sends) {
  for (var i = sends.length - 1; i >= 0; i--) {
    final payload = RtpMidiPayload.decode(sends[i]);
    if (payload != null && payload.journalData != null) {
      return payload.journalData!.length;
    }
  }
  return 0;
}
