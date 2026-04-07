import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/channel_chapter_e.dart';
import 'package:test/test.dart';

void main() {
  group('NoteExtraLog', () {
    test('equality', () {
      const a = NoteExtraLog(noteNum: 60, countVel: 100);
      const b = NoteExtraLog(noteNum: 60, countVel: 100);
      const c = NoteExtraLog(noteNum: 60, countVel: 101);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ChannelChapterE', () {
    test('encode minimum: 1 log produces 3 bytes', () {
      const chapter = ChannelChapterE(
        logs: [NoteExtraLog(noteNum: 60, countVel: 3)],
      );
      expect(chapter.encode().length, equals(3));
    });

    test('roundtrip with 1 log', () {
      const original = ChannelChapterE(
        logs: [NoteExtraLog(noteNum: 60, countVel: 3)],
      );
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterE.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip with multiple logs', () {
      const original = ChannelChapterE(
        s: true,
        logs: [
          NoteExtraLog(noteNum: 60, countVel: 3),
          NoteExtraLog(s: true, noteNum: 64, v: true, countVel: 100),
        ],
      );
      final bytes = original.encode();
      expect(bytes.length, equals(5)); // 1 + 2*2
      final (decoded, consumed) = ChannelChapterE.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(5));
    });

    test('S flag at bit 7 of header byte', () {
      const chapter = ChannelChapterE(
        s: true,
        logs: [NoteExtraLog(noteNum: 0, countVel: 0)],
      );
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('LEN field is log count minus 1', () {
      const chapter = ChannelChapterE(
        logs: [
          NoteExtraLog(noteNum: 60, countVel: 1),
          NoteExtraLog(noteNum: 64, countVel: 2),
        ],
      );
      expect(chapter.encode()[0] & 0x7F, equals(1));
    });

    test('log V flag at bit 7 of second log byte', () {
      const chapter = ChannelChapterE(
        logs: [NoteExtraLog(noteNum: 0, v: true, countVel: 0)],
      );
      expect(chapter.encode()[2] & 0x80, equals(0x80));
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelChapterE.decode(Uint8List(0)), isNull);
      expect(ChannelChapterE.decode(Uint8List(2)), isNull);
    });

    test('decode returns null when LEN implies more data than available', () {
      final bytes = Uint8List.fromList([0x01, 0x00, 0x00]);
      expect(ChannelChapterE.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x00, 0x3C, 0x03, // LEN=0, NOTENUM=60, COUNT=3
      ]);
      final (decoded, consumed) = ChannelChapterE.decode(bytes, 1)!;
      expect(decoded.logs.length, equals(1));
      expect(decoded.logs[0].noteNum, equals(60));
      expect(decoded.logs[0].countVel, equals(3));
      expect(consumed, equals(3));
    });

    test('known binary vector', () {
      // LEN=1 (2 logs), note 60 count=2, note 64 vel=80
      final bytes = Uint8List.fromList([
        0x01, // S=0, LEN=1
        0x3C, 0x02, // NOTENUM=60, V=0, COUNT=2
        0x40, 0xD0, // NOTENUM=64, V=1, VEL=80
      ]);
      final (decoded, consumed) = ChannelChapterE.decode(bytes)!;
      expect(consumed, equals(5));
      expect(decoded.logs[0].noteNum, equals(60));
      expect(decoded.logs[0].v, isFalse);
      expect(decoded.logs[0].countVel, equals(2));
      expect(decoded.logs[1].noteNum, equals(64));
      expect(decoded.logs[1].v, isTrue);
      expect(decoded.logs[1].countVel, equals(80));
    });

    test('equality', () {
      const a = ChannelChapterE(
        logs: [NoteExtraLog(noteNum: 60, countVel: 3)],
      );
      const b = ChannelChapterE(
        logs: [NoteExtraLog(noteNum: 60, countVel: 3)],
      );
      const c = ChannelChapterE(
        logs: [NoteExtraLog(noteNum: 61, countVel: 3)],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('minSize is 3', () {
      expect(ChannelChapterE.minSize, equals(3));
    });
  });
}
