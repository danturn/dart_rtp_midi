import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/system_chapter_d.dart';
import 'package:rtp_midi/src/rtp/journal/system_chapter_f.dart';
import 'package:rtp_midi/src/rtp/journal/system_chapter_q.dart';
import 'package:rtp_midi/src/rtp/journal/system_chapter_v.dart';
import 'package:rtp_midi/src/rtp/journal/system_chapter_x.dart';
import 'package:rtp_midi/src/rtp/journal/system_journal.dart';
import 'package:test/test.dart';

void main() {
  group('SystemJournal', () {
    test('encode/decode roundtrip: empty (no chapters)', () {
      const original = SystemJournal();
      final bytes = original.encode();
      expect(bytes.length, equals(2)); // just the 2-byte header
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(2));
    });

    test('encode/decode roundtrip: Chapter V only', () {
      const original = SystemJournal(
        chapterV: SystemChapterV(count: 42),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(3)); // 2 header + 1 V
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterV, isNotNull);
      expect(decoded.chapterV!.count, equals(42));
      expect(consumed, equals(3));
    });

    test('encode/decode roundtrip: Chapter Q header only (C=0, T=0)', () {
      const original = SystemJournal(
        chapterQ: SystemChapterQ(top: 5),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(3)); // 2 header + 1 Q
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterQ, equals(original.chapterQ));
      expect(consumed, equals(3));
    });

    test('encode/decode roundtrip: Chapter Q with CLOCK (C=1)', () {
      const original = SystemJournal(
        chapterQ: SystemChapterQ(c: true, top: 3, clock: 1000),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(5)); // 2 header + 3 Q
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterQ, equals(original.chapterQ));
      expect(consumed, equals(5));
    });

    test('encode/decode roundtrip: Chapter Q with CLOCK and TIMETOOLS', () {
      const original = SystemJournal(
        chapterQ: SystemChapterQ(
          c: true,
          t: true,
          top: 2,
          clock: 500,
          timetools: 0x0F0F0F,
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(8)); // 2 header + 6 Q
      final (decoded, _) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterQ, equals(original.chapterQ));
    });

    test('encode/decode roundtrip: Chapter F header only', () {
      const original = SystemJournal(
        chapterF: SystemChapterF(point: 5),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(3)); // 2 header + 1 F
      final (decoded, _) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterF, equals(original.chapterF));
    });

    test('encode/decode roundtrip: Chapter F with COMPLETE (4 bytes)', () {
      const original = SystemJournal(
        chapterF: SystemChapterF(
          c: true,
          q: true,
          point: 7,
          complete: 0x12345678,
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(7)); // 2 header + 5 F
      final (decoded, _) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterF, equals(original.chapterF));
    });

    test('encode/decode roundtrip: Chapter F with COMPLETE and PARTIAL', () {
      const original = SystemJournal(
        chapterF: SystemChapterF(
          c: true,
          p: true,
          q: true,
          point: 5,
          complete: 0xAAAAAAAA,
          partial: 0xBBBBBBBB,
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(11)); // 2 header + 9 F
      final (decoded, _) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterF, equals(original.chapterF));
    });

    test('encode/decode roundtrip: Chapter D only', () {
      const original = SystemJournal(
        chapterD: SystemChapterD(s: true),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(3)); // 2 header + 1 D
      final (decoded, _) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterD, equals(original.chapterD));
    });

    test('encode/decode roundtrip: Chapter X only', () {
      final original = SystemJournal(
        chapterX: SystemChapterX(
          sta: 1,
          data: Uint8List.fromList([0xF0, 0x7E, 0xF7]),
        ),
      );
      final bytes = original.encode();
      expect(bytes.length, equals(6)); // 2 header + 4 X
      final (decoded, _) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterX, equals(original.chapterX));
    });

    test('encode/decode roundtrip: Q and F together (Apple combo)', () {
      const original = SystemJournal(
        chapterQ: SystemChapterQ(c: true, top: 7, clock: 0xFFFF),
        chapterF: SystemChapterF(
          c: true,
          q: true,
          point: 7,
          complete: 0xABCDEF01,
        ),
      );
      final bytes = original.encode();
      // 2 header + 3 Q(C=1) + 5 F(C=1) = 10
      expect(bytes.length, equals(10));
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(decoded.chapterQ, equals(original.chapterQ));
      expect(decoded.chapterF, equals(original.chapterF));
      expect(consumed, equals(10));
    });

    test('encode/decode roundtrip: all chapters', () {
      final original = SystemJournal(
        s: true,
        chapterD: const SystemChapterD(s: true),
        chapterV: const SystemChapterV(count: 10),
        chapterQ: const SystemChapterQ(c: true, top: 1, clock: 24),
        chapterF: const SystemChapterF(point: 2),
        chapterX: SystemChapterX(
          sta: 0,
          data: Uint8List.fromList([0x01]),
        ),
      );
      final bytes = original.encode();
      // 2 header + 1 D + 1 V + 3 Q(C=1) + 1 F + 2 X = 10
      expect(bytes.length, equals(10));
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(decoded.s, isTrue);
      expect(decoded.chapterD, isNotNull);
      expect(decoded.chapterV, isNotNull);
      expect(decoded.chapterV!.count, equals(10));
      expect(decoded.chapterQ, equals(original.chapterQ));
      expect(decoded.chapterF, equals(original.chapterF));
      expect(decoded.chapterX, equals(original.chapterX));
      expect(consumed, equals(10));
    });

    test('system journal header S flag at bit 7', () {
      const journal = SystemJournal(s: true);
      final bytes = journal.encode();
      expect(bytes[0] & 0x80, equals(0x80));
    });

    test('system journal header D flag at bit 6', () {
      const journal = SystemJournal(chapterD: SystemChapterD());
      final bytes = journal.encode();
      expect(bytes[0] & 0x40, equals(0x40));
    });

    test('system journal header V flag at bit 5', () {
      const journal = SystemJournal(chapterV: SystemChapterV());
      final bytes = journal.encode();
      expect(bytes[0] & 0x20, equals(0x20));
    });

    test('system journal header Q flag at bit 4', () {
      const journal = SystemJournal(chapterQ: SystemChapterQ(top: 0));
      final bytes = journal.encode();
      expect(bytes[0] & 0x10, equals(0x10));
    });

    test('system journal header F flag at bit 3', () {
      const journal = SystemJournal(chapterF: SystemChapterF(point: 0));
      final bytes = journal.encode();
      expect(bytes[0] & 0x08, equals(0x08));
    });

    test('system journal header X flag at bit 2', () {
      const journal = SystemJournal(chapterX: SystemChapterX(sta: 0));
      final bytes = journal.encode();
      expect(bytes[0] & 0x04, equals(0x04));
    });

    test('LENGTH field spans bits 1-0 of byte 0 and all of byte 1', () {
      const journal = SystemJournal();
      final bytes = journal.encode();
      final length = ((bytes[0] & 0x03) << 8) | bytes[1];
      expect(length, equals(2));
    });

    test('LENGTH includes all chapter sizes', () {
      const journal = SystemJournal(
        chapterQ: SystemChapterQ(c: true, top: 0, clock: 0),
        chapterF: SystemChapterF(point: 0),
      );
      final bytes = journal.encode();
      final length = ((bytes[0] & 0x03) << 8) | bytes[1];
      // 2 header + 3 Q(C=1) + 1 F = 6
      expect(length, equals(6));
    });

    test('decode returns null for too-short data', () {
      expect(SystemJournal.decode(Uint8List(1)), isNull);
      expect(SystemJournal.decode(Uint8List(0)), isNull);
    });

    test('decode returns null when LENGTH exceeds buffer', () {
      final bytes = Uint8List.fromList([0x00, 0x0A]);
      expect(SystemJournal.decode(bytes), isNull);
    });

    test('decode with offset', () {
      final data = Uint8List.fromList([
        0xFF, 0xFF, // padding
        0x10, 0x04, // Q=1, LENGTH=4
        0x10, 0x00, 0x00, // Chapter Q: C=1, TOP=0, CLOCK=0
      ]);
      final (decoded, consumed) = SystemJournal.decode(data, 2)!;
      expect(decoded.chapterQ, isNotNull);
      expect(decoded.chapterQ!.c, isTrue);
      expect(consumed, equals(4));
    });

    test('known binary vector: Q+F Apple-style', () {
      // Q: N=1, D=1, C=1, TOP=0, CLOCK=24
      // F: POINT=3 (header only)
      // System journal header: Q=1, F=1, LENGTH = 2+3+1 = 6
      final bytes = Uint8List.fromList([
        0x18, 0x06, // Q=1, F=1, LENGTH=6
        0x70, 0x00, 0x18, // Q: N=1, D=1, C=1, TOP=0, CLOCK=24
        0x03, // F: POINT=3
      ]);
      final (decoded, consumed) = SystemJournal.decode(bytes)!;
      expect(consumed, equals(6));
      expect(decoded.chapterQ, isNotNull);
      expect(decoded.chapterQ!.n, isTrue);
      expect(decoded.chapterQ!.d, isTrue);
      expect(decoded.chapterQ!.c, isTrue);
      expect(decoded.chapterQ!.clock, equals(24));
      expect(decoded.chapterF, isNotNull);
      expect(decoded.chapterF!.point, equals(3));
    });

    test('equality', () {
      const a = SystemJournal(
        chapterQ: SystemChapterQ(c: true, top: 1, clock: 2),
      );
      const b = SystemJournal(
        chapterQ: SystemChapterQ(c: true, top: 1, clock: 2),
      );
      const c = SystemJournal(
        chapterQ: SystemChapterQ(c: true, top: 1, clock: 3),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('chapter order in wire format: D, V, Q, F, X', () {
      final original = SystemJournal(
        chapterD: SystemChapterD(
          b: true,
          logData: Uint8List.fromList([0x05]),
        ),
        chapterV: const SystemChapterV(count: 99),
        chapterQ: const SystemChapterQ(c: true, top: 3, clock: 0x1234),
        chapterF: const SystemChapterF(point: 5),
        chapterX: SystemChapterX(sta: 2, data: Uint8List.fromList([0xCC])),
      );
      final bytes = original.encode();

      // 2 header + 2 D(B+1 byte log) + 1 V + 3 Q(C=1) + 1 F + 2 X = 11
      expect(bytes.length, equals(11));

      // D at offset 2: flags byte
      expect(bytes[2] & 0x40, equals(0x40)); // B flag
      expect(bytes[3], equals(0x05)); // Reset log: COUNT=5

      // V at offset 4
      expect(bytes[4] & 0x7F, equals(99)); // COUNT=99

      // Q at offset 5: C=1, TOP=3
      expect(bytes[5] & 0x10, equals(0x10)); // C flag
      expect(bytes[5] & 0x07, equals(3)); // TOP
      expect(bytes[6], equals(0x12)); // CLOCK high
      expect(bytes[7], equals(0x34)); // CLOCK low

      // F at offset 8
      expect(bytes[8] & 0x07, equals(5)); // POINT

      // X at offset 9
      expect(bytes[9] & 0x03, equals(2)); // STA
      expect(bytes[10], equals(0xCC)); // data
    });

    test('decode returns null when chapter data is truncated', () {
      // Q flag set with C=1 in Q header, but LENGTH only allows 1 byte for Q
      final bytes = Uint8List.fromList([
        0x10, 0x03, // Q=1, LENGTH=3 (only 1 byte for Q)
        0x10, // Q header with C=1 → needs 3 bytes but only 1 available
      ]);
      expect(SystemJournal.decode(bytes), isNull);
    });
  });
}
