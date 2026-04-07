import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/system_chapter_q.dart';
import 'package:test/test.dart';

void main() {
  group('SystemChapterQ', () {
    test('encode produces 1 byte without C or T', () {
      const chapter = SystemChapterQ(top: 0);
      expect(chapter.encode().length, equals(1));
    });

    test('encode produces 3 bytes with C only', () {
      const chapter = SystemChapterQ(c: true, top: 0, clock: 0);
      expect(chapter.encode().length, equals(3));
    });

    test('encode produces 4 bytes with T only', () {
      const chapter = SystemChapterQ(t: true, top: 0, timetools: 0);
      expect(chapter.encode().length, equals(4));
    });

    test('encode produces 6 bytes with C and T', () {
      const chapter = SystemChapterQ(
        c: true,
        t: true,
        top: 0,
        clock: 0,
        timetools: 0,
      );
      expect(chapter.encode().length, equals(6));
    });

    test('roundtrip header only (C=0, T=0)', () {
      const original = SystemChapterQ(
        s: true,
        n: true,
        d: true,
        top: 7,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterQ.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('roundtrip with CLOCK (C=1)', () {
      const original = SystemChapterQ(
        n: true,
        c: true,
        top: 5,
        clock: 0xABCD,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterQ.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip with TIMETOOLS (T=1)', () {
      const original = SystemChapterQ(
        t: true,
        top: 3,
        timetools: 0x123456,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterQ.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(4));
    });

    test('roundtrip with CLOCK and TIMETOOLS (C=1, T=1)', () {
      const original = SystemChapterQ(
        s: true,
        n: true,
        d: true,
        c: true,
        t: true,
        top: 7,
        clock: 0xFFFF,
        timetools: 0xFFFFFF,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterQ.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(6));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = SystemChapterQ(s: true, top: 0);
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('N flag at bit 6 of byte 0', () {
      const chapter = SystemChapterQ(n: true, top: 0);
      expect(chapter.encode()[0] & 0x40, equals(0x40));
    });

    test('D flag at bit 5 of byte 0', () {
      const chapter = SystemChapterQ(d: true, top: 0);
      expect(chapter.encode()[0] & 0x20, equals(0x20));
    });

    test('C flag at bit 4 of byte 0', () {
      const chapter = SystemChapterQ(c: true, top: 0, clock: 0);
      expect(chapter.encode()[0] & 0x10, equals(0x10));
    });

    test('T flag at bit 3 of byte 0 (RFC 6295, not Wireshark 0x80 bug)', () {
      const chapter = SystemChapterQ(t: true, top: 0, timetools: 0);
      final bytes = chapter.encode();
      expect(bytes[0] & 0x08, equals(0x08));
      // Verify S is NOT set (proves T != S)
      expect(bytes[0] & 0x80, equals(0));
    });

    test('TOP at bits 2-0 of byte 0', () {
      for (int i = 0; i <= 7; i++) {
        final chapter = SystemChapterQ(top: i);
        expect(chapter.encode()[0] & 0x07, equals(i));
      }
    });

    test('CLOCK in bytes 1-2 when C=1', () {
      const chapter = SystemChapterQ(c: true, top: 0, clock: 0x1234);
      final bytes = chapter.encode();
      expect(bytes[1], equals(0x12));
      expect(bytes[2], equals(0x34));
    });

    test('TIMETOOLS in bytes 1-3 when T=1 and C=0', () {
      const chapter = SystemChapterQ(t: true, top: 0, timetools: 0xABCDEF);
      final bytes = chapter.encode();
      expect(bytes[1], equals(0xAB));
      expect(bytes[2], equals(0xCD));
      expect(bytes[3], equals(0xEF));
    });

    test('TIMETOOLS follows CLOCK when both C=1 and T=1', () {
      const chapter = SystemChapterQ(
        c: true,
        t: true,
        top: 0,
        clock: 0x1111,
        timetools: 0x222222,
      );
      final bytes = chapter.encode();
      // Bytes 1-2: CLOCK
      expect(bytes[1], equals(0x11));
      expect(bytes[2], equals(0x11));
      // Bytes 3-5: TIMETOOLS
      expect(bytes[3], equals(0x22));
      expect(bytes[4], equals(0x22));
      expect(bytes[5], equals(0x22));
    });

    test('song position = 65536*TOP + CLOCK', () {
      const chapter = SystemChapterQ(c: true, top: 3, clock: 1000);
      final (decoded, _) = SystemChapterQ.decode(chapter.encode())!;
      final songPosition = 65536 * decoded.top + decoded.clock!;
      expect(songPosition, equals(65536 * 3 + 1000));
    });

    test('decode returns null for empty data', () {
      expect(SystemChapterQ.decode(Uint8List(0)), isNull);
    });

    test('decode returns null when C set but only 1 byte', () {
      final bytes = Uint8List.fromList([0x10]); // C=1, needs 3 bytes
      expect(SystemChapterQ.decode(bytes), isNull);
    });

    test('decode returns null when T set but only 1 byte', () {
      final bytes = Uint8List.fromList([0x08]); // T=1, needs 4 bytes
      expect(SystemChapterQ.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x68, // S=0, N=1, D=1, C=0, T=1, TOP=0
        0x00, 0x01, 0x00, // TIMETOOLS=256
      ]);
      final (decoded, consumed) = SystemChapterQ.decode(bytes, 1)!;
      expect(decoded.n, isTrue);
      expect(decoded.d, isTrue);
      expect(decoded.t, isTrue);
      expect(decoded.c, isFalse);
      expect(decoded.timetools, equals(256));
      expect(consumed, equals(4));
    });

    test('known binary vector: stopped sequencer', () {
      // S=0, N=0, D=0, C=0, T=0, TOP=0 → 1 byte
      final bytes = Uint8List.fromList([0x00]);
      final (decoded, consumed) = SystemChapterQ.decode(bytes)!;
      expect(decoded.n, isFalse);
      expect(decoded.c, isFalse);
      expect(decoded.t, isFalse);
      expect(decoded.top, equals(0));
      expect(consumed, equals(1));
    });

    test('known binary vector: running with clock', () {
      // S=0, N=1, D=1, C=1, T=0, TOP=2, CLOCK=1000
      // byte0 = 0111_0 010 = 0x72
      final bytes = Uint8List.fromList([
        0x72, // N=1, D=1, C=1, TOP=2
        0x03, 0xE8, // CLOCK=1000
      ]);
      final (decoded, consumed) = SystemChapterQ.decode(bytes)!;
      expect(decoded.n, isTrue);
      expect(decoded.d, isTrue);
      expect(decoded.c, isTrue);
      expect(decoded.top, equals(2));
      expect(decoded.clock, equals(1000));
      expect(consumed, equals(3));
      // Song position = 65536*2 + 1000 = 132072
      expect(65536 * decoded.top + decoded.clock!, equals(132072));
    });

    test('equality', () {
      const a = SystemChapterQ(c: true, top: 1, clock: 100);
      const b = SystemChapterQ(c: true, top: 1, clock: 100);
      const c2 = SystemChapterQ(c: true, top: 1, clock: 101);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c2)));
    });

    test('TOP max value 7', () {
      const chapter = SystemChapterQ(top: 7);
      final (decoded, _) = SystemChapterQ.decode(chapter.encode())!;
      expect(decoded.top, equals(7));
    });

    test('CLOCK max value 0xFFFF', () {
      const chapter = SystemChapterQ(c: true, top: 0, clock: 0xFFFF);
      final (decoded, _) = SystemChapterQ.decode(chapter.encode())!;
      expect(decoded.clock, equals(0xFFFF));
    });

    test('TIMETOOLS max value 0xFFFFFF', () {
      const chapter = SystemChapterQ(t: true, top: 0, timetools: 0xFFFFFF);
      final (decoded, _) = SystemChapterQ.decode(chapter.encode())!;
      expect(decoded.timetools, equals(0xFFFFFF));
    });
  });
}
