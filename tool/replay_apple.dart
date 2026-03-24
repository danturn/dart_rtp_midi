/// Replays a session handshake + MIDI Note On using raw UDP.
/// No library code. Minimal, hardcoded bytes.
///
/// Usage: dart run tool/replay_apple.dart [ip] [port]
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  final address = args.isNotEmpty ? args[0] : '192.168.1.89';
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  final target = InternetAddress(address);
  final controlPort = port;
  final dataPort = port + 1;

  final ctrlSock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  // Bind data socket to ctrl+1 to maintain even/odd convention.
  final dataSock =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, ctrlSock.port + 1);

  print('Local ports: control=${ctrlSock.port}, data=${dataSock.port}');

  // Queue incoming packets for each socket.
  final ctrlQueue = _PacketQueue(ctrlSock);
  final dataQueue = _PacketQueue(dataSock);

  const ssrc = 0xAABBCCDD;
  const token = 0x12345678;

  // --- Handshake ---
  print('1. Control IN...');
  ctrlSock.send(_buildIN(token, ssrc, 'Dart Replay'), target, controlPort);
  final ctrlOk = await ctrlQueue.waitFor(
      'ctrl OK', (d) => d.length >= 4 && d[2] == 0x4F && d[3] == 0x4B);
  if (ctrlOk == null) exit(1);

  print('2. Data IN...');
  dataSock.send(_buildIN(token, ssrc, 'Dart Replay'), target, dataPort);
  final dataOk = await dataQueue.waitFor(
      'data OK', (d) => d.length >= 4 && d[2] == 0x4F && d[3] == 0x4B);
  if (dataOk == null) exit(1);

  // --- Clock sync ---
  print('3. CK0...');
  final t1 = DateTime.now().microsecondsSinceEpoch ~/ 100;
  dataSock.send(_buildCK0(ssrc, t1), target, dataPort);

  final ck1 = await dataQueue.waitFor('CK1',
      (d) => d.length >= 36 && d[2] == 0x43 && d[3] == 0x4B && d[8] == 1);
  if (ck1 == null) exit(1);

  print('4. CK2...');
  final t3 = DateTime.now().microsecondsSinceEpoch ~/ 100;
  dataSock.send(_buildCK2(ssrc, ck1, t3), target, dataPort);

  print('Session established. Waiting 5s...');
  await Future.delayed(const Duration(seconds: 5));

  // --- Send MIDI ---
  final ts = DateTime.now().microsecondsSinceEpoch ~/ 100 & 0xFFFFFFFF;
  final midi = Uint8List(16);
  final mv = ByteData.sublistView(midi);
  midi[0] = 0x80; // V=2
  midi[1] = 0x61; // M=0, PT=97
  mv.setUint16(2, 0x1000); // seq
  mv.setUint32(4, ts);
  mv.setUint32(8, ssrc);
  midi[12] = 0x03; // J=0, LEN=3
  midi[13] = 0x90; // Note On
  midi[14] = 0x3C; // C4
  midi[15] = 0x64; // vel 100

  print('5. Sending MIDI: ${_hex(midi)}');
  dataSock.send(midi, target, dataPort);

  print('Waiting 10s...');
  await Future.delayed(const Duration(seconds: 10));

  // --- Disconnect ---
  print('6. BYE');
  ctrlSock.send(_buildBYE(ssrc), target, controlPort);
  dataSock.send(_buildBYE(ssrc), target, dataPort);
  await Future.delayed(const Duration(milliseconds: 500));

  ctrlQueue.dispose();
  dataQueue.dispose();
  ctrlSock.close();
  dataSock.close();
  print('Done.');
}

// --- Packet queue (single listener per socket) ---

class _PacketQueue {
  final RawDatagramSocket _socket;
  final _packets = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];

  _PacketQueue(this._socket) {
    _socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket.receive();
        if (dg != null) {
          final data = Uint8List.fromList(dg.data);
          if (_waiters.isNotEmpty) {
            _waiters.removeAt(0).complete(data);
          } else {
            _packets.add(data);
          }
        }
      }
    });
  }

  Future<Uint8List?> waitFor(
      String label, bool Function(Uint8List) matcher) async {
    // Check buffered packets first.
    for (var i = 0; i < _packets.length; i++) {
      if (matcher(_packets[i])) {
        final p = _packets.removeAt(i);
        print('<< $label: ${_hex(p)}');
        return p;
      }
    }
    // Wait for new packet.
    final completer = Completer<Uint8List>();
    _waiters.add(completer);
    try {
      final data = await completer.future.timeout(const Duration(seconds: 5));
      print('<< $label: ${_hex(data)}');
      if (matcher(data)) return data;
      print('Unexpected packet for $label');
      return null;
    } on TimeoutException {
      print('Timeout waiting for $label');
      return null;
    }
  }

  void dispose() {
    for (final c in _waiters) {
      if (!c.isCompleted) c.complete(Uint8List(0));
    }
  }
}

// --- Packet builders ---

Uint8List _buildIN(int token, int ssrc, String name) {
  final nb = name.codeUnits;
  final d = Uint8List(16 + nb.length + 1);
  final v = ByteData.sublistView(d);
  v.setUint16(0, 0xFFFF);
  v.setUint16(2, 0x494E);
  v.setUint32(4, 2);
  v.setUint32(8, token);
  v.setUint32(12, ssrc);
  d.setRange(16, 16 + nb.length, nb);
  return d;
}

Uint8List _buildBYE(int ssrc) {
  final d = Uint8List(16);
  final v = ByteData.sublistView(d);
  v.setUint16(0, 0xFFFF);
  v.setUint16(2, 0x4259);
  v.setUint32(4, 2);
  v.setUint32(12, ssrc);
  return d;
}

Uint8List _buildCK0(int ssrc, int t1) {
  final d = Uint8List(36);
  final v = ByteData.sublistView(d);
  v.setUint16(0, 0xFFFF);
  v.setUint16(2, 0x434B);
  v.setUint32(4, ssrc);
  v.setUint32(12, (t1 >> 32) & 0xFFFFFFFF);
  v.setUint32(16, t1 & 0xFFFFFFFF);
  return d;
}

Uint8List _buildCK2(int ssrc, Uint8List ck1, int t3) {
  final d = Uint8List(36);
  final v = ByteData.sublistView(d);
  v.setUint16(0, 0xFFFF);
  v.setUint16(2, 0x434B);
  v.setUint32(4, ssrc);
  d[8] = 2;
  d.setRange(12, 28, ck1.sublist(12, 28));
  v.setUint32(28, (t3 >> 32) & 0xFFFFFFFF);
  v.setUint32(32, t3 & 0xFFFFFFFF);
  return d;
}

String _hex(Uint8List data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
