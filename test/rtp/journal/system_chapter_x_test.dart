import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/system_chapter_x.dart';
import 'package:test/test.dart';

void main() {
  group('SystemChapterX', () {
    test('encode produces 1 byte minimum', () {
      const chapter = SystemChapterX(sta: 0);
      expect(chapter.encode().length, equals(1));
    });

    test('encode includes payload data', () {
      final chapter = SystemChapterX(
        sta: 0,
        data: Uint8List.fromList([0x01, 0x02, 0x03]),
      );
      expect(chapter.encode().length, equals(4));
    });

    test('roundtrip header only', () {
      const original = SystemChapterX(
        s: true,
        t: true,
        c: true,
        f: true,
        d: true,
        l: true,
        sta: 3,
      );
      final bytes = original.encode();
      final result = SystemChapterX.decode(bytes, length: bytes.length);
      expect(result, isNotNull);
      final (decoded, consumed) = result!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('roundtrip with data', () {
      final original = SystemChapterX(
        s: true,
        sta: 2,
        data: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      );
      final bytes = original.encode();
      final result = SystemChapterX.decode(bytes, length: bytes.length);
      expect(result, isNotNull);
      final (decoded, consumed) = result!;
      expect(decoded, equals(original));
      expect(consumed, equals(4));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = SystemChapterX(s: true, sta: 0);
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('T flag at bit 6 of byte 0', () {
      const chapter = SystemChapterX(t: true, sta: 0);
      expect(chapter.encode()[0] & 0x40, equals(0x40));
    });

    test('C flag at bit 5 of byte 0', () {
      const chapter = SystemChapterX(c: true, sta: 0);
      expect(chapter.encode()[0] & 0x20, equals(0x20));
    });

    test('F flag at bit 4 of byte 0', () {
      const chapter = SystemChapterX(f: true, sta: 0);
      expect(chapter.encode()[0] & 0x10, equals(0x10));
    });

    test('D flag at bit 3 of byte 0', () {
      const chapter = SystemChapterX(d: true, sta: 0);
      expect(chapter.encode()[0] & 0x08, equals(0x08));
    });

    test('L flag at bit 2 of byte 0', () {
      const chapter = SystemChapterX(l: true, sta: 0);
      expect(chapter.encode()[0] & 0x04, equals(0x04));
    });

    test('STA at bits 1-0 of byte 0', () {
      for (int i = 0; i <= 3; i++) {
        final chapter = SystemChapterX(sta: i);
        expect(chapter.encode()[0] & 0x03, equals(i));
      }
    });

    test('decode returns null when length is 0', () {
      expect(SystemChapterX.decode(Uint8List(0), length: 0), isNull);
    });

    test('decode returns null when buffer too short for length', () {
      expect(SystemChapterX.decode(Uint8List(2), length: 5), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xFF, // padding
        0xFC, // S=1, T=1, C=1, F=1, D=1, L=1, STA=0
        0x42, // data byte
      ]);
      final result = SystemChapterX.decode(bytes, offset: 2, length: 2);
      expect(result, isNotNull);
      final (decoded, consumed) = result!;
      expect(decoded.s, isTrue);
      expect(decoded.t, isTrue);
      expect(decoded.c, isTrue);
      expect(decoded.f, isTrue);
      expect(decoded.d, isTrue);
      expect(decoded.l, isTrue);
      expect(decoded.sta, equals(0));
      expect(decoded.data!.length, equals(1));
      expect(decoded.data![0], equals(0x42));
      expect(consumed, equals(2));
    });

    test('known binary vector: header only', () {
      final bytes = Uint8List.fromList([0x03]); // STA=3
      final (decoded, consumed) = SystemChapterX.decode(bytes, length: 1)!;
      expect(decoded.s, isFalse);
      expect(decoded.sta, equals(3));
      expect(decoded.data, isNull);
      expect(consumed, equals(1));
    });

    test('known binary vector: with SysEx data', () {
      // S=0, T=1, C=0, F=0, D=1, L=0, STA=1
      // Followed by 3 data bytes
      final bytes = Uint8List.fromList([
        0x49, // 0100_1001 → T=1, D=1, STA=1
        0xF0, 0x7E, 0xF7, // example sysex data
      ]);
      final (decoded, consumed) = SystemChapterX.decode(bytes, length: 4)!;
      expect(decoded.t, isTrue);
      expect(decoded.d, isTrue);
      expect(decoded.sta, equals(1));
      expect(decoded.data!.length, equals(3));
      expect(consumed, equals(4));
    });

    test('equality', () {
      const a = SystemChapterX(sta: 1);
      const b = SystemChapterX(sta: 1);
      const c = SystemChapterX(sta: 2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('equality includes data', () {
      final a = SystemChapterX(
        sta: 0,
        data: Uint8List.fromList([1, 2]),
      );
      final b = SystemChapterX(
        sta: 0,
        data: Uint8List.fromList([1, 3]),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
