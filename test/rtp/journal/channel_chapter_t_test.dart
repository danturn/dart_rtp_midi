import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/journal/channel_chapter_t.dart';
import 'package:test/test.dart';

void main() {
  group('ChannelChapterT', () {
    test('encode produces 1 byte', () {
      const chapter = ChannelChapterT();
      expect(chapter.encode().length, equals(1));
    });

    test('roundtrip with defaults', () {
      const original = ChannelChapterT();
      final bytes = original.encode();
      final result = ChannelChapterT.decode(bytes);
      expect(result, isNotNull);
      final (decoded, consumed) = result!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('roundtrip with all fields set', () {
      const original = ChannelChapterT(s: true, pressure: 127);
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterT.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = ChannelChapterT(s: true);
      expect(chapter.encode()[0] & 0x80, equals(0x80));

      const noFlag = ChannelChapterT();
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('PRESSURE at bits 6-0 of byte 0', () {
      const chapter = ChannelChapterT(pressure: 42);
      expect(chapter.encode()[0] & 0x7F, equals(42));
    });

    test('PRESSURE max value 127', () {
      const chapter = ChannelChapterT(pressure: 127);
      final (decoded, _) = ChannelChapterT.decode(chapter.encode())!;
      expect(decoded.pressure, equals(127));
    });

    test('decode returns null for empty data', () {
      expect(ChannelChapterT.decode(Uint8List(0)), isNull);
    });

    test('decode with offset', () {
      final bytes =
          Uint8List.fromList([0xFF, 0xCA]); // padding, S=1 PRESSURE=74
      final (decoded, consumed) = ChannelChapterT.decode(bytes, 1)!;
      expect(decoded.s, isTrue);
      expect(decoded.pressure, equals(74));
      expect(consumed, equals(1));
    });

    test('decode returns null when offset leaves insufficient bytes', () {
      expect(ChannelChapterT.decode(Uint8List(1), 1), isNull);
    });

    test('known binary vector', () {
      // S=0, PRESSURE=100
      final bytes = Uint8List.fromList([0x64]); // 0110_0100
      final (decoded, consumed) = ChannelChapterT.decode(bytes)!;
      expect(decoded.s, isFalse);
      expect(decoded.pressure, equals(100));
      expect(consumed, equals(1));
    });

    test('equality', () {
      const a = ChannelChapterT(pressure: 5);
      const b = ChannelChapterT(pressure: 5);
      const c = ChannelChapterT(pressure: 6);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('size is 1', () {
      expect(ChannelChapterT.size, equals(1));
    });
  });
}
