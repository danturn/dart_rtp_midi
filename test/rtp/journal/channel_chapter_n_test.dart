import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/channel_chapter_n.dart';
import 'package:test/test.dart';

void main() {
  group('NoteLog', () {
    test('equality', () {
      const a = NoteLog(noteNum: 60, velocity: 100);
      const b = NoteLog(noteNum: 60, velocity: 100);
      const c = NoteLog(noteNum: 60, velocity: 101);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ChannelChapterN', () {
    group('offbitCount', () {
      test('LOW=15 HIGH=0 → 0', () {
        expect(ChannelChapterN.offbitCount(15, 0), equals(0));
      });

      test('LOW=15 HIGH=1 → 0', () {
        expect(ChannelChapterN.offbitCount(15, 1), equals(0));
      });

      test('LOW<=HIGH → HIGH-LOW+1', () {
        expect(ChannelChapterN.offbitCount(3, 7), equals(5));
        expect(ChannelChapterN.offbitCount(0, 0), equals(1));
        expect(ChannelChapterN.offbitCount(0, 15), equals(16));
      });

      test('LOW>HIGH → 0', () {
        expect(ChannelChapterN.offbitCount(7, 3), equals(0));
        expect(ChannelChapterN.offbitCount(14, 0), equals(0));
      });
    });

    test('encode header only (no logs, no offbits)', () {
      const chapter = ChannelChapterN(logs: []);
      final bytes = chapter.encode();
      // default LOW=15, HIGH=0 → offbit=0
      expect(bytes.length, equals(2));
    });

    test('roundtrip: header only', () {
      const original = ChannelChapterN(logs: []);
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterN.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(2));
    });

    test('roundtrip: 1 note log, no offbits', () {
      const original = ChannelChapterN(
        logs: [NoteLog(noteNum: 60, velocity: 100)],
      );
      final bytes = original.encode();
      expect(bytes.length, equals(4)); // 2 header + 1*2 logs
      final (decoded, consumed) = ChannelChapterN.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(4));
    });

    test('roundtrip: note logs + offbit field', () {
      final original = ChannelChapterN(
        b: true,
        logs: const [NoteLog(noteNum: 60, y: true, velocity: 100)],
        low: 3,
        high: 5,
        offBits: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
      );
      final bytes = original.encode();
      // 2 header + 1*2 logs + 3 offbits = 7
      expect(bytes.length, equals(7));
      final (decoded, consumed) = ChannelChapterN.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(7));
    });

    test('B flag at bit 7 of byte 0', () {
      const chapter = ChannelChapterN(b: true, logs: []);
      expect(chapter.encode()[0] & 0x80, equals(0x80));

      const noFlag = ChannelChapterN(logs: []);
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('LEN at bits 6-0 of byte 0', () {
      const chapter = ChannelChapterN(
        logs: [
          NoteLog(noteNum: 60, velocity: 100),
          NoteLog(noteNum: 64, velocity: 80),
        ],
      );
      expect(chapter.encode()[0] & 0x7F, equals(2));
    });

    test('LOW at bits 7-4, HIGH at bits 3-0 of byte 1', () {
      const chapter = ChannelChapterN(logs: [], low: 10, high: 5);
      final byte1 = chapter.encode()[1];
      expect((byte1 >> 4) & 0x0F, equals(10));
      expect(byte1 & 0x0F, equals(5));
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelChapterN.decode(Uint8List(0)), isNull);
      expect(ChannelChapterN.decode(Uint8List(1)), isNull);
    });

    test('decode returns null when logs exceed buffer', () {
      // LEN=1 means 1 log = 2 bytes, but only header provided
      final bytes = Uint8List.fromList([0x01, 0xF0]);
      expect(ChannelChapterN.decode(bytes), isNull);
    });

    test('decode returns null when offbits exceed buffer', () {
      // LOW=0, HIGH=2 → 3 offbit bytes, but not enough data
      final bytes = Uint8List.fromList([0x00, 0x02, 0xFF]);
      expect(ChannelChapterN.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x01, 0xF0, // B=0, LEN=1, LOW=15, HIGH=0
        0x3C, 0x64, // NOTENUM=60, Y=0, VELOCITY=100
      ]);
      final (decoded, consumed) = ChannelChapterN.decode(bytes, 1)!;
      expect(decoded.logs.length, equals(1));
      expect(decoded.logs[0].noteNum, equals(60));
      expect(decoded.logs[0].velocity, equals(100));
      expect(consumed, equals(4));
    });

    test('known binary vector: middle C note-on with offbits', () {
      // B=1, LEN=1 (1 log), LOW=3, HIGH=4 (2 offbit bytes)
      // Note log: NOTENUM=60, Y=1, VELOCITY=100
      final bytes = Uint8List.fromList([
        0x81, 0x34, // B=1, LEN=1, LOW=3, HIGH=4
        0x3C, 0xE4, // NOTENUM=60, Y=1, VEL=100
        0xFF, 0x00, // offbit bytes
      ]);
      final (decoded, consumed) = ChannelChapterN.decode(bytes)!;
      expect(consumed, equals(6));
      expect(decoded.b, isTrue);
      expect(decoded.logs.length, equals(1));
      expect(decoded.logs[0].noteNum, equals(60));
      expect(decoded.logs[0].y, isTrue);
      expect(decoded.logs[0].velocity, equals(100));
      expect(decoded.low, equals(3));
      expect(decoded.high, equals(4));
      expect(decoded.offBits, equals(Uint8List.fromList([0xFF, 0x00])));
    });

    test('multiple note logs', () {
      const original = ChannelChapterN(
        logs: [
          NoteLog(noteNum: 60, velocity: 100),
          NoteLog(s: true, noteNum: 64, y: true, velocity: 80),
          NoteLog(noteNum: 67, velocity: 90),
        ],
      );
      final bytes = original.encode();
      expect(bytes.length, equals(8)); // 2 + 3*2
      final (decoded, _) = ChannelChapterN.decode(bytes)!;
      expect(decoded, equals(original));
    });

    test('equality', () {
      const a = ChannelChapterN(
        logs: [NoteLog(noteNum: 60, velocity: 100)],
      );
      const b = ChannelChapterN(
        logs: [NoteLog(noteNum: 60, velocity: 100)],
      );
      const c = ChannelChapterN(
        logs: [NoteLog(noteNum: 61, velocity: 100)],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('headerSize is 2', () {
      expect(ChannelChapterN.headerSize, equals(2));
    });

    group('128-log special case (RFC 6295 A.6)', () {
      test('decode: LEN=127 + LOW=15 + HIGH=0 → 128 logs', () {
        // Build a buffer: header(2) + 128 logs(256) = 258 bytes
        final bytes = Uint8List(258);
        bytes[0] = 0x7F; // B=0, LEN=127
        bytes[1] = 0xF0; // LOW=15, HIGH=0
        // Fill 128 note logs with note numbers 0-127
        for (int i = 0; i < 128; i++) {
          bytes[2 + i * 2] = i; // S=0, NOTENUM=i
          bytes[2 + i * 2 + 1] = 64; // Y=0, VELOCITY=64
        }
        final (decoded, consumed) = ChannelChapterN.decode(bytes)!;
        expect(decoded.logs.length, equals(128));
        expect(consumed, equals(258));
        expect(decoded.logs[0].noteNum, equals(0));
        expect(decoded.logs[127].noteNum, equals(127));
      });

      test('encode 128 logs uses LEN=127 + LOW=15 + HIGH=0', () {
        final logs = List.generate(
          128,
          (i) => NoteLog(noteNum: i, velocity: 64),
        );
        final chapter = ChannelChapterN(logs: logs);
        final bytes = chapter.encode();
        expect(bytes[0] & 0x7F, equals(127)); // LEN=127
        expect((bytes[1] >> 4) & 0x0F, equals(15)); // LOW=15
        expect(bytes[1] & 0x0F, equals(0)); // HIGH=0
        expect(bytes.length, equals(258)); // 2 + 128*2
      });

      test('roundtrip 128 logs', () {
        final logs = List.generate(
          128,
          (i) => NoteLog(noteNum: i, velocity: 64),
        );
        final original = ChannelChapterN(logs: logs);
        final bytes = original.encode();
        final (decoded, consumed) = ChannelChapterN.decode(bytes)!;
        expect(decoded.logs.length, equals(128));
        expect(consumed, equals(258));
        for (int i = 0; i < 128; i++) {
          expect(decoded.logs[i].noteNum, equals(i));
          expect(decoded.logs[i].velocity, equals(64));
        }
      });
    });
  });
}
