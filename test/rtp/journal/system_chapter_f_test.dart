import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/journal/system_chapter_f.dart';
import 'package:test/test.dart';

void main() {
  group('SystemChapterF', () {
    test('encode produces 1 byte without C or P', () {
      const chapter = SystemChapterF(point: 0);
      expect(chapter.encode().length, equals(1));
    });

    test('encode produces 5 bytes with C only', () {
      const chapter = SystemChapterF(c: true, point: 0, complete: 0);
      expect(chapter.encode().length, equals(5));
    });

    test('encode produces 5 bytes with P only', () {
      const chapter = SystemChapterF(p: true, point: 0, partial: 0);
      expect(chapter.encode().length, equals(5));
    });

    test('encode produces 9 bytes with C and P', () {
      const chapter = SystemChapterF(
        c: true,
        p: true,
        point: 0,
        complete: 0,
        partial: 0,
      );
      expect(chapter.encode().length, equals(9));
    });

    test('roundtrip header only', () {
      const original = SystemChapterF(
        s: true,
        q: true,
        d: true,
        point: 7,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('roundtrip with COMPLETE (quarter-frame, Q=1)', () {
      const original = SystemChapterF(
        c: true,
        q: true,
        point: 5,
        complete: 0x12345678,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(5));
    });

    test('roundtrip with COMPLETE (full frame, Q=0)', () {
      // HR=0x60 (30fps, 0 hours), MN=15, SC=30, FR=0
      const original = SystemChapterF(
        c: true,
        q: false,
        point: 7,
        complete: 0x600F1E00,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(5));
    });

    test('roundtrip with PARTIAL only', () {
      const original = SystemChapterF(
        p: true,
        point: 3,
        partial: 0xAABBCCDD,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(5));
    });

    test('roundtrip with COMPLETE and PARTIAL', () {
      const original = SystemChapterF(
        c: true,
        p: true,
        q: true,
        point: 5,
        complete: 0x11223344,
        partial: 0x55667788,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(9));
    });

    test('S flag at bit 7', () {
      const chapter = SystemChapterF(s: true, point: 0);
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('C flag at bit 6', () {
      const chapter = SystemChapterF(c: true, point: 0, complete: 0);
      expect(chapter.encode()[0] & 0x40, equals(0x40));
    });

    test('P flag at bit 5', () {
      const chapter = SystemChapterF(p: true, point: 0, partial: 0);
      expect(chapter.encode()[0] & 0x20, equals(0x20));
    });

    test('Q flag at bit 4', () {
      const chapter = SystemChapterF(q: true, point: 0);
      expect(chapter.encode()[0] & 0x10, equals(0x10));
    });

    test('D flag at bit 3', () {
      const chapter = SystemChapterF(d: true, point: 0);
      expect(chapter.encode()[0] & 0x08, equals(0x08));
    });

    test('POINT at bits 2-0', () {
      for (int i = 0; i <= 7; i++) {
        final chapter = SystemChapterF(point: i);
        expect(chapter.encode()[0] & 0x07, equals(i));
      }
    });

    test('COMPLETE field is 4 bytes big-endian (bytes 1-4)', () {
      const chapter = SystemChapterF(
        c: true,
        point: 0,
        complete: 0xDEADBEEF,
      );
      final bytes = chapter.encode();
      expect(bytes[1], equals(0xDE));
      expect(bytes[2], equals(0xAD));
      expect(bytes[3], equals(0xBE));
      expect(bytes[4], equals(0xEF));
    });

    test('PARTIAL follows COMPLETE when both present', () {
      const chapter = SystemChapterF(
        c: true,
        p: true,
        point: 0,
        complete: 0x11111111,
        partial: 0x22222222,
      );
      final bytes = chapter.encode();
      // COMPLETE at bytes 1-4
      expect(bytes[1], equals(0x11));
      // PARTIAL at bytes 5-8
      expect(bytes[5], equals(0x22));
    });

    test('decode returns null for empty data', () {
      expect(SystemChapterF.decode(Uint8List(0)), isNull);
    });

    test('decode returns null when C set but only 1 byte', () {
      expect(SystemChapterF.decode(Uint8List.fromList([0x40])), isNull);
    });

    test('decode returns null when P set but only 1 byte', () {
      expect(SystemChapterF.decode(Uint8List.fromList([0x20])), isNull);
    });

    test('decode returns null when C+P set but only 5 bytes', () {
      expect(
        SystemChapterF.decode(
          Uint8List.fromList([0x60, 0, 0, 0, 0]),
        ),
        isNull,
      );
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xFF, // padding
        0x03, // S=0, C=0, P=0, Q=0, D=0, POINT=3
      ]);
      final (decoded, consumed) = SystemChapterF.decode(bytes, 2)!;
      expect(decoded.point, equals(3));
      expect(consumed, equals(1));
    });

    test('known binary vector: quarter-frame nibbles', () {
      // C=1, Q=1, POINT=7, COMPLETE = MT0-MT7 packed
      // MT0=0x1, MT1=0xE, MT2=0x0, MT3=0xF, MT4=0x0, MT5=0x0, MT6=0x6, MT7=0x0
      // = 0x1E0F0060
      final bytes = Uint8List.fromList([
        0x57, // S=0, C=1, P=0, Q=1, D=0, POINT=7
        0x1E, 0x0F, 0x00, 0x60,
      ]);
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded.c, isTrue);
      expect(decoded.q, isTrue);
      expect(decoded.complete, equals(0x1E0F0060));
      expect(consumed, equals(5));
    });

    test('known binary vector: full frame HR/MN/SC/FR', () {
      // C=1, Q=0, COMPLETE = HR=0x61 (30fps, 1hr), MN=30, SC=0, FR=15
      final bytes = Uint8List.fromList([
        0x47, // S=0, C=1, P=0, Q=0, D=0, POINT=7
        0x61, 0x1E, 0x00, 0x0F,
      ]);
      final (decoded, consumed) = SystemChapterF.decode(bytes)!;
      expect(decoded.c, isTrue);
      expect(decoded.q, isFalse);
      expect(decoded.complete, equals(0x611E000F));
      expect(consumed, equals(5));
      // Extract HR/MN/SC/FR
      final hr = (decoded.complete! >> 24) & 0xFF;
      final mn = (decoded.complete! >> 16) & 0xFF;
      final sc = (decoded.complete! >> 8) & 0xFF;
      final fr = decoded.complete! & 0xFF;
      expect(hr, equals(0x61));
      expect(mn, equals(30));
      expect(sc, equals(0));
      expect(fr, equals(15));
    });

    test('equality', () {
      const a = SystemChapterF(point: 3);
      const b = SystemChapterF(point: 3);
      const c2 = SystemChapterF(point: 4);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c2)));
    });

    test('equality includes partial field', () {
      const a = SystemChapterF(p: true, point: 0, partial: 0x100);
      const b = SystemChapterF(p: true, point: 0, partial: 0x200);
      expect(a, isNot(equals(b)));
    });
  });
}
