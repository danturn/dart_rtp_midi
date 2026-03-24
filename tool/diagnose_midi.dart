/// Diagnostic tool: connects, sends one Note On, and logs all raw bytes.
///
/// Usage: dart run tool/diagnose_midi.dart [ip] [port]
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_rtp_midi/rtp_midi.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_header.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:dart_rtp_midi/src/session/session_controller.dart';
import 'package:dart_rtp_midi/src/transport/udp_transport.dart';

/// A transport wrapper that logs all sent/received data.
class LoggingTransport implements Transport {
  final Transport _inner;

  LoggingTransport(this._inner);

  @override
  int get controlPort => _inner.controlPort;
  @override
  int get dataPort => _inner.dataPort;
  @override
  Stream<Datagram> get onControlMessage => _inner.onControlMessage;
  @override
  Stream<Datagram> get onDataMessage => _inner.onDataMessage.map((d) {
        _logReceived('DATA', d);
        return d;
      });
  @override
  Future<void> bind() => _inner.bind();
  @override
  Future<void> close() => _inner.close();

  @override
  void sendControl(Uint8List data, String address, int port) {
    _logSent('CTRL', data, address, port);
    _inner.sendControl(data, address, port);
  }

  @override
  void sendData(Uint8List data, String address, int port) {
    _logSent('DATA', data, address, port);
    _inner.sendData(data, address, port);
  }

  void _logSent(String label, Uint8List data, String address, int port) {
    final hex = _hex(data);
    final desc = _describe(data);
    print('>> SEND $label to $address:$port (${data.length} bytes)');
    print('   $hex');
    if (desc.isNotEmpty) print('   $desc');
    print('');
  }

  void _logReceived(String label, Datagram d) {
    final hex = _hex(d.data);
    final desc = _describe(d.data);
    print(
        '<< RECV $label from ${d.address}:${d.port} (${d.data.length} bytes)');
    print('   $hex');
    if (desc.isNotEmpty) print('   $desc');
    print('');
  }

  String _hex(Uint8List data) {
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String _describe(Uint8List data) {
    if (data.length < 2) return '';

    // Check for session protocol (0xFFFF signature)
    if (data.length >= 4 && data[0] == 0xFF && data[1] == 0xFF) {
      final cmd = String.fromCharCodes([data[2], data[3]]);
      return '[Session: $cmd]';
    }

    // Check for RTP (version 2)
    if (data.length >= 13 && (data[0] & 0xC0) == 0x80) {
      final header = RtpHeader.decode(data);
      if (header != null) {
        final payload = RtpMidiPayload.decode(data);
        if (payload != null) {
          final cmds = payload.commands.map((c) => c.message).join(', ');
          return '[RTP-MIDI: seq=${header.sequenceNumber}, '
              'ts=${header.timestamp}, ssrc=0x${header.ssrc.toRadixString(16)}, '
              'M=${header.marker ? 1 : 0}, PT=${header.payloadType}, '
              'midi=[$cmds]]';
        }
        return '[RTP: seq=${header.sequenceNumber}, ts=${header.timestamp}]';
      }
    }

    return '';
  }
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/diagnose_midi.dart <ip> [port]');
    exit(1);
  }

  final address = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  print('=== RTP-MIDI Diagnostic ===');
  print('Target: $address:$port');
  print('');

  // Create transport with logging wrapper.
  final isIPv6 = address.contains(':');
  final inner = UdpTransport(
    port: 0,
    bindAddress: isIPv6 ? '::' : '0.0.0.0',
  );
  final transport = LoggingTransport(inner);
  await transport.bind();
  print(
      'Local ports: control=${transport.controlPort}, data=${transport.dataPort}');
  print('');

  // Create session controller manually to use our logging transport.
  const config = RtpMidiConfig(name: 'Dart Diagnostic');
  final ssrc = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
  final controller = SessionController(
    transport: transport,
    config: config,
    localSsrc: ssrc,
  );
  print('Local SSRC: 0x${ssrc.toRadixString(16)}');
  print('');

  controller.onStateChanged.listen((state) {
    print('--- State: $state ---');
    print('');
  });

  controller.onMidiMessage.listen((msg) {
    print('*** MIDI RECEIVED: $msg ***');
    print('');
  });

  // Connect
  print('Connecting...');
  await controller.invite(address, port);

  // Wait for ready
  try {
    await controller.onStateChanged
        .firstWhere((s) => s == SessionState.ready)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    print('ERROR: Timed out waiting for ready state');
    print('Final state: ${controller.state}');
    await controller.dispose();
    await transport.close();
    exit(1);
  }

  print('=== Session ready. Waiting 2s before sending... ===');
  print('');
  await Future.delayed(const Duration(seconds: 2));

  // --- Test 1: Normal packet (J=0, no journal) ---
  print('--- Test 1: Normal packet (J=0) ---');
  controller.sendMidi(const NoteOn(channel: 0, note: 60, velocity: 100));
  await Future.delayed(const Duration(seconds: 1));

