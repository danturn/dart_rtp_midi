import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/channel_journal_header.dart';
import 'package:test/test.dart';

void main() {
  group('ChannelJournalHeader', () {
    test('encode produces 3 bytes', () {
      const header = ChannelJournalHeader(channel: 0, length: 3);
      expect(header.encode().length, equals(3));
    });

    test('roundtrip with defaults', () {
      const original = ChannelJournalHeader(channel: 0, length: 3);
      final bytes = original.encode();
      final (decoded, consumed) = ChannelJournalHeader.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('roundtrip with all fields set', () {
      const original = ChannelJournalHeader(
        s: true,
        channel: 15,
        h: true,
        length: 1023,
        chapterP: true,
        chapterC: true,
        chapterM: true,
        chapterW: true,
        chapterN: true,
        chapterE: true,
        chapterT: true,
        chapterA: true,
      );
      final bytes = original.encode();
      final (decoded, consumed) = ChannelJournalHeader.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(3));
    });

    test('S flag at bit 7 of byte 0', () {
      const header = ChannelJournalHeader(s: true, channel: 0, length: 3);
      expect(header.encode()[0] & 0x80, equals(0x80));

      const noFlag = ChannelJournalHeader(channel: 0, length: 3);
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('CHAN at bits 6-3 of byte 0', () {
      const header = ChannelJournalHeader(channel: 9, length: 3);
      expect((header.encode()[0] >> 3) & 0x0F, equals(9));
    });

    test('CHAN max value 15', () {
      const header = ChannelJournalHeader(channel: 15, length: 3);
      final (decoded, _) = ChannelJournalHeader.decode(header.encode())!;
      expect(decoded.channel, equals(15));
    });

    test('H flag at bit 2 of byte 0', () {
      const header = ChannelJournalHeader(h: true, channel: 0, length: 3);
      expect(header.encode()[0] & 0x04, equals(0x04));

      const noFlag = ChannelJournalHeader(channel: 0, length: 3);
      expect(noFlag.encode()[0] & 0x04, equals(0));
    });

    test('LENGTH spans bits 1-0 of byte 0 and all of byte 1', () {
      const header = ChannelJournalHeader(channel: 0, length: 260);
      final bytes = header.encode();
      final length = ((bytes[0] & 0x03) << 8) | bytes[1];
      expect(length, equals(260));
    });

    test('LENGTH max value 1023', () {
      const header = ChannelJournalHeader(channel: 0, length: 1023);
      final bytes = header.encode();
      final length = ((bytes[0] & 0x03) << 8) | bytes[1];
      expect(length, equals(1023));
    });

    test('chapter P flag at bit 7 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterP: true);
      expect(header.encode()[2] & 0x80, equals(0x80));
    });

    test('chapter C flag at bit 6 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterC: true);
      expect(header.encode()[2] & 0x40, equals(0x40));
    });

    test('chapter M flag at bit 5 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterM: true);
      expect(header.encode()[2] & 0x20, equals(0x20));
    });

    test('chapter W flag at bit 4 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterW: true);
      expect(header.encode()[2] & 0x10, equals(0x10));
    });

    test('chapter N flag at bit 3 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterN: true);
      expect(header.encode()[2] & 0x08, equals(0x08));
    });

    test('chapter E flag at bit 2 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterE: true);
      expect(header.encode()[2] & 0x04, equals(0x04));
    });

    test('chapter T flag at bit 1 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterT: true);
      expect(header.encode()[2] & 0x02, equals(0x02));
    });

    test('chapter A flag at bit 0 of byte 2', () {
      const header =
          ChannelJournalHeader(channel: 0, length: 3, chapterA: true);
      expect(header.encode()[2] & 0x01, equals(0x01));
    });

    test('decode returns null for insufficient data', () {
      expect(ChannelJournalHeader.decode(Uint8List(0)), isNull);
      expect(ChannelJournalHeader.decode(Uint8List(1)), isNull);
      expect(ChannelJournalHeader.decode(Uint8List(2)), isNull);
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x48, 0x06, 0x80, // S=0, CHAN=9, H=0, LENGTH=6, P=1
      ]);
      final (decoded, consumed) = ChannelJournalHeader.decode(bytes, 1)!;
      expect(decoded.channel, equals(9));
      expect(decoded.length, equals(6));
      expect(decoded.chapterP, isTrue);
      expect(consumed, equals(3));
    });

    test('known binary vector: channel 0, P+N chapters', () {
      // S=1, CHAN=0, H=0, LENGTH=8, P=1, N=1
      final bytes = Uint8List.fromList([0x80, 0x08, 0x88]);
      final (decoded, consumed) = ChannelJournalHeader.decode(bytes)!;
      expect(decoded.s, isTrue);
      expect(decoded.channel, equals(0));
      expect(decoded.h, isFalse);
      expect(decoded.length, equals(8));
      expect(decoded.chapterP, isTrue);
      expect(decoded.chapterN, isTrue);
      expect(decoded.chapterC, isFalse);
      expect(consumed, equals(3));
    });

    test('equality', () {
      const a = ChannelJournalHeader(channel: 5, length: 10, chapterP: true);
      const b = ChannelJournalHeader(channel: 5, length: 10, chapterP: true);
      const c = ChannelJournalHeader(channel: 5, length: 11, chapterP: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('size is 3', () {
      expect(ChannelJournalHeader.size, equals(3));
    });
  });
}
