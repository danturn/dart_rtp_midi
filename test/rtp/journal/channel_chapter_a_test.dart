import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/journal/channel_chapter_a.dart';
import 'package:test/test.dart';

void main() {
  group('PolyAftertouchLog', () {
    test('equality', () {
      const a = PolyAftertouchLog(noteNum: 60, pressure: 80);
      const b = PolyAftertouchLog(noteNum: 60, pressure: 80);
      const c = PolyAftertouchLog(noteNum: 60, pressure: 81);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ChannelChapterA', () {
    test('encode minimum: 1 log produces 3 bytes', () {
      const chapter = ChannelChapterA(
        logs: [PolyAftertouchLog(noteNum: 60, pressure: 80)],
      );
      expect(chapter.encode().length, equals(3));
    });

    test('roundtrip with 1 log', () {
      const original = ChannelChapterA(
        logs: [PolyAftertouchLog(noteNum: 60, pressure: 80)],
      );
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterA.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip with multiple logs', () {
      const original = ChannelChapterA(
        s: true,
        logs: [
          PolyAftertouchLog(noteNum: 60, pressure: 80),
          PolyAftertouchLog(s: true, noteNum: 64, x: true, pressure: 127),
          PolyAftertouchLog(noteNum: 72, pressure: 0),
        ],
      );
      final bytes = original.encode();
      expect(bytes.length, equals(7)); // 1 + 3*2
      final (decoded, consumed) = ChannelChapterA.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(7));
    });

    test('S flag at bit 7 of header byte', () {
      const chapter = ChannelChapterA(
        s: true,
        logs: [PolyAftertouchLog(noteNum: 0, pressure: 0)],
      );
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('LEN field is log count minus 1', () {
      const chapter = ChannelChapterA(
        logs: [
          PolyAftertouchLog(noteNum: 60, pressure: 1),
          PolyAftertouchLog(noteNum: 64, pressure: 2),
        ],
      );
      expect(chapter.encode()[0] & 0x7F, equals(1));
    });

    test('log X flag at bit 7 of second log byte', () {
      const chapter = ChannelChapterA(
        logs: [PolyAftertouchLog(noteNum: 0, x: true, pressure: 0)],
      );
      expect(chapter.encode()[2] & 0x80, equals(0x80));
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelChapterA.decode(Uint8List(0)), isNull);
      expect(ChannelChapterA.decode(Uint8List(2)), isNull);
    });

    test('decode returns null when LEN implies more data than available', () {
      final bytes = Uint8List.fromList([0x01, 0x00, 0x00]);
      expect(ChannelChapterA.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x00, 0x3C, 0x50, // LEN=0, NOTENUM=60, PRESSURE=80
      ]);
      final (decoded, consumed) = ChannelChapterA.decode(bytes, 1)!;
      expect(decoded.logs.length, equals(1));
      expect(decoded.logs[0].noteNum, equals(60));
      expect(decoded.logs[0].pressure, equals(80));
      expect(consumed, equals(3));
    });

    test('known binary vector', () {
      // LEN=1 (2 logs), note 60 pressure=100, note 64 X=1 pressure=50
      final bytes = Uint8List.fromList([
        0x01, // S=0, LEN=1
        0x3C, 0x64, // NOTENUM=60, X=0, PRESSURE=100
        0x40, 0xB2, // NOTENUM=64, X=1, PRESSURE=50
      ]);
      final (decoded, consumed) = ChannelChapterA.decode(bytes)!;
      expect(consumed, equals(5));
      expect(decoded.logs[0].noteNum, equals(60));
      expect(decoded.logs[0].x, isFalse);
      expect(decoded.logs[0].pressure, equals(100));
      expect(decoded.logs[1].noteNum, equals(64));
      expect(decoded.logs[1].x, isTrue);
      expect(decoded.logs[1].pressure, equals(50));
    });

    test('equality', () {
      const a = ChannelChapterA(
        logs: [PolyAftertouchLog(noteNum: 60, pressure: 80)],
      );
      const b = ChannelChapterA(
        logs: [PolyAftertouchLog(noteNum: 60, pressure: 80)],
      );
      const c = ChannelChapterA(
        logs: [PolyAftertouchLog(noteNum: 61, pressure: 80)],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('minSize is 3', () {
      expect(ChannelChapterA.minSize, equals(3));
    });
  });
}
