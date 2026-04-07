import 'dart:typed_data';

import 'package:rtp_midi/src/session/rs_packet.dart';
import 'package:test/test.dart';

void main() {
  group('RsPacket', () {
    test('encode produces 12 bytes', () {
      const packet = RsPacket(ssrc: 0x11111111, sequenceNumber: 100);
      expect(packet.encode().length, 12);
    });

    test('encode has correct signature', () {
      const packet = RsPacket(ssrc: 0x11111111, sequenceNumber: 100);
      final bytes = packet.encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint16(0), 0xFFFF);
    });

    test('encode has correct command code', () {
      const packet = RsPacket(ssrc: 0x11111111, sequenceNumber: 100);
      final bytes = packet.encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint16(2), 0x5253);
    });

    test('encode has correct SSRC', () {
      const packet = RsPacket(ssrc: 0xDEADBEEF, sequenceNumber: 100);
      final bytes = packet.encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint32(4), 0xDEADBEEF);
    });

    test('encode puts seqnum in upper 16 bits of offset 8', () {
      const packet = RsPacket(ssrc: 0x11111111, sequenceNumber: 42);
      final bytes = packet.encode();
      final view = ByteData.sublistView(bytes);
      // Upper 16 bits: seqnum shifted left by 16
      expect(view.getUint16(8), 42);
      expect(view.getUint16(10), 0); // lower 16 bits are zero
    });

    test('decode roundtrips correctly', () {
      const original = RsPacket(ssrc: 0x22222222, sequenceNumber: 1000);
      final decoded = RsPacket.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.ssrc, 0x22222222);
      expect(decoded.sequenceNumber, 1000);
    });

    test('decode returns null for too-short data', () {
      expect(RsPacket.decode(Uint8List(11)), isNull);
    });

    test('decode returns null for wrong signature', () {
      final bytes = Uint8List(12);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0x1234); // wrong signature
      view.setUint16(2, 0x5253);
      expect(RsPacket.decode(bytes), isNull);
    });

    test('decode returns null for wrong command', () {
      final bytes = Uint8List(12);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0xFFFF);
      view.setUint16(2, 0x494E); // "IN" not "RS"
      expect(RsPacket.decode(bytes), isNull);
    });

    test('equality', () {
      const a = RsPacket(ssrc: 0x1111, sequenceNumber: 42);
      const b = RsPacket(ssrc: 0x1111, sequenceNumber: 42);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when ssrc differs', () {
      const a = RsPacket(ssrc: 0x1111, sequenceNumber: 42);
      const b = RsPacket(ssrc: 0x2222, sequenceNumber: 42);
      expect(a, isNot(equals(b)));
    });

    test('inequality when seqnum differs', () {
      const a = RsPacket(ssrc: 0x1111, sequenceNumber: 42);
      const b = RsPacket(ssrc: 0x1111, sequenceNumber: 43);
      expect(a, isNot(equals(b)));
    });

    test('seqnum wraps at uint16 max', () {
      const packet = RsPacket(ssrc: 0x1111, sequenceNumber: 65535);
      final decoded = RsPacket.decode(packet.encode());
      expect(decoded!.sequenceNumber, 65535);
    });

    test('seqnum zero roundtrips', () {
      const packet = RsPacket(ssrc: 0x1111, sequenceNumber: 0);
      final decoded = RsPacket.decode(packet.encode());
      expect(decoded!.sequenceNumber, 0);
    });
  });

  group('isRsPacket', () {
    test('returns true for valid RS packet', () {
      const packet = RsPacket(ssrc: 0x1111, sequenceNumber: 42);
      expect(isRsPacket(packet.encode()), isTrue);
    });

    test('returns false for wrong size', () {
      expect(isRsPacket(Uint8List(11)), isFalse);
      expect(isRsPacket(Uint8List(13)), isFalse);
    });

    test('returns false for exchange packet', () {
      // Build a minimal exchange-like packet (17+ bytes)
      final bytes = Uint8List(12);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0xFFFF);
      view.setUint16(2, 0x494E); // "IN"
      expect(isRsPacket(bytes), isFalse);
    });

    test('returns false for clock sync packet', () {
      final bytes = Uint8List(12);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0xFFFF);
      view.setUint16(2, 0x434B); // "CK"
      expect(isRsPacket(bytes), isFalse);
    });
  });
}
