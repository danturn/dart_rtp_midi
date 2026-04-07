import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/channel_chapter_w.dart';
import 'package:test/test.dart';

void main() {
  group('ChannelChapterW', () {
    test('encode produces 2 bytes', () {
      const chapter = ChannelChapterW();
      expect(chapter.encode().length, equals(2));
    });

    test('roundtrip with defaults', () {
      const original = ChannelChapterW();
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterW.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(2));
    });

    test('roundtrip with all fields set', () {
      const original =
          ChannelChapterW(s: true, first: 127, r: true, second: 64);
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterW.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(2));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = ChannelChapterW(s: true);
      expect(chapter.encode()[0] & 0x80, equals(0x80));

      const noFlag = ChannelChapterW();
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('FIRST at bits 6-0 of byte 0', () {
      const chapter = ChannelChapterW(first: 100);
      expect(chapter.encode()[0] & 0x7F, equals(100));
    });

    test('R flag at bit 7 of byte 1', () {
      const chapter = ChannelChapterW(r: true);
      expect(chapter.encode()[1] & 0x80, equals(0x80));

      const noFlag = ChannelChapterW();
      expect(noFlag.encode()[1] & 0x80, equals(0));
    });

    test('SECOND at bits 6-0 of byte 1', () {
      const chapter = ChannelChapterW(second: 64);
      expect(chapter.encode()[1] & 0x7F, equals(64));
    });

    test('decode returns null for empty data', () {
      expect(ChannelChapterW.decode(Uint8List(0)), isNull);
    });

    test('decode returns null for 1 byte', () {
      expect(ChannelChapterW.decode(Uint8List(1)), isNull);
    });

    test('decode with offset', () {
      final bytes =
          Uint8List.fromList([0xFF, 0x40, 0x20]); // padding, then data
      final (decoded, consumed) = ChannelChapterW.decode(bytes, 1)!;
      expect(decoded.s, isFalse);
      expect(decoded.first, equals(64));
      expect(decoded.r, isFalse);
      expect(decoded.second, equals(32));
      expect(consumed, equals(2));
    });

    test('decode returns null when offset leaves insufficient bytes', () {
      expect(ChannelChapterW.decode(Uint8List(2), 1), isNull);
    });

    test('known binary vector: pitch bend center', () {
      // FIRST=0, SECOND=64 (center position: 0x2000)
      final bytes = Uint8List.fromList([0x00, 0x40]);
      final (decoded, consumed) = ChannelChapterW.decode(bytes)!;
      expect(decoded.s, isFalse);
      expect(decoded.first, equals(0));
      expect(decoded.second, equals(64));
      expect(consumed, equals(2));
    });

    test('known binary vector: max pitch bend with S', () {
      // S=1, FIRST=127, R=0, SECOND=127
      final bytes = Uint8List.fromList([0xFF, 0x7F]);
      final (decoded, _) = ChannelChapterW.decode(bytes)!;
      expect(decoded.s, isTrue);
      expect(decoded.first, equals(127));
      expect(decoded.r, isFalse);
      expect(decoded.second, equals(127));
    });

    test('equality', () {
      const a = ChannelChapterW(first: 10, second: 20);
      const b = ChannelChapterW(first: 10, second: 20);
      const c = ChannelChapterW(first: 10, second: 21);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('size is 2', () {
      expect(ChannelChapterW.size, equals(2));
    });
  });
}
