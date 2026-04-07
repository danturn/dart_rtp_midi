import 'dart:typed_data';

import 'package:rtp_midi/src/rtp/journal/journal_header.dart';
import 'package:test/test.dart';

void main() {
  group('JournalHeader', () {
    test('encode produces 3 bytes', () {
      const header = JournalHeader(checkpointSeqNum: 0);
      expect(header.encode().length, equals(3));
    });

    test('encode/decode roundtrip with defaults', () {
      const original = JournalHeader(checkpointSeqNum: 42);
      final bytes = original.encode();
      final decoded = JournalHeader.decode(bytes);
      expect(decoded, equals(original));
    });

    test('encode/decode roundtrip with all flags set', () {
      const original = JournalHeader(
        singlePacketLoss: true,
        systemJournalPresent: true,
        channelJournalsPresent: true,
        enhancedChapterC: true,
        totalChannels: 15,
        checkpointSeqNum: 0xFFFF,
      );
      final bytes = original.encode();
      final decoded = JournalHeader.decode(bytes);
      expect(decoded, equals(original));
    });

    test('S flag at bit 7 of byte 0', () {
      const header = JournalHeader(
        singlePacketLoss: true,
        checkpointSeqNum: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x80, equals(0x80));

      const noFlag = JournalHeader(checkpointSeqNum: 0);
      expect(noFlag.encode()[0] & 0x80, equals(0));
    });

    test('Y flag at bit 6 of byte 0', () {
      const header = JournalHeader(
        systemJournalPresent: true,
        checkpointSeqNum: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x40, equals(0x40));
    });

    test('A flag at bit 5 of byte 0', () {
      const header = JournalHeader(
        channelJournalsPresent: true,
        checkpointSeqNum: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x20, equals(0x20));
    });

    test('H flag at bit 4 of byte 0', () {
      const header = JournalHeader(
        enhancedChapterC: true,
        checkpointSeqNum: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x10, equals(0x10));
    });

    test('TOTCHAN at bits 3-0 of byte 0', () {
      const header = JournalHeader(
        totalChannels: 9,
        checkpointSeqNum: 0,
      );
      final bytes = header.encode();
      expect(bytes[0] & 0x0F, equals(9));
    });

    test('checkpoint sequence number in bytes 1-2', () {
      const header = JournalHeader(checkpointSeqNum: 0x1234);
      final bytes = header.encode();
      expect(bytes[1], equals(0x12));
      expect(bytes[2], equals(0x34));
    });

    test('decode returns null for too-short data', () {
      expect(JournalHeader.decode(Uint8List(2)), isNull);
      expect(JournalHeader.decode(Uint8List(0)), isNull);
    });

    test('decode with offset', () {
      // 2 bytes padding + 3 bytes header
      final bytes = Uint8List.fromList([
        0xFF, 0xFF, // padding
        0xF9, // S=1, Y=1, A=1, H=1, TOTCHAN=9
        0x00, 0x2A, // checkpoint = 42
      ]);
      final decoded = JournalHeader.decode(bytes, 2);
      expect(decoded, isNotNull);
      expect(decoded!.singlePacketLoss, isTrue);
      expect(decoded.systemJournalPresent, isTrue);
      expect(decoded.channelJournalsPresent, isTrue);
      expect(decoded.enhancedChapterC, isTrue);
      expect(decoded.totalChannels, equals(9));
      expect(decoded.checkpointSeqNum, equals(42));
    });

    test('decode returns null when offset leaves insufficient bytes', () {
      final bytes = Uint8List(4); // 4 bytes total
      expect(JournalHeader.decode(bytes, 2), isNull); // only 2 bytes left
    });

    test('known binary vector', () {
      // S=1, Y=1, A=0, H=0, TOTCHAN=3, checkpoint=1000
      final bytes = Uint8List.fromList([
        0xC3, // 1100_0011
        0x03, 0xE8, // 1000
      ]);
      final decoded = JournalHeader.decode(bytes)!;
      expect(decoded.singlePacketLoss, isTrue);
      expect(decoded.systemJournalPresent, isTrue);
      expect(decoded.channelJournalsPresent, isFalse);
      expect(decoded.enhancedChapterC, isFalse);
      expect(decoded.totalChannels, equals(3));
      expect(decoded.checkpointSeqNum, equals(1000));
    });

    test('equality', () {
      const a = JournalHeader(checkpointSeqNum: 1, totalChannels: 5);
      const b = JournalHeader(checkpointSeqNum: 1, totalChannels: 5);
      const c = JournalHeader(checkpointSeqNum: 2, totalChannels: 5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('totalChannels max value 15', () {
      const header = JournalHeader(
        totalChannels: 15,
        checkpointSeqNum: 0,
      );
      final decoded = JournalHeader.decode(header.encode());
      expect(decoded!.totalChannels, equals(15));
    });

    test('checkpoint seqnum wrapping at 16 bits', () {
      const header = JournalHeader(checkpointSeqNum: 0xFFFF);
      final decoded = JournalHeader.decode(header.encode());
      expect(decoded!.checkpointSeqNum, equals(0xFFFF));
    });
  });
}
