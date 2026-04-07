import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/channel_chapter_m.dart';
import 'package:test/test.dart';

void main() {
  group('ParamLog', () {
    test('equality', () {
      const a = ParamLog(pnumLsb: 10, pnumMsb: 20, q: false);
      const b = ParamLog(pnumLsb: 10, pnumMsb: 20, q: false);
      const c = ParamLog(pnumLsb: 11, pnumMsb: 20, q: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('size: short format, no trailing fields', () {
      const log = ParamLog(pnumLsb: 10);
      expect(log.isShort, isTrue);
      expect(log.size, equals(2)); // S|PNUM-LSB + FLAGS
    });

    test('size: long format, no trailing fields', () {
      const log = ParamLog(pnumLsb: 10, pnumMsb: 20, q: false);
      expect(log.isShort, isFalse);
      expect(log.size, equals(3)); // S|PNUM-LSB + Q|PNUM-MSB + FLAGS
    });

    test('size: long format with J+L fields', () {
      const log = ParamLog(
        pnumLsb: 10,
        pnumMsb: 20,
        q: false,
        j: true,
        jValue: 0x42,
        l: true,
        lValue: 0x1234,
      );
      expect(log.size, equals(6)); // 3 (long header+flags) + 1 J + 2 L
    });
  });

  group('ChannelChapterM', () {
    test('encode header only (no logs, no pending)', () {
      const chapter = ChannelChapterM();
      final bytes = chapter.encode();
      expect(bytes.length, equals(2));
    });

    test('roundtrip: header only', () {
      const original = ChannelChapterM();
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(2));
    });

    test('roundtrip: with PENDING', () {
      const original = ChannelChapterM(
        p: true,
        pendingQ: true,
        pending: 42,
      );
      final bytes = original.encode();
      expect(bytes.length, equals(3)); // 2 header + 1 pending
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip: long format log (Z=0)', () {
      const original = ChannelChapterM(
        logs: [
          ParamLog(pnumLsb: 10, pnumMsb: 20, q: true),
        ],
      );
      final bytes = original.encode();
      // 2 header + 3 log (long: PNUM-LSB + PNUM-MSB + FLAGS) = 5
      expect(bytes.length, equals(5));
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(5));
    });

    test('roundtrip: short format log (Z=1, U=1)', () {
      const original = ChannelChapterM(
        z: true,
        u: true,
        logs: [
          ParamLog(pnumLsb: 10),
        ],
      );
      final bytes = original.encode();
      // 2 header + 2 log (short: PNUM-LSB + FLAGS) = 4
      expect(bytes.length, equals(4));
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(4));
    });

    test('roundtrip: short format log (Z=1, W=1)', () {
      const original = ChannelChapterM(
        z: true,
        w: true,
        logs: [
          ParamLog(pnumLsb: 5),
        ],
      );
      final bytes = original.encode();
      expect(bytes.length, equals(4));
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(4));
    });

    test('short format requires Z AND (U OR W)', () {
      // Z=1 but U=0 and W=0 → long format
      const chapter = ChannelChapterM(z: true);
      expect(chapter.shortFormat, isFalse);

      // Z=1, U=1 → short
      const short1 = ChannelChapterM(z: true, u: true);
      expect(short1.shortFormat, isTrue);

      // Z=1, W=1 → short
      const short2 = ChannelChapterM(z: true, w: true);
      expect(short2.shortFormat, isTrue);

      // Z=0, U=1 → long
      const long1 = ChannelChapterM(u: true);
      expect(long1.shortFormat, isFalse);
    });

    test('roundtrip: log with all trailing fields', () {
      const original = ChannelChapterM(
        logs: [
          ParamLog(
            pnumLsb: 10,
            pnumMsb: 20,
            q: false,
            j: true,
            jValue: 0x42,
            k: true,
            kValue: 0x55,
            l: true,
            lValue: 0x1234,
            m: true,
            mValue: 0x5678,
            n: true,
            nValue: 0xAB,
          ),
        ],
      );
      final bytes = original.encode();
      // 2 header + (3+1+1+2+2+1) = 2 + 10 = 12
      expect(bytes.length, equals(12));
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(12));
    });

    test('roundtrip: multiple logs', () {
      const original = ChannelChapterM(
        s: true,
        logs: [
          ParamLog(pnumLsb: 10, pnumMsb: 0, q: false, j: true, jValue: 0x10),
          ParamLog(pnumLsb: 20, pnumMsb: 0, q: true, k: true, kValue: 0x20),
        ],
      );
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(bytes.length));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = ChannelChapterM(s: true);
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('P flag at bit 6 of byte 0', () {
      const chapter = ChannelChapterM(p: true, pending: 0);
      expect(chapter.encode()[0] & 0x40, equals(0x40));
    });

    test('E flag at bit 5 of byte 0', () {
      const chapter = ChannelChapterM(e: true);
      expect(chapter.encode()[0] & 0x20, equals(0x20));
    });

    test('U flag at bit 4 of byte 0', () {
      const chapter = ChannelChapterM(u: true);
      expect(chapter.encode()[0] & 0x10, equals(0x10));
    });

    test('W flag at bit 3 of byte 0', () {
      const chapter = ChannelChapterM(w: true);
      expect(chapter.encode()[0] & 0x08, equals(0x08));
    });

    test('Z flag at bit 2 of byte 0', () {
      const chapter = ChannelChapterM(z: true);
      expect(chapter.encode()[0] & 0x04, equals(0x04));
    });

    test('LENGTH spans bits 1-0 of byte 0 and all of byte 1', () {
      const chapter = ChannelChapterM();
      final bytes = chapter.encode();
      final length = ((bytes[0] & 0x03) << 8) | bytes[1];
      expect(length, equals(2));
    });

    test('PENDING byte: Q at bit 7, value at bits 6-0', () {
      const chapter = ChannelChapterM(
        p: true,
        pendingQ: true,
        pending: 100,
      );
      final bytes = chapter.encode();
      expect(bytes[2] & 0x80, equals(0x80)); // Q
      expect(bytes[2] & 0x7F, equals(100)); // PENDING
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelChapterM.decode(Uint8List(0)), isNull);
      expect(ChannelChapterM.decode(Uint8List(1)), isNull);
    });

    test('decode returns null when LENGTH exceeds buffer', () {
      final bytes = Uint8List.fromList([0x00, 0x0A]); // LENGTH=10
      expect(ChannelChapterM.decode(bytes), isNull);
    });

    test('decode returns null for invalid LENGTH < 2', () {
      final bytes = Uint8List.fromList([0x00, 0x01]); // LENGTH=1
      expect(ChannelChapterM.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x00, 0x02, // empty chapter, LENGTH=2
      ]);
      final (decoded, consumed) = ChannelChapterM.decode(bytes, 1)!;
      expect(decoded.logs, isEmpty);
      expect(consumed, equals(2));
    });

    test('known binary vector: long format with J field', () {
      // S=0, P=0, E=0, U=0, W=0, Z=0, LENGTH=6
      // Log: S=0, PNUM-LSB=10, Q=0, PNUM-MSB=20
      // Flags: J=1, rest=0 → 0x80
      // J value: 0x42
      final bytes = Uint8List.fromList([
        0x00, 0x06, // header: LENGTH=6
        0x0A, // log: S=0, PNUM-LSB=10
        0x14, // Q=0, PNUM-MSB=20
        0x80, // flags: J=1
        0x42, // J value
      ]);
      final (decoded, consumed) = ChannelChapterM.decode(bytes)!;
      expect(consumed, equals(6));
      expect(decoded.logs.length, equals(1));
      expect(decoded.logs[0].pnumLsb, equals(10));
      expect(decoded.logs[0].pnumMsb, equals(20));
      expect(decoded.logs[0].j, isTrue);
      expect(decoded.logs[0].jValue, equals(0x42));
    });

    test('equality', () {
      const a = ChannelChapterM(s: true, e: true);
      const b = ChannelChapterM(s: true, e: true);
      const c = ChannelChapterM(s: true, e: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('headerSize is 2', () {
      expect(ChannelChapterM.headerSize, equals(2));
    });
  });
}
