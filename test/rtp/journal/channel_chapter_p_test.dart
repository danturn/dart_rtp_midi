import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/journal/channel_chapter_p.dart';
import 'package:test/test.dart';

void main() {
  group('ChannelChapterP', () {
    test('encode produces 3 bytes', () {
      const chapter = ChannelChapterP();
      expect(chapter.encode().length, equals(3));
    });

    test('roundtrip with defaults', () {
      const original = ChannelChapterP();
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterP.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip with all fields set', () {
      const original = ChannelChapterP(
        s: true,
        program: 42,
        b: true,
        bankMsb: 3,
        x: true,
        bankLsb: 7,
      );
      final bytes = original.encode();
      final (decoded, consumed) = ChannelChapterP.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('S flag at bit 7 of byte 0', () {
      const chapter = ChannelChapterP(s: true);
      expect(chapter.encode()[0] & 0x80, equals(0x80));

      const noFlag = ChannelChapterP();
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('PROGRAM at bits 6-0 of byte 0', () {
      const chapter = ChannelChapterP(program: 99);
      expect(chapter.encode()[0] & 0x7F, equals(99));
    });

    test('B flag at bit 7 of byte 1', () {
      const chapter = ChannelChapterP(b: true);
      expect(chapter.encode()[1] & 0x80, equals(0x80));

      const noFlag = ChannelChapterP();
      expect(noFlag.encode()[1] & 0x80, equals(0));
    });

    test('BANK-MSB at bits 6-0 of byte 1', () {
      const chapter = ChannelChapterP(bankMsb: 120);
      expect(chapter.encode()[1] & 0x7F, equals(120));
    });

    test('X flag at bit 7 of byte 2', () {
      const chapter = ChannelChapterP(x: true);
      expect(chapter.encode()[2] & 0x80, equals(0x80));

      const noFlag = ChannelChapterP();
      expect(noFlag.encode()[2] & 0x80, equals(0));
    });

    test('BANK-LSB at bits 6-0 of byte 2', () {
      const chapter = ChannelChapterP(bankLsb: 55);
      expect(chapter.encode()[2] & 0x7F, equals(55));
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelChapterP.decode(Uint8List(0)), isNull);
      expect(ChannelChapterP.decode(Uint8List(1)), isNull);
      expect(ChannelChapterP.decode(Uint8List(2)), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([0xFF, 0xAA, 0x83, 0x05]);
      final (decoded, consumed) = ChannelChapterP.decode(bytes, 1)!;
      expect(decoded.s, isTrue);
      expect(decoded.program, equals(42));
      expect(decoded.b, isTrue);
      expect(decoded.bankMsb, equals(3));
      expect(decoded.x, isFalse);
      expect(decoded.bankLsb, equals(5));
      expect(consumed, equals(3));
    });

    test('known binary vector: Grand Piano bank 0', () {
      // S=0, PROGRAM=0, B=1, BANK-MSB=0, X=1, BANK-LSB=0
      final bytes = Uint8List.fromList([0x00, 0x80, 0x80]);
      final (decoded, consumed) = ChannelChapterP.decode(bytes)!;
      expect(decoded.s, isFalse);
      expect(decoded.program, equals(0));
      expect(decoded.b, isTrue);
      expect(decoded.bankMsb, equals(0));
      expect(decoded.x, isTrue);
      expect(decoded.bankLsb, equals(0));
      expect(consumed, equals(3));
    });

    test('equality', () {
      const a = ChannelChapterP(program: 5, bankMsb: 1);
      const b = ChannelChapterP(program: 5, bankMsb: 1);
      const c = ChannelChapterP(program: 5, bankMsb: 2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('size is 3', () {
      expect(ChannelChapterP.size, equals(3));
    });
  });
}
