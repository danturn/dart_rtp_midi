/// Same as replay_apple.dart but using IPv6 link-local (like Apple does).
///
/// Usage: dart run tool/replay_ipv6.dart
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  // Cubase Mac's link-local IPv6 (from tcpdump capture).
  // Use numeric scope ID for local en0 interface.
  final scopeId = args.isNotEmpty ? args[0] : '14';
  final targetAddr = 'fe80::14bd:9902:492a:f2a3%$scopeId';

  print('Trying to resolve: $targetAddr');

  final target = InternetAddress(targetAddr);
  print('Resolved: ${target.address}, type: ${target.type}');

  final controlPort = 5004;
  final dataPort = 5005;

  // Bind to our own link-local address (required for fe80:: routing).
  final localAddr = InternetAddress('fe80::bc:8458:36c0:7b32%$scopeId');
  final ctrlSock = await RawDatagramSocket.bind(localAddr, 0);
  final dataSock = await RawDatagramSocket.bind(localAddr, ctrlSock.port + 1);

  print('Local ports: control=${ctrlSock.port}, data=${dataSock.port}');

  final ctrlQueue = _PacketQueue(ctrlSock);
  final dataQueue = _PacketQueue(dataSock);

  const ssrc = 0xAABBCCDD;
  const token = 0x12345678;

  // --- Handshake ---
  print('1. Control IN...');
  ctrlSock.send(_buildIN(token, ssrc, 'Dart IPv6'), target, controlPort);

  final ctrlOk = await ctrlQueue.waitFor(
      'ctrl OK', (d) => d.length >= 4 && d[2] == 0x4F && d[3] == 0x4B);
  if (ctrlOk == null) {
    print('FAILED');
    exit(1);
  }

  print('2. Data IN...');
  dataSock.send(_buildIN(token, ssrc, 'Dart IPv6'), target, dataPort);

  final dataOk = await dataQueue.waitFor(
      'data OK', (d) => d.length >= 4 && d[2] == 0x4F && d[3] == 0x4B);
  if (dataOk == null) {
    print('FAILED');
    exit(1);
  }

  // --- Clock sync ---
  print('3. CK0...');
  final t1 = DateTime.now().microsecondsSinceEpoch ~/ 100;
  dataSock.send(_buildCK0(ssrc, t1), target, dataPort);

  final ck1 = await dataQueue.waitFor('CK1',
      (d) => d.length >= 36 && d[2] == 0x43 && d[3] == 0x4B && d[8] == 1);
  if (ck1 == null) {
    print('FAILED');
    exit(1);
  }

  print('4. CK2...');
  final t3 = DateTime.now().microsecondsSinceEpoch ~/ 100;
  dataSock.send(_buildCK2(ssrc, ck1, t3), target, dataPort);

  print('Session established. Waiting 5s...');
  await Future.delayed(const Duration(seconds: 5));

  // --- Send MIDI ---
  final ts = DateTime.now().microsecondsSinceEpoch ~/ 100 & 0xFFFFFFFF;
  final midi = Uint8List(16);
  final mv = ByteData.sublistView(midi);
  midi[0] = 0x80;
  midi[1] = 0x61;
  mv.setUint16(2, 0x1000);
  mv.setUint32(4, ts);
  mv.setUint32(8, ssrc);
  midi[12] = 0x03;
  midi[13] = 0x90;
  midi[14] = 0x3C;
  midi[15] = 0x64;

  print('5. Sending MIDI: ${_hex(midi)}');
  dataSock.send(midi, target, dataPort);

  print('Waiting 10s...');
  await Future.delayed(const Duration(seconds: 10));

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
          print('  << recv (${data.length}b): ${_hex(data)}');
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
    for (var i = 0; i < _packets.length; i++) {
      if (matcher(_packets[i])) {
        final p = _packets.removeAt(i);
        print('  >> $label OK');
        return p;
      }
    }
    final c = Completer<Uint8List>();
    _waiters.add(c);
    try {
      final data = await c.future.timeout(const Duration(seconds: 5));
      if (matcher(data)) {
        print('  >> $label OK');
        return data;
      }
      print('  >> $label: unexpected packet');
      return null;
    } on TimeoutException {
      print('  >> $label: timeout');
      return null;
    }
  }

  void dispose() {
    for (final c in _waiters) {
      if (!c.isCompleted) c.complete(Uint8List(0));
    }
  }
}

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
