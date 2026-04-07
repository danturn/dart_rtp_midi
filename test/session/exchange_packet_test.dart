import 'dart:typed_data';

import 'package:rtp_midi/src/session/exchange_packet.dart';
import 'package:test/test.dart';

void main() {
  group('ExchangeCommand', () {
    test('invitation has code 0x494E ("IN")', () {
      expect(ExchangeCommand.invitation.code, 0x494E);
    });

    test('ok has code 0x4F4B ("OK")', () {
      expect(ExchangeCommand.ok.code, 0x4F4B);
    });

    test('no has code 0x4E4F ("NO")', () {
      expect(ExchangeCommand.no.code, 0x4E4F);
    });

    test('bye has code 0x4259 ("BY")', () {
      expect(ExchangeCommand.bye.code, 0x4259);
    });

    test('fromCode returns correct command for each code', () {
      expect(ExchangeCommand.fromCode(0x494E), ExchangeCommand.invitation);
      expect(ExchangeCommand.fromCode(0x4F4B), ExchangeCommand.ok);
      expect(ExchangeCommand.fromCode(0x4E4F), ExchangeCommand.no);
      expect(ExchangeCommand.fromCode(0x4259), ExchangeCommand.bye);
    });

    test('fromCode returns null for unknown codes', () {
      expect(ExchangeCommand.fromCode(0x0000), isNull);
      expect(ExchangeCommand.fromCode(0xFFFF), isNull);
      expect(ExchangeCommand.fromCode(0x434B), isNull); // 'CK' code
      expect(ExchangeCommand.fromCode(0x1234), isNull);
    });
  });

  group('ExchangePacket', () {
    group('roundtrip encode/decode', () {
      test('invitation packet roundtrips correctly', () {
        const original = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 0xDEADBEEF,
          ssrc: 0x12345678,
          name: 'TestDevice',
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
      });

      test('ok packet roundtrips correctly', () {
        const original = ExchangePacket(
          command: ExchangeCommand.ok,
          initiatorToken: 0xCAFEBABE,
          ssrc: 0xABCDEF01,
          name: 'Responder',
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
      });

      test('no packet roundtrips correctly', () {
        const original = ExchangePacket(
          command: ExchangeCommand.no,
          initiatorToken: 0x00000001,
          ssrc: 0x00000002,
          name: 'Rejector',
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
      });

      test('bye packet roundtrips correctly', () {
        const original = ExchangePacket(
          command: ExchangeCommand.bye,
          initiatorToken: 0xFFFFFFFF,
          ssrc: 0x87654321,
          name: 'GoodbyeDevice',
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
      });
    });

    group('known binary test vectors', () {
      test('invitation packet encodes to expected bytes', () {
        const packet = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 0x00000001,
          ssrc: 0x00000002,
          name: 'A',
        );
        final bytes = packet.encode();

        // Signature: 0xFFFF
        expect(bytes[0], 0xFF);
        expect(bytes[1], 0xFF);
        // Command: 0x494E ("IN")
        expect(bytes[2], 0x49);
        expect(bytes[3], 0x4E);
        // Protocol version: 2 (uint32 big-endian)
        expect(bytes[4], 0x00);
        expect(bytes[5], 0x00);
        expect(bytes[6], 0x00);
        expect(bytes[7], 0x02);
        // Initiator token: 1
        expect(bytes[8], 0x00);
        expect(bytes[9], 0x00);
        expect(bytes[10], 0x00);
        expect(bytes[11], 0x01);
        // SSRC: 2
        expect(bytes[12], 0x00);
        expect(bytes[13], 0x00);
        expect(bytes[14], 0x00);
        expect(bytes[15], 0x02);
        // Name: 'A' (UTF-8) + NUL
        expect(bytes[16], 0x41); // 'A'
        expect(bytes[17], 0x00); // NUL terminator
        expect(bytes.length, 18);
      });

      test('ok packet encodes to expected bytes', () {
        const packet = ExchangePacket(
          command: ExchangeCommand.ok,
          initiatorToken: 0xDEADBEEF,
          ssrc: 0xCAFEBABE,
          name: '',
        );
        final bytes = packet.encode();

        expect(bytes[2], 0x4F); // 'O'
        expect(bytes[3], 0x4B); // 'K'
        // Token: 0xDEADBEEF
        expect(bytes[8], 0xDE);
        expect(bytes[9], 0xAD);
        expect(bytes[10], 0xBE);
        expect(bytes[11], 0xEF);
        // SSRC: 0xCAFEBABE
        expect(bytes[12], 0xCA);
        expect(bytes[13], 0xFE);
        expect(bytes[14], 0xBA);
        expect(bytes[15], 0xBE);
        // Empty name, just NUL
        expect(bytes[16], 0x00);
        expect(bytes.length, 17); // minSize
      });

      test('decode from manually constructed bytes', () {
        // Construct a NO packet manually
        final bytes = Uint8List(18);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF); // signature
        view.setUint16(2, 0x4E4F); // 'NO'
        view.setUint32(4, 2); // version
        view.setUint32(8, 0xAAAABBBB); // token
        view.setUint32(12, 0xCCCCDDDD); // ssrc
        bytes[16] = 0x58; // 'X'
        bytes[17] = 0x00; // NUL

        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.command, ExchangeCommand.no);
        expect(decoded.protocolVersion, 2);
        expect(decoded.initiatorToken, 0xAAAABBBB);
        expect(decoded.ssrc, 0xCCCCDDDD);
        expect(decoded.name, 'X');
      });

      test('bye packet decodes from manually constructed bytes', () {
        final bytes = Uint8List(17);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x4259); // 'BY'
        view.setUint32(4, 2);
        view.setUint32(8, 0x11223344);
        view.setUint32(12, 0x55667788);
        bytes[16] = 0x00; // NUL (empty name)

        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.command, ExchangeCommand.bye);
        expect(decoded.initiatorToken, 0x11223344);
        expect(decoded.ssrc, 0x55667788);
        expect(decoded.name, '');
      });
    });

    group('name edge cases', () {
      test('empty name roundtrips correctly', () {
        const original = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: '',
        );
        final bytes = original.encode();
        expect(bytes.length, ExchangePacket.minSize);
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
        expect(decoded!.name, '');
      });

      test('long name roundtrips correctly', () {
        final longName = 'A' * 1000;
        final original = ExchangePacket(
          command: ExchangeCommand.ok,
          initiatorToken: 42,
          ssrc: 99,
          name: longName,
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
        expect(decoded!.name.length, 1000);
      });

      test('unicode name roundtrips correctly', () {
        const unicodeName = '\u{1F3B5}MIDI\u{2665}'; // musical note + heart
        const original = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 0xFF,
          ssrc: 0xAA,
          name: unicodeName,
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, equals(original));
        expect(decoded!.name, unicodeName);
      });

      test('Japanese name roundtrips correctly', () {
        const japaneseName = '\u30D4\u30A2\u30CE'; // katakana "piano"
        const original = ExchangePacket(
          command: ExchangeCommand.ok,
          initiatorToken: 7,
          ssrc: 8,
          name: japaneseName,
        );
        final bytes = original.encode();
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded!.name, japaneseName);
      });

      test('name with spaces roundtrips correctly', () {
        const name = 'My MIDI Device';
        const original = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: name,
        );
        final decoded = ExchangePacket.decode(original.encode());
        expect(decoded!.name, name);
      });
    });

    group('signature and version', () {
      test('encode always writes 0xFFFF signature', () {
        for (final cmd in ExchangeCommand.values) {
          final packet = ExchangePacket(
            command: cmd,
            initiatorToken: 0,
            ssrc: 0,
            name: '',
          );
          final bytes = packet.encode();
          final view = ByteData.sublistView(bytes);
          expect(view.getUint16(0), exchangeSignature,
              reason: 'Signature should be 0xFFFF for $cmd');
        }
      });

      test('encode always writes protocol version 2', () {
        const packet = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 0,
          ssrc: 0,
          name: '',
        );
        final bytes = packet.encode();
        final view = ByteData.sublistView(bytes);
        expect(view.getUint32(4), 2);
      });

      test('default protocolVersion is 2', () {
        const packet = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 0,
          ssrc: 0,
          name: '',
        );
        expect(packet.protocolVersion, 2);
      });

      test('decode preserves non-standard protocol version', () {
        // Build a packet with version 99 to verify decode reads whatever is there
        final bytes = Uint8List(17);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x494E); // 'IN'
        view.setUint32(4, 99); // non-standard version
        view.setUint32(8, 1);
        view.setUint32(12, 2);
        bytes[16] = 0x00;

        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.protocolVersion, 99);
      });
    });

    group('error handling', () {
      test('decode returns null for empty bytes', () {
        expect(ExchangePacket.decode(Uint8List(0)), isNull);
      });

      test('decode returns null for bytes shorter than minSize', () {
        expect(ExchangePacket.decode(Uint8List(1)), isNull);
        expect(ExchangePacket.decode(Uint8List(4)), isNull);
        expect(ExchangePacket.decode(Uint8List(16)), isNull);
      });

      test('decode returns null for wrong signature', () {
        final bytes = Uint8List(17);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0x0000); // wrong signature
        view.setUint16(2, 0x494E);
        view.setUint32(4, 2);
        view.setUint32(8, 1);
        view.setUint32(12, 2);
        bytes[16] = 0x00;

        expect(ExchangePacket.decode(bytes), isNull);
      });

      test('decode returns null for 0xFFFE signature', () {
        final bytes = Uint8List(17);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFE); // off by one
        view.setUint16(2, 0x494E);
        view.setUint32(4, 2);
        view.setUint32(8, 1);
        view.setUint32(12, 2);
        bytes[16] = 0x00;

        expect(ExchangePacket.decode(bytes), isNull);
      });

      test('decode returns null for unknown command code', () {
        final bytes = Uint8List(17);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x1234); // unknown command
        view.setUint32(4, 2);
        view.setUint32(8, 1);
        view.setUint32(12, 2);
        bytes[16] = 0x00;

        expect(ExchangePacket.decode(bytes), isNull);
      });

      test('decode returns null for CK command code (clock sync)', () {
        final bytes = Uint8List(36);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x434B); // 'CK'
        view.setUint32(4, 2);
        view.setUint32(8, 1);
        view.setUint32(12, 2);
        bytes[16] = 0x00;

        expect(ExchangePacket.decode(bytes), isNull);
      });

      test('decode handles packet with no NUL terminator gracefully', () {
        // Build a packet where the name field has no NUL terminator
        final bytes = Uint8List(18);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x494E); // 'IN'
        view.setUint32(4, 2);
        view.setUint32(8, 1);
        view.setUint32(12, 2);
        bytes[16] = 0x41; // 'A'
        bytes[17] = 0x42; // 'B' — no NUL

        // Should still decode, reading name up to end of buffer
        final decoded = ExchangePacket.decode(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.name, 'AB');
      });
    });

    group('equality and hashCode', () {
      test('identical packets are equal', () {
        const a = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Test',
        );
        const b = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Test',
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different commands are not equal', () {
        const a = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Test',
        );
        const b = ExchangePacket(
          command: ExchangeCommand.ok,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Test',
        );
        expect(a, isNot(equals(b)));
      });

      test('different tokens are not equal', () {
        const a = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Test',
        );
        const b = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 99,
          ssrc: 2,
          name: 'Test',
        );
        expect(a, isNot(equals(b)));
      });

      test('different names are not equal', () {
        const a = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Alice',
        );
        const b = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Bob',
        );
        expect(a, isNot(equals(b)));
      });
    });

    group('toString', () {
      test('produces readable output', () {
        const packet = ExchangePacket(
          command: ExchangeCommand.invitation,
          initiatorToken: 0xFF,
          ssrc: 0xAB,
          name: 'Test',
        );
        final str = packet.toString();
        expect(str, contains('invitation'));
        expect(str, contains('Test'));
        expect(str, contains('ff')); // hex token
      });
    });
  });

  group('ClockSyncPacket', () {
    group('roundtrip encode/decode', () {
      test('CK0 packet roundtrips correctly', () {
        const original = ClockSyncPacket(
          ssrc: 0x12345678,
          count: 0,
          timestamp1: 1000,
        );
        final bytes = original.encode();
        final decoded = ClockSyncPacket.decode(bytes);
        expect(decoded, equals(original));
        expect(decoded!.count, 0);
        expect(decoded.timestamp1, 1000);
        expect(decoded.timestamp2, 0);
        expect(decoded.timestamp3, 0);
      });

      test('CK1 packet roundtrips correctly', () {
        const original = ClockSyncPacket(
          ssrc: 0xAABBCCDD,
          count: 1,
          timestamp1: 1000,
          timestamp2: 2000,
        );
        final bytes = original.encode();
        final decoded = ClockSyncPacket.decode(bytes);
        expect(decoded, equals(original));
        expect(decoded!.count, 1);
        expect(decoded.timestamp1, 1000);
        expect(decoded.timestamp2, 2000);
        expect(decoded.timestamp3, 0);
      });

      test('CK2 packet roundtrips correctly', () {
        const original = ClockSyncPacket(
          ssrc: 0x11111111,
          count: 2,
          timestamp1: 1000,
          timestamp2: 2000,
          timestamp3: 3000,
        );
        final bytes = original.encode();
        final decoded = ClockSyncPacket.decode(bytes);
        expect(decoded, equals(original));
        expect(decoded!.count, 2);
        expect(decoded.timestamp1, 1000);
        expect(decoded.timestamp2, 2000);
        expect(decoded.timestamp3, 3000);
      });
    });

    group('known binary test vectors', () {
      test('CK0 packet encodes to expected bytes', () {
        const packet = ClockSyncPacket(
          ssrc: 0x00000001,
          count: 0,
          timestamp1: 0x0000000100000002, // hi=1, lo=2
        );
        final bytes = packet.encode();

        // Signature: 0xFFFF
        expect(bytes[0], 0xFF);
        expect(bytes[1], 0xFF);
        // Command: 'CK' (0x434B)
        expect(bytes[2], 0x43);
        expect(bytes[3], 0x4B);
        // SSRC: 1
        expect(bytes[4], 0x00);
        expect(bytes[5], 0x00);
        expect(bytes[6], 0x00);
        expect(bytes[7], 0x01);
        // Count: 0
        expect(bytes[8], 0x00);
        // Padding: 3 zero bytes
        expect(bytes[9], 0x00);
        expect(bytes[10], 0x00);
        expect(bytes[11], 0x00);
        // Total length is 36 bytes
        expect(bytes.length, ClockSyncPacket.size);
      });

      test('decode from manually constructed CK2 bytes', () {
        final bytes = Uint8List(36);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF); // sig
        view.setUint16(2, 0x434B); // 'CK'
        view.setUint32(4, 0xABCD1234); // ssrc
        bytes[8] = 2; // count
        // padding bytes 9-11 are zero
        // timestamp1 = 500 (hi=0, lo=500)
        view.setUint32(12, 0);
        view.setUint32(16, 500);
        // timestamp2 = 600
        view.setUint32(20, 0);
        view.setUint32(24, 600);
        // timestamp3 = 700
        view.setUint32(28, 0);
        view.setUint32(32, 700);

        final decoded = ClockSyncPacket.decode(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.ssrc, 0xABCD1234);
        expect(decoded.count, 2);
        expect(decoded.timestamp1, 500);
        expect(decoded.timestamp2, 600);
        expect(decoded.timestamp3, 700);
      });
    });

    group('timestamp edge cases', () {
      test('zero timestamps roundtrip', () {
        const original = ClockSyncPacket(
          ssrc: 1,
          count: 0,
          timestamp1: 0,
        );
        final decoded = ClockSyncPacket.decode(original.encode());
        expect(decoded!.timestamp1, 0);
        expect(decoded.timestamp2, 0);
        expect(decoded.timestamp3, 0);
      });

      test('large timestamps roundtrip', () {
        // Use a large but safe Dart integer (2^52 - 1 to stay within safe int range)
        const largeTs = (1 << 52) - 1; // 4503599627370495
        const original = ClockSyncPacket(
          ssrc: 1,
          count: 2,
          timestamp1: largeTs,
          timestamp2: largeTs - 1,
          timestamp3: largeTs - 2,
        );
        final decoded = ClockSyncPacket.decode(original.encode());
        expect(decoded!.timestamp1, largeTs);
        expect(decoded.timestamp2, largeTs - 1);
        expect(decoded.timestamp3, largeTs - 2);
      });

      test('timestamp with only high 32 bits set', () {
        const ts = 0x100000000; // 2^32
        const original = ClockSyncPacket(
          ssrc: 1,
          count: 0,
          timestamp1: ts,
        );
        final decoded = ClockSyncPacket.decode(original.encode());
        expect(decoded!.timestamp1, ts);
      });

      test('timestamp with both high and low 32 bits set', () {
        const ts = 0xABCD00001234; // mixed hi/lo
        const original = ClockSyncPacket(
          ssrc: 1,
          count: 0,
          timestamp1: ts,
        );
        final decoded = ClockSyncPacket.decode(original.encode());
        expect(decoded!.timestamp1, ts);
      });
    });

    group('signature and command code', () {
      test('encode always writes 0xFFFF signature', () {
        const packet = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 0);
        final bytes = packet.encode();
        final view = ByteData.sublistView(bytes);
        expect(view.getUint16(0), exchangeSignature);
      });

      test('encode always writes CK command code', () {
        const packet = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 0);
        final bytes = packet.encode();
        final view = ByteData.sublistView(bytes);
        expect(view.getUint16(2), ClockSyncPacket.commandCode);
      });

      test('commandCode constant is 0x434B', () {
        expect(ClockSyncPacket.commandCode, 0x434B);
      });

      test('size constant is 36', () {
        expect(ClockSyncPacket.size, 36);
      });
    });

    group('error handling', () {
      test('decode returns null for empty bytes', () {
        expect(ClockSyncPacket.decode(Uint8List(0)), isNull);
      });

      test('decode returns null for bytes shorter than 36', () {
        expect(ClockSyncPacket.decode(Uint8List(35)), isNull);
        expect(ClockSyncPacket.decode(Uint8List(4)), isNull);
        expect(ClockSyncPacket.decode(Uint8List(20)), isNull);
      });

      test('decode returns null for wrong signature', () {
        final bytes = Uint8List(36);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0x0000); // wrong
        view.setUint16(2, 0x434B);
        expect(ClockSyncPacket.decode(bytes), isNull);
      });

      test('decode returns null for non-CK command', () {
        final bytes = Uint8List(36);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x494E); // 'IN', not 'CK'
        expect(ClockSyncPacket.decode(bytes), isNull);
      });

      test('decode returns null for count > 2', () {
        final bytes = Uint8List(36);
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x434B);
        view.setUint32(4, 1); // ssrc
        bytes[8] = 3; // count=3 is invalid

        expect(ClockSyncPacket.decode(bytes), isNull);
      });

      test('decode accepts packet with extra trailing bytes', () {
        final bytes = Uint8List(40); // 4 extra bytes
        final view = ByteData.sublistView(bytes);
        view.setUint16(0, 0xFFFF);
        view.setUint16(2, 0x434B);
        view.setUint32(4, 99);
        bytes[8] = 0;

        final decoded = ClockSyncPacket.decode(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.ssrc, 99);
        expect(decoded.count, 0);
      });
    });

    group('equality and hashCode', () {
      test('identical packets are equal', () {
        const a = ClockSyncPacket(
            ssrc: 1,
            count: 2,
            timestamp1: 100,
            timestamp2: 200,
            timestamp3: 300);
        const b = ClockSyncPacket(
            ssrc: 1,
            count: 2,
            timestamp1: 100,
            timestamp2: 200,
            timestamp3: 300);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different timestamps are not equal', () {
        const a = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 100);
        const b = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 200);
        expect(a, isNot(equals(b)));
      });

      test('different counts are not equal', () {
        const a = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 100);
        const b = ClockSyncPacket(ssrc: 1, count: 1, timestamp1: 100);
        expect(a, isNot(equals(b)));
      });

      test('different ssrc are not equal', () {
        const a = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 100);
        const b = ClockSyncPacket(ssrc: 2, count: 0, timestamp1: 100);
        expect(a, isNot(equals(b)));
      });
    });

    group('toString', () {
      test('produces readable output', () {
        const packet = ClockSyncPacket(
            ssrc: 0xAB, count: 1, timestamp1: 100, timestamp2: 200);
        final str = packet.toString();
        expect(str, contains('ClockSyncPacket'));
        expect(str, contains('count: 1'));
        expect(str, contains('t1: 100'));
        expect(str, contains('t2: 200'));
      });
    });
  });

  group('isClockSyncPacket', () {
    test('returns true for CK packets', () {
      const ck = ClockSyncPacket(ssrc: 1, count: 0, timestamp1: 0);
      expect(isClockSyncPacket(ck.encode()), isTrue);
    });

    test('returns false for exchange packets', () {
      for (final cmd in ExchangeCommand.values) {
        final packet = ExchangePacket(
          command: cmd,
          initiatorToken: 1,
          ssrc: 2,
          name: 'Test',
        );
        expect(isClockSyncPacket(packet.encode()), isFalse,
            reason: 'Should be false for $cmd');
      }
    });

    test('returns null for bytes shorter than 4', () {
      expect(isClockSyncPacket(Uint8List(0)), isNull);
      expect(isClockSyncPacket(Uint8List(1)), isNull);
      expect(isClockSyncPacket(Uint8List(3)), isNull);
    });

    test('returns null for exactly 4 bytes with valid data', () {
      // 4 bytes is enough for isClockSyncPacket to check
      final bytes = Uint8List(4);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0xFFFF);
      view.setUint16(2, 0x434B);
      expect(isClockSyncPacket(bytes), isTrue);
    });

    test('returns null for wrong signature', () {
      final bytes = Uint8List(4);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0x1234);
      view.setUint16(2, 0x434B);
      expect(isClockSyncPacket(bytes), isNull);
    });

    test('returns false for unknown command with valid signature', () {
      final bytes = Uint8List(4);
      final view = ByteData.sublistView(bytes);
      view.setUint16(0, 0xFFFF);
      view.setUint16(2, 0x9999); // unknown
      expect(isClockSyncPacket(bytes), isFalse);
    });
  });

  group('exchangeSignature and protocolVersion constants', () {
    test('exchangeSignature is 0xFFFF', () {
      expect(exchangeSignature, 0xFFFF);
    });

    test('protocolVersion is 2', () {
      expect(protocolVersion, 2);
    });
  });
}
