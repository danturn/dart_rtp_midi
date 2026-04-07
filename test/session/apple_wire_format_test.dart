/// Tests that our codec produces and parses packets compatible with Apple's
/// macOS Network MIDI implementation.
///
/// These test vectors are constructed to match the exact binary layout that
/// macOS Audio MIDI Setup sends and expects.
library;

import 'dart:typed_data';

import 'package:rtp_midi/src/session/exchange_packet.dart';
import 'package:test/test.dart';

/// Build a Uint8List from a list of int bytes.
Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('Apple-compatible invitation packet (IN)', () {
    // Realistic IN packet: signature=0xFFFF, command='IN' (0x494E),
    // version=2, token=0x01020304, ssrc=0xAABBCCDD, name="macOS Session\0"
    final appleInPacket = bytes([
      0xFF, 0xFF, // signature
      0x49, 0x4E, // 'IN'
      0x00, 0x00, 0x00, 0x02, // version = 2
      0x01, 0x02, 0x03, 0x04, // initiator token
      0xAA, 0xBB, 0xCC, 0xDD, // SSRC
      // "macOS Session" in UTF-8 + NUL
      0x6D, 0x61, 0x63, 0x4F, 0x53, 0x20, 0x53, 0x65,
      0x73, 0x73, 0x69, 0x6F, 0x6E, 0x00,
    ]);

    test('decode parses correctly', () {
      final packet = ExchangePacket.decode(appleInPacket);
      expect(packet, isNotNull);
      expect(packet!.command, ExchangeCommand.invitation);
      expect(packet.protocolVersion, 2);
      expect(packet.initiatorToken, 0x01020304);
      expect(packet.ssrc, 0xAABBCCDD);
      expect(packet.name, 'macOS Session');
    });

    test('re-encoding produces identical bytes', () {
      final packet = ExchangePacket.decode(appleInPacket)!;
      expect(packet.encode(), appleInPacket);
    });

    test('our encode produces bytes that Apple would accept', () {
      const packet = ExchangePacket(
        command: ExchangeCommand.invitation,
        initiatorToken: 0x01020304,
        ssrc: 0xAABBCCDD,
        name: 'macOS Session',
      );
      final encoded = packet.encode();

      // Verify wire format byte by byte
      final view = ByteData.sublistView(encoded);
      expect(view.getUint16(0), 0xFFFF, reason: 'signature');
      expect(view.getUint16(2), 0x494E, reason: 'command IN');
      expect(view.getUint32(4), 2, reason: 'version');
      expect(view.getUint32(8), 0x01020304, reason: 'token');
      expect(view.getUint32(12), 0xAABBCCDD, reason: 'ssrc');

      // Name is UTF-8 NUL-terminated
      expect(
          encoded.sublist(16, encoded.length - 1), 'macOS Session'.codeUnits);
      expect(encoded.last, 0, reason: 'NUL terminator');
    });
  });

  group('Apple-compatible OK packet', () {
    // OK response echoing the same token, different SSRC
    final appleOkPacket = bytes([
      0xFF, 0xFF, // signature
      0x4F, 0x4B, // 'OK'
      0x00, 0x00, 0x00, 0x02, // version = 2
      0x01, 0x02, 0x03, 0x04, // initiator token (echoed from IN)
      0x11, 0x22, 0x33, 0x44, // responder SSRC
      // "My Mac" + NUL
      0x4D, 0x79, 0x20, 0x4D, 0x61, 0x63, 0x00,
    ]);

    test('decode parses correctly', () {
      final packet = ExchangePacket.decode(appleOkPacket);
      expect(packet, isNotNull);
      expect(packet!.command, ExchangeCommand.ok);
      expect(packet.initiatorToken, 0x01020304);
      expect(packet.ssrc, 0x11223344);
      expect(packet.name, 'My Mac');
    });

    test('roundtrip preserves all fields', () {
      final packet = ExchangePacket.decode(appleOkPacket)!;
      final reEncoded = packet.encode();
      expect(ExchangePacket.decode(reEncoded), packet);
    });
  });

  group('Apple-compatible BY packet', () {
    final appleByPacket = bytes([
      0xFF, 0xFF, // signature
      0x42, 0x59, // 'BY'
      0x00, 0x00, 0x00, 0x02, // version = 2
      0xDE, 0xAD, 0xBE, 0xEF, // token
      0xAA, 0xBB, 0xCC, 0xDD, // SSRC
      0x54, 0x65, 0x73, 0x74, 0x00, // "Test" + NUL
    ]);

    test('decode parses correctly', () {
      final packet = ExchangePacket.decode(appleByPacket);
      expect(packet, isNotNull);
      expect(packet!.command, ExchangeCommand.bye);
      expect(packet.initiatorToken, 0xDEADBEEF);
      expect(packet.ssrc, 0xAABBCCDD);
      expect(packet.name, 'Test');
    });

    test('re-encoding produces identical bytes', () {
      final packet = ExchangePacket.decode(appleByPacket)!;
      expect(packet.encode(), appleByPacket);
    });
  });

  group('Apple-compatible CK0 packet', () {
    // CK0: initiator sends with timestamp1 set, timestamp2/3 zero
    final appleCk0 = bytes([
      0xFF, 0xFF, // signature
      0x43, 0x4B, // 'CK'
      0xAA, 0xBB, 0xCC, 0xDD, // SSRC
      0x00, // count = 0 (CK0)
      0x00, 0x00, 0x00, // padding
      // timestamp1: 0x0000000100000064 (4294967396 = high=1, low=100)
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x64,
      // timestamp2: 0
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      // timestamp3: 0
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]);

    test('detected as clock sync, not exchange', () {
      expect(isClockSyncPacket(appleCk0), isTrue);
      expect(ExchangePacket.decode(appleCk0), isNull);
    });

    test('decode parses correctly', () {
      final ck = ClockSyncPacket.decode(appleCk0);
      expect(ck, isNotNull);
      expect(ck!.ssrc, 0xAABBCCDD);
      expect(ck.count, 0);
      expect(ck.timestamp1, (1 << 32) | 100); // 4294967396
      expect(ck.timestamp2, 0);
      expect(ck.timestamp3, 0);
    });

    test('re-encoding produces identical bytes', () {
      final ck = ClockSyncPacket.decode(appleCk0)!;
      expect(ck.encode(), appleCk0);
    });
  });

  group('Apple-compatible CK1 packet', () {
    final appleCk1 = bytes([
      0xFF, 0xFF, // signature
      0x43, 0x4B, // 'CK'
      0x11, 0x22, 0x33, 0x44, // responder SSRC
      0x01, // count = 1 (CK1)
      0x00, 0x00, 0x00, // padding
      // timestamp1 (copied from CK0): 1000
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8,
      // timestamp2 (responder's time): 1050
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x1A,
      // timestamp3: 0
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]);

    test('decode parses all fields correctly', () {
      final ck = ClockSyncPacket.decode(appleCk1);
      expect(ck, isNotNull);
      expect(ck!.ssrc, 0x11223344);
      expect(ck.count, 1);
      expect(ck.timestamp1, 1000);
      expect(ck.timestamp2, 1050);
      expect(ck.timestamp3, 0);
    });

    test('re-encoding produces identical bytes', () {
      final ck = ClockSyncPacket.decode(appleCk1)!;
      expect(ck.encode(), appleCk1);
    });
  });

  group('Apple-compatible CK2 packet', () {
    final appleCk2 = bytes([
      0xFF, 0xFF, // signature
      0x43, 0x4B, // 'CK'
      0xAA, 0xBB, 0xCC, 0xDD, // initiator SSRC
      0x02, // count = 2 (CK2)
      0x00, 0x00, 0x00, // padding
      // timestamp1: 1000
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8,
      // timestamp2: 1050
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x1A,
      // timestamp3: 1100
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x4C,
    ]);

    test('decode parses all three timestamps', () {
      final ck = ClockSyncPacket.decode(appleCk2);
      expect(ck, isNotNull);
      expect(ck!.count, 2);
      expect(ck.timestamp1, 1000);
      expect(ck.timestamp2, 1050);
      expect(ck.timestamp3, 1100);
    });

    test('re-encoding produces identical bytes', () {
      final ck = ClockSyncPacket.decode(appleCk2)!;
      expect(ck.encode(), appleCk2);
    });
  });

  group('Full handshake byte sequence', () {
    // Simulate the exact sequence of packets in a real Apple session setup
    test('initiator perspective: IN -> OK -> IN(data) -> OK(data)', () {
      const localSsrc = 0x11111111;
      const remoteSsrc = 0x22222222;
      const token = 0xABCDEF01;

      // Step 1: We send IN
      const outgoingIn = ExchangePacket(
        command: ExchangeCommand.invitation,
        initiatorToken: token,
        ssrc: localSsrc,
        name: 'DartApp',
      );
      final inBytes = outgoingIn.encode();

      // Verify the wire bytes are well-formed
      final inView = ByteData.sublistView(inBytes);
      expect(inView.getUint16(0), 0xFFFF);
      expect(inView.getUint16(2), 0x494E);
      expect(inView.getUint32(8), token);

      // Step 2: Apple responds with OK (same token, different SSRC)
      const appleOk = ExchangePacket(
        command: ExchangeCommand.ok,
        initiatorToken: token,
        ssrc: remoteSsrc,
        name: "dan's MacBook Pro",
      );
      final okBytes = appleOk.encode();
      final decodedOk = ExchangePacket.decode(okBytes)!;
      expect(decodedOk.command, ExchangeCommand.ok);
      expect(decodedOk.initiatorToken, token,
          reason: 'Apple must echo our token');
      expect(decodedOk.ssrc, remoteSsrc);

      // Step 3: We send IN on data port (same token)
      const dataIn = ExchangePacket(
        command: ExchangeCommand.invitation,
        initiatorToken: token,
        ssrc: localSsrc,
        name: 'DartApp',
      );
      final dataInBytes = dataIn.encode();
      expect(dataInBytes, inBytes, reason: 'Same IN packet on both ports');

      // Step 4: Apple responds OK on data port
      final dataOkBytes = appleOk.encode();
      final decodedDataOk = ExchangePacket.decode(dataOkBytes)!;
      expect(decodedDataOk.initiatorToken, token);
    });
  });

  group('Packet with Unicode session name (macOS supports this)', () {
    test('Japanese session name roundtrips correctly', () {
      const packet = ExchangePacket(
        command: ExchangeCommand.invitation,
        initiatorToken: 0x12345678,
        ssrc: 0xABCDABCD,
        name: 'MIDIセッション',
      );
      final encoded = packet.encode();
      final decoded = ExchangePacket.decode(encoded)!;
      expect(decoded.name, 'MIDIセッション');
      expect(decoded.initiatorToken, 0x12345678);
    });

    test('emoji session name roundtrips correctly', () {
      const packet = ExchangePacket(
        command: ExchangeCommand.ok,
        initiatorToken: 0x1,
        ssrc: 0x2,
        name: 'Music 🎵',
      );
      final decoded = ExchangePacket.decode(packet.encode())!;
      expect(decoded.name, 'Music 🎵');
    });
  });

  group('Realistic timestamp values', () {
    test('macOS-scale timestamps (microseconds since boot / 100)', () {
      // A typical macOS timestamp after ~1 hour uptime:
      // 1 hour = 3,600,000,000 microseconds / 100 = 36,000,000 ticks
      const uptimeTs = 36000000;

      const ck0 = ClockSyncPacket(
        ssrc: 0xAABBCCDD,
        count: 0,
        timestamp1: uptimeTs,
      );

      final encoded = ck0.encode();
      final decoded = ClockSyncPacket.decode(encoded)!;
      expect(decoded.timestamp1, uptimeTs);
    });

    test('timestamps near 32-bit boundary', () {
      // After ~5 days: 4,320,000,000,000 us / 100 = 43,200,000,000
      // This exceeds 32 bits (max ~4.29 billion), testing hi/lo split
      const longUptimeTs = 43200000000;

      const ck = ClockSyncPacket(
        ssrc: 0x12345678,
        count: 0,
        timestamp1: longUptimeTs,
      );

      final encoded = ck.encode();
      final view = ByteData.sublistView(encoded);

      // Verify the hi/lo split is correct
      final hi = view.getUint32(12);
      final lo = view.getUint32(16);
      expect((hi << 32) | lo, longUptimeTs);

      // Verify roundtrip
      expect(ClockSyncPacket.decode(encoded)!.timestamp1, longUptimeTs);
    });
  });
}
