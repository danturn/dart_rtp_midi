import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/rtp_header.dart';
import 'package:test/test.dart';

void main() {
  group('RtpHeader', () {
    test('encode produces 12 bytes', () {
      const header = RtpHeader(
        sequenceNumber: 1,
        timestamp: 1000,
        ssrc: 0x12345678,
      );
      expect(header.encode().length, equals(12));
    });

    test('encode/decode roundtrip with defaults', () {
      const original = RtpHeader(
        sequenceNumber: 42,
        timestamp: 123456,
        ssrc: 0xDEADBEEF,
      );
      final bytes = original.encode();
      final decoded = RtpHeader.decode(bytes);
      expect(decoded, equals(original));
    });

    test('encode/decode roundtrip with all fields set', () {
      const original = RtpHeader(
        version: 2,
        padding: true,
        extension: true,
        csrcCount: 3,
        marker: false,
        payloadType: 97,
        sequenceNumber: 0xFFFF,
        timestamp: 0xFFFFFFFF,
        ssrc: 0xAAAABBBB,
      );
      final bytes = original.encode();
      final decoded = RtpHeader.decode(bytes);
      expect(decoded, equals(original));
    });

    test('version field at bits 6-7 of byte 0', () {
      const header = RtpHeader(
        sequenceNumber: 0,
        timestamp: 0,
        ssrc: 0,
      );
      final bytes = header.encode();
      // Version 2 → bits 7-6 = 10 → byte 0 high nibble starts with 0x80
      expect(bytes[0] & 0xC0, equals(0x80));
    });

    test('marker bit at bit 7 of byte 1', () {
      const withMarker = RtpHeader(
        marker: true,
        sequenceNumber: 0,
        timestamp: 0,
        ssrc: 0,
      );
      final withMarkerBytes = withMarker.encode();
      expect(withMarkerBytes[1] & 0x80, equals(0x80));

      const withoutMarker = RtpHeader(
        marker: false,
        sequenceNumber: 0,
        timestamp: 0,
        ssrc: 0,
      );
      final withoutMarkerBytes = withoutMarker.encode();
      expect(withoutMarkerBytes[1] & 0x80, equals(0));
    });

    test('payload type at bits 0-6 of byte 1', () {
      const header = RtpHeader(
        payloadType: 97,
        sequenceNumber: 0,
        timestamp: 0,
        ssrc: 0,
      );
      final bytes = header.encode();
      expect(bytes[1] & 0x7F, equals(97));
    });

    test('sequence number wrapping', () {
      const header = RtpHeader(
        sequenceNumber: 0xFFFF,
        timestamp: 0,
        ssrc: 0,
      );
      final decoded = RtpHeader.decode(header.encode());
      expect(decoded!.sequenceNumber, equals(0xFFFF));
    });

    test('decode returns null for too-short data', () {
      expect(RtpHeader.decode(Uint8List(11)), isNull);
      expect(RtpHeader.decode(Uint8List(0)), isNull);
    });

    test('decode returns null for wrong version', () {
      final bytes = Uint8List(12);
      // Set version to 1 (bits 7-6 = 01 → 0x40)
      bytes[0] = 0x40;
      expect(RtpHeader.decode(bytes), isNull);
    });

    test('decode returns null for version 0', () {
      final bytes = Uint8List(12);
      bytes[0] = 0x00; // version 0
      expect(RtpHeader.decode(bytes), isNull);
    });

    test('known binary vector', () {
      // Hand-crafted RTP header:
      // V=2, P=0, X=0, CC=0, M=1, PT=97
      // Seq=1, TS=1000, SSRC=0x12345678
      final bytes = Uint8List.fromList([
        0x80, // V=2, P=0, X=0, CC=0
        0xE1, // M=1, PT=97 (0x61)
        0x00, 0x01, // Seq=1
        0x00, 0x00, 0x03, 0xE8, // TS=1000
        0x12, 0x34, 0x56, 0x78, // SSRC
      ]);
      final decoded = RtpHeader.decode(bytes)!;
      expect(decoded.version, equals(2));
      expect(decoded.padding, isFalse);
      expect(decoded.extension, isFalse);
      expect(decoded.csrcCount, equals(0));
      expect(decoded.marker, isTrue);
      expect(decoded.payloadType, equals(97));
      expect(decoded.sequenceNumber, equals(1));
      expect(decoded.timestamp, equals(1000));
      expect(decoded.ssrc, equals(0x12345678));
    });

    test('equality', () {
      const a = RtpHeader(sequenceNumber: 1, timestamp: 100, ssrc: 1);
      const b = RtpHeader(sequenceNumber: 1, timestamp: 100, ssrc: 1);
      const c = RtpHeader(sequenceNumber: 2, timestamp: 100, ssrc: 1);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('padding flag', () {
      const header = RtpHeader(
        padding: true,
        sequenceNumber: 0,
        timestamp: 0,
        ssrc: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x20, equals(0x20));
      final decoded = RtpHeader.decode(bytes)!;
      expect(decoded.padding, isTrue);
    });

    test('extension flag', () {
      const header = RtpHeader(
        extension: true,
        sequenceNumber: 0,
        timestamp: 0,
        ssrc: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x10, equals(0x10));
      final decoded = RtpHeader.decode(bytes)!;
      expect(decoded.extension, isTrue);
    });
  });
}