  // --- Test 2: Exact bytes captured from working Apple-to-Apple transfer ---
  // (with our SSRC swapped in)
  print('--- Test 2: Exact Apple captured packet (our SSRC) ---');
  final applePacket = Uint8List.fromList([
    0x80, 0x61, 0xa8, 0xb7, 0x00, 0x0c, 0x49, 0xa5,
    // SSRC - use ours:
    (ssrc >> 24) & 0xFF, (ssrc >> 16) & 0xFF, (ssrc >> 8) & 0xFF, ssrc & 0xFF,
    0x43, 0x90, 0x3c, 0x64,
    0x20, 0xa8, 0xb7, 0x00, 0x07, 0x08, 0x81, 0xf1, 0x3c, 0x64,
  ]);
  transport.sendData(
      applePacket, controller.remoteAddress, controller.remoteDataPort);
  await Future.delayed(const Duration(seconds: 1));

  // --- Test 2b: Exact Apple bytes, COMPLETELY unmodified (Apple's original SSRC) ---
  print('--- Test 2b: Exact Apple captured packet (original SSRC) ---');
  final appleExact = Uint8List.fromList([
    0x80, 0x61, 0xa8, 0xb7, 0x00, 0x0c, 0x49, 0xa5,
    0x11, 0x92, 0xf8, 0x3e, // Apple's original SSRC
    0x43, 0x90, 0x3c, 0x64,
    0x20, 0xa8, 0xb7, 0x00, 0x07, 0x08, 0x81, 0xf1, 0x3c, 0x64,
  ]);
  transport.sendData(
      appleExact, controller.remoteAddress, controller.remoteDataPort);
  await Future.delayed(const Duration(seconds: 1));

  // --- Test 3: Another normal packet ---
  print('--- Test 3: Normal Note Off ---');
  controller.sendMidi(const NoteOff(channel: 0, note: 60, velocity: 0));
  await Future.delayed(const Duration(seconds: 1));

  // Keep alive to receive any incoming MIDI.
  print('');
  print('=== All sent. Waiting 10s for incoming MIDI... ===');
  print('');
  await Future.delayed(const Duration(seconds: 10));

  print('=== Disconnecting ===');
  await controller.disconnect();
  await Future.delayed(const Duration(seconds: 1));
  await controller.dispose();
  await transport.close();
}

/// Send a hand-crafted RTP-MIDI packet matching Apple's exact format.
///
/// Apple's Note On packet:
/// 80 61 [seq] [ts] [ssrc] 43 90 3c 64 20 [seq] 00 07 08 81 f1 3c 64
///
/// Journal structure: A=1, 1 channel journal with N chapter (Note On).
void _sendRawAppleFormat(
  LoggingTransport transport,
  SessionController controller,
  int ssrc,
  int seqNum,
) {
  final timestamp = DateTime.now().microsecondsSinceEpoch ~/ 100 & 0xFFFFFFFF;

  // 12 (RTP) + 1 (MIDI header) + 3 (MIDI data) + 10 (journal) = 26 bytes
  // Matches Apple's packet size exactly.
  final packet = Uint8List(26);
  final view = ByteData.sublistView(packet);

  // RTP header (12 bytes)
  packet[0] = 0x80; // V=2, P=0, X=0, CC=0
  packet[1] = 0x61; // M=0, PT=97
  view.setUint16(2, seqNum & 0xFFFF);
  view.setUint32(4, timestamp);
  view.setUint32(8, ssrc);

  // MIDI command section header: B=0, J=1, Z=0, P=0, LEN=3
  packet[12] = 0x43;

  // MIDI data: Note On C4 vel=100
  packet[13] = 0x90;
  packet[14] = 0x3C;
  packet[15] = 0x64;

  // Recovery journal (10 bytes, matching Apple's format):
  // Journal header (3 bytes): S=0, Y=0, A=1, H=0, TOTCHAN=0
  packet[16] = 0x20; // A=1 (channel journals follow)
  view.setUint16(17, seqNum & 0xFFFF); // checkpoint seqnum = this packet

  // Channel journal (7 bytes):
  // Channel journal header (3 bytes)
  packet[19] = 0x00; // S=0, chan=0, H=0
  packet[20] = 0x07; // LENGTH low byte = 7 (total channel journal length)
  packet[21] = 0x08; // Chapter presence: N chapter only (bit 3)

  // N chapter (Note chapter, 4 bytes):
  // N chapter header: B=1 (low/high split), LEN=0, LOW=0, HIGH=127
  packet[22] = 0x81; // B=1, LEN=1 (1 note log)
  packet[23] = 0xF1; // LOW=0x3C? Actually let me match Apple exactly
  // Actually let me just copy Apple's exact journal bytes
  // Apple sent: 20 a8 b7 00 07 08 81 f1 3c 64
  // I'll use same structure but with our seqnum

  // Actually, let me just hardcode Apple's journal structure with adapted seqnum
  packet[16] = 0x20; // S=0, Y=0, A=1, H=0, TOTCHAN=0
  view.setUint16(17, seqNum & 0xFFFF); // checkpoint = our seq
  packet[19] = 0x00; // S=0, chan=0 (bits 6-3), H=0, len high=0
  packet[20] = 0x07; // len low = 7
  packet[21] = 0x08; // chapters: N present
  packet[22] = 0x81; // N chapter: B=1, LEN=1
  packet[23] = 0xF1; // LOW=0x3C (note 60 region), HIGH flags
  packet[24] = 0x3C; // note number 60
  packet[25] = 0x64; // velocity 100

  transport.sendData(
    packet,
    controller.remoteAddress,
    controller.remoteDataPort,
  );
}
