import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/system_chapter_v.dart';
import 'package:test/test.dart';

void main() {
  group('SystemChapterV', () {
    test('encode produces 1 byte', () {
      const chapter = SystemChapterV();
      expect(chapter.encode().length, equals(1));
    });

    test('roundtrip with defaults', () {
      const original = SystemChapterV();
      final bytes = original.encode();
      final result = SystemChapterV.decode(bytes);
      expect(result, isNotNull);
      final (decoded, consumed) = result!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('roundtrip with all fields set', () {
      const original = SystemChapterV(s: true, count: 127);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterV.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = SystemChapterV(s: true);
      expect(chapter.encode()[0] & 0x80, equals(0x80));

      const noFlag = SystemChapterV();
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('COUNT at bits 6-0 of byte 0', () {
      const chapter = SystemChapterV(count: 42);
      expect(chapter.encode()[0] & 0x7F, equals(42));
    });

    test('COUNT max value 127', () {
      const chapter = SystemChapterV(count: 127);
      final (decoded, _) = SystemChapterV.decode(chapter.encode())!;
      expect(decoded.count, equals(127));
    });

    test('decode returns null for empty data', () {
      expect(SystemChapterV.decode(Uint8List(0)), isNull);
    });

    test('decode with offset', () {
      final bytes =
          Uint8List.fromList([0xFF, 0x8A]); // padding, then S=1 COUNT=10
      final (decoded, consumed) = SystemChapterV.decode(bytes, 1)!;
      expect(decoded.s, isTrue);
      expect(decoded.count, equals(10));
      expect(consumed, equals(1));
    });

    test('decode returns null when offset leaves insufficient bytes', () {
      expect(SystemChapterV.decode(Uint8List(1), 1), isNull);
    });

    test('known binary vector', () {
      // S=0, COUNT=96
      final bytes = Uint8List.fromList([0x60]); // 0110_0000
      final (decoded, consumed) = SystemChapterV.decode(bytes)!;
      expect(decoded.s, isFalse);
      expect(decoded.count, equals(96));
      expect(consumed, equals(1));
    });

    test('equality', () {
      const a = SystemChapterV(count: 5);
      const b = SystemChapterV(count: 5);
      const c = SystemChapterV(count: 6);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('size is 1', () {
      expect(SystemChapterV.size, equals(1));
    });
  });
}
