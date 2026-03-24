import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/journal/channel_chapter_c.dart';
import 'package:test/test.dart';

void main() {
  group('ControllerLog', () {
    test('equality', () {
      const a = ControllerLog(number: 7, value: 100);
      const b = ControllerLog(number: 7, value: 100);
      const c = ControllerLog(number: 7, value: 101);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ChannelChapterC', () {
    test('encode minimum: 1 log produces 3 bytes', () {
      const chapter = ChannelChapterC(
        logs: [ControllerLog(number: 7, value: 100)],
      );
      expect(chapter.encode().length, equals(3));
    });

    test('roundtrip with 1 log', () {
      const original = ChannelChapterC(
        logs: [ControllerLog(number: 7, value: 100)],
      );
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterC.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip with multiple logs', () {
      const original = ChannelChapterC(
        s: true,
        logs: [
          ControllerLog(number: 1, value: 64),
          ControllerLog(s: true, number: 7, a: true, value: 127),
          ControllerLog(number: 64, value: 0),
        ],
      );
      final bytes = original.encode();
      expect(bytes.length, equals(7)); // 1 + 3*2
      final (decoded, consumed) = ChannelChapterC.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(7));
    });

    test('S flag at bit 7 of header byte', () {
      const chapter = ChannelChapterC(
        s: true,
        logs: [ControllerLog(number: 0, value: 0)],
      );
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('LEN field is log count minus 1', () {
      const chapter = ChannelChapterC(
        logs: [
          ControllerLog(number: 0, value: 0),
          ControllerLog(number: 1, value: 1),
          ControllerLog(number: 2, value: 2),
        ],
      );
      expect(chapter.encode()[0] & 0x7F, equals(2)); // 3-1=2
    });

    test('log S flag at bit 7 of first log byte', () {
      const chapter = ChannelChapterC(
        logs: [ControllerLog(s: true, number: 0, value: 0)],
      );
      expect(chapter.encode()[1] & 0x80, equals(0x80));
    });

    test('log A flag at bit 7 of second log byte', () {
      const chapter = ChannelChapterC(
        logs: [ControllerLog(number: 0, a: true, value: 0)],
      );
      expect(chapter.encode()[2] & 0x80, equals(0x80));
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelChapterC.decode(Uint8List(0)), isNull);
      expect(ChannelChapterC.decode(Uint8List(1)), isNull);
      expect(ChannelChapterC.decode(Uint8List(2)), isNull);
    });

    test('decode returns null when LEN implies more data than available', () {
      // LEN=1 means 2 logs = 5 bytes total, but only 3 provided
      final bytes = Uint8List.fromList([0x01, 0x00, 0x00]);
      expect(ChannelChapterC.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x00, 0x07, 0x64, // LEN=0, NUMBER=7, VALUE=100
      ]);
      final (decoded, consumed) = ChannelChapterC.decode(bytes, 1)!;
      expect(decoded.logs.length, equals(1));
      expect(decoded.logs[0].number, equals(7));
      expect(decoded.logs[0].value, equals(100));
      expect(consumed, equals(3));
    });

    test('known binary vector: volume + pan', () {
      // LEN=1 (2 logs), log1: CC#7=100, log2: CC#10=64
      final bytes = Uint8List.fromList([
        0x01, // S=0, LEN=1
        0x07, 0x64, // CC#7 (Volume) = 100
        0x0A, 0x40, // CC#10 (Pan) = 64
      ]);
      final (decoded, consumed) = ChannelChapterC.decode(bytes)!;
      expect(consumed, equals(5));
      expect(decoded.logs.length, equals(2));
      expect(decoded.logs[0].number, equals(7));
      expect(decoded.logs[0].value, equals(100));
      expect(decoded.logs[1].number, equals(10));
      expect(decoded.logs[1].value, equals(64));
    });

    test('max LEN value 127 encodes 128 logs', () {
      final logs = List.generate(
        128,
        (i) => ControllerLog(number: i & 0x7F, value: 0),
      );
      final chapter = ChannelChapterC(logs: logs);
      final bytes = chapter.encode();
      expect(bytes[0] & 0x7F, equals(127)); // LEN = 127
      expect(bytes.length, equals(1 + 128 * 2));
      final (decoded, _) = ChannelChapterC.decode(bytes)!;
      expect(decoded.logs.length, equals(128));
    });

    test('equality', () {
      const a = ChannelChapterC(
        logs: [ControllerLog(number: 1, value: 2)],
      );
      const b = ChannelChapterC(
        logs: [ControllerLog(number: 1, value: 2)],
      );
      const c = ChannelChapterC(
        logs: [ControllerLog(number: 1, value: 3)],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('minSize is 3', () {
      expect(ChannelChapterC.minSize, equals(3));
    });
  });
}
