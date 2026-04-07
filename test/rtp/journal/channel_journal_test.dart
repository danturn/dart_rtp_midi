import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/channel_chapter_a.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_c.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_e.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_m.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_n.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_p.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_t.dart';
import 'package:rtp_midi/src/rtp/journal/channel_chapter_w.dart';
import 'package:rtp_midi/src/rtp/journal/channel_journal.dart';
import 'package:test/test.dart';

void main() {
  group('ChannelJournal', () {
    test('encode/decode roundtrip: empty (no chapters)', () {
      const original = ChannelJournal(channel: 0);
      final bytes = original.encode();
      expect(bytes.length, equals(3)); // just the 3-byte header
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('encode/decode roundtrip: Chapter P only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 42, b: true, bankMsb: 3),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(6)); // 3 header + 3 P
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterP, isNotNull);
      expect(decoded.chapterP!.program, equals(42));
      expect(decoded.chapterP!.b, isTrue);
      expect(decoded.chapterP!.bankMsb, equals(3));
      expect(consumed, equals(6));
    });

    test('encode/decode roundtrip: Chapter T only', () {
      const original = ChannelJournal(
        channel: 5,
        chapterT: ChannelChapterT(pressure: 100),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(4)); // 3 header + 1 T
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterT, equals(original.chapterT));
      expect(consumed, equals(4));
    });

    test('encode/decode roundtrip: Chapter W only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterW: ChannelChapterW(first: 0, second: 64),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(5)); // 3 header + 2 W
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterW, equals(original.chapterW));
      expect(consumed, equals(5));
    });

    test('encode/decode roundtrip: Chapter C only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterC: ChannelChapterC(
          logs: [
            ControllerLog(number: 7, value: 100),
            ControllerLog(number: 10, value: 64),
          ],
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(8)); // 3 header + 5 C
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterC, equals(original.chapterC));
      expect(consumed, equals(8));
    });

    test('encode/decode roundtrip: Chapter N only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterN: ChannelChapterN(
          logs: [NoteLog(noteNum: 60, velocity: 100)],
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(7)); // 3 header + 4 N (2 hdr + 2 log)
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterN, equals(original.chapterN));
      expect(consumed, equals(7));
    });

    test('encode/decode roundtrip: Chapter E only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterE: ChannelChapterE(
          logs: [NoteExtraLog(noteNum: 60, countVel: 3)],
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(6)); // 3 header + 3 E
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterE, equals(original.chapterE));
      expect(consumed, equals(6));
    });

    test('encode/decode roundtrip: Chapter A only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterA: ChannelChapterA(
          logs: [PolyAftertouchLog(noteNum: 60, pressure: 80)],
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(6)); // 3 header + 3 A
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterA, equals(original.chapterA));
      expect(consumed, equals(6));
    });

    test('encode/decode roundtrip: Chapter M only', () {
      const original = ChannelJournal(
        channel: 0,
        chapterM: ChannelChapterM(
          logs: [ParamLog(pnumLsb: 10, pnumMsb: 20, q: false)],
        ),
      );
      final bytes = original.encode();
      // 3 header + 5 M (2 hdr + 3 log) = 8
      expect(bytes.length, equals(8));
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterM, equals(original.chapterM));
      expect(consumed, equals(8));
    });

    test('encode/decode roundtrip: P+N Apple combo', () {
      const original = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 0, b: true, bankMsb: 0),
        chapterN: ChannelChapterN(
          logs: [NoteLog(noteNum: 60, y: true, velocity: 100)],
        ),
      );
      final bytes = original.encode();
      // 3 header + 3 P + 4 N = 10
      expect(bytes.length, equals(10));
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.chapterP, equals(original.chapterP));
      expect(decoded.chapterN, equals(original.chapterN));
      expect(consumed, equals(10));
    });

    test('encode/decode roundtrip: all chapters', () {
      const original = ChannelJournal(
        s: true,
        channel: 9,
        chapterP: ChannelChapterP(program: 42),
        chapterC: ChannelChapterC(
          logs: [ControllerLog(number: 7, value: 100)],
        ),
        chapterM: ChannelChapterM(),
        chapterW: ChannelChapterW(first: 0, second: 64),
        chapterN: ChannelChapterN(logs: []),
        chapterE: ChannelChapterE(
          logs: [NoteExtraLog(noteNum: 60, countVel: 3)],
        ),
        chapterT: ChannelChapterT(pressure: 50),
        chapterA: ChannelChapterA(
          logs: [PolyAftertouchLog(noteNum: 60, pressure: 80)],
        ),
      );
      final bytes = original.encode();
      // 3 hdr + 3 P + 3 C + 2 M + 2 W + 2 N + 3 E + 1 T + 3 A = 22
      expect(bytes.length, equals(22));
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(decoded.s, isTrue);
      expect(decoded.channel, equals(9));
      expect(decoded.chapterP, equals(original.chapterP));
      expect(decoded.chapterC, equals(original.chapterC));
      expect(decoded.chapterM, equals(original.chapterM));
      expect(decoded.chapterW, equals(original.chapterW));
      expect(decoded.chapterN, equals(original.chapterN));
      expect(decoded.chapterE, equals(original.chapterE));
      expect(decoded.chapterT, equals(original.chapterT));
      expect(decoded.chapterA, equals(original.chapterA));
      expect(consumed, equals(22));
    });

    test('header S flag at bit 7', () {
      const journal = ChannelJournal(s: true, channel: 0);
      final bytes = journal.encode();
      expect(bytes[0] & 0x80, equals(0x80));
    });

    test('header CHAN at bits 6-3', () {
      const journal = ChannelJournal(channel: 9);
      final bytes = journal.encode();
      expect((bytes[0] >> 3) & 0x0F, equals(9));
    });

    test('header LENGTH includes all chapter sizes', () {
      const journal = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 0),
        chapterT: ChannelChapterT(pressure: 0),
      );
      final bytes = journal.encode();
      final length = ((bytes[0] & 0x03) << 8) | bytes[1];
      // 3 header + 3 P + 1 T = 7
      expect(length, equals(7));
    });

    test('chapter presence flags in byte 2', () {
      const journal = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(),
        chapterN: ChannelChapterN(logs: []),
      );
      final bytes = journal.encode();
      expect(bytes[2] & 0x80, equals(0x80)); // P
      expect(bytes[2] & 0x08, equals(0x08)); // N
      expect(bytes[2] & 0x40, equals(0)); // C absent
    });

    test('chapter order in wire format: P, C, M, W, N, E, T, A', () {
      const original = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 1),
        chapterC: ChannelChapterC(
          logs: [ControllerLog(number: 2, value: 3)],
        ),
        chapterW: ChannelChapterW(first: 10, second: 20),
        chapterT: ChannelChapterT(pressure: 99),
      );
      final bytes = original.encode();
      // 3 hdr + 3 P + 3 C + 2 W + 1 T = 12
      expect(bytes.length, equals(12));

      // P at offset 3
      expect(bytes[3] & 0x7F, equals(1)); // PROGRAM=1

      // C at offset 6
      expect(bytes[6] & 0x7F, equals(0)); // LEN=0 (1 log)
      expect(bytes[7] & 0x7F, equals(2)); // NUMBER=2
      expect(bytes[8] & 0x7F, equals(3)); // VALUE=3

      // W at offset 9
      expect(bytes[9] & 0x7F, equals(10)); // FIRST=10
      expect(bytes[10] & 0x7F, equals(20)); // SECOND=20

      // T at offset 11
      expect(bytes[11] & 0x7F, equals(99)); // PRESSURE=99
    });

    test('decode returns null for too-short data', () {
      expect(ChannelJournal.decode(Uint8List(2)), isNull);
      expect(ChannelJournal.decode(Uint8List(0)), isNull);
    });

    test('decode returns null when LENGTH exceeds buffer', () {
      final bytes = Uint8List.fromList([0x00, 0x0A, 0x00]); // LENGTH=10
      expect(ChannelJournal.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final data = Uint8List.fromList([
        0xFF, 0xFF, // padding
        0x00, 0x04, 0x02, // CHAN=0, LENGTH=4, T=1
        0x64, // Chapter T: PRESSURE=100
      ]);
      final (decoded, consumed) = ChannelJournal.decode(data, 2)!;
      expect(decoded.chapterT, isNotNull);
      expect(decoded.chapterT!.pressure, equals(100));
      expect(consumed, equals(4));
    });

    test('decode returns null when chapter data is truncated', () {
      // P flag set but LENGTH only allows header
      final bytes = Uint8List.fromList([0x00, 0x03, 0x80]); // LENGTH=3, P=1
      expect(ChannelJournal.decode(bytes), isNull);
    });

    test('equality', () {
      const a = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 5),
      );
      const b = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 5),
      );
      const c = ChannelJournal(
        channel: 0,
        chapterP: ChannelChapterP(program: 6),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('known binary vector: channel 0, P+C Apple-style', () {
      // Header: S=0, CHAN=0, H=0, LENGTH=9, P=1, C=1
      // P: PROGRAM=0, B=1, MSB=0, X=1, LSB=0
      // C: LEN=0, CC#7=100
      final bytes = Uint8List.fromList([
        0x00, 0x09, 0xC0, // header: LENGTH=9, P=1, C=1
        0x00, 0x80, 0x80, // P: program=0, B=1, MSB=0, X=1, LSB=0
        0x00, 0x07, 0x64, // C: LEN=0, CC#7=100
      ]);
      final (decoded, consumed) = ChannelJournal.decode(bytes)!;
      expect(consumed, equals(9));
      expect(decoded.channel, equals(0));
      expect(decoded.chapterP!.program, equals(0));
      expect(decoded.chapterP!.b, isTrue);
      expect(decoded.chapterC!.logs.length, equals(1));
      expect(decoded.chapterC!.logs[0].number, equals(7));
      expect(decoded.chapterC!.logs[0].value, equals(100));
    });
  });
}
