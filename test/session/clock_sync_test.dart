import 'package:rtp_midi/src/session/clock_sync.dart';
import 'package:rtp_midi/src/session/exchange_packet.dart';
import 'package:test/test.dart';

void main() {
  group('createCk0', () {
    test('has count 0', () {
      final packet = createCk0(ssrc: 1, timestamp1: 100);
      expect(packet.count, 0);
    });

    test('sets timestamp1', () {
      final packet = createCk0(ssrc: 1, timestamp1: 12345);
      expect(packet.timestamp1, 12345);
    });

    test('timestamp2 is 0', () {
      final packet = createCk0(ssrc: 1, timestamp1: 100);
      expect(packet.timestamp2, 0);
    });

    test('timestamp3 is 0', () {
      final packet = createCk0(ssrc: 1, timestamp1: 100);
      expect(packet.timestamp3, 0);
    });

    test('sets correct ssrc', () {
      final packet = createCk0(ssrc: 0xABCD1234, timestamp1: 0);
      expect(packet.ssrc, 0xABCD1234);
    });

    test('roundtrips via encode/decode', () {
      final original = createCk0(ssrc: 42, timestamp1: 999);
      final decoded = ClockSyncPacket.decode(original.encode());
      expect(decoded, equals(original));
    });
  });

  group('createCk1', () {
    test('has count 1', () {
      final packet = createCk1(ssrc: 1, timestamp1: 100, timestamp2: 200);
      expect(packet.count, 1);
    });

    test('copies timestamp1 from CK0', () {
      final ck0 = createCk0(ssrc: 10, timestamp1: 5000);
      final ck1 = createCk1(
        ssrc: 20,
        timestamp1: ck0.timestamp1,
        timestamp2: 6000,
      );
      expect(ck1.timestamp1, ck0.timestamp1);
      expect(ck1.timestamp1, 5000);
    });

    test('sets timestamp2', () {
      final packet = createCk1(ssrc: 1, timestamp1: 100, timestamp2: 250);
      expect(packet.timestamp2, 250);
    });

    test('timestamp3 is 0', () {
      final packet = createCk1(ssrc: 1, timestamp1: 100, timestamp2: 200);
      expect(packet.timestamp3, 0);
    });

    test('sets correct ssrc (different from CK0 ssrc)', () {
      final packet = createCk1(
        ssrc: 0xBBBBCCCC,
        timestamp1: 100,
        timestamp2: 200,
      );
      expect(packet.ssrc, 0xBBBBCCCC);
    });

    test('roundtrips via encode/decode', () {
      final original = createCk1(ssrc: 7, timestamp1: 111, timestamp2: 222);
      final decoded = ClockSyncPacket.decode(original.encode());
      expect(decoded, equals(original));
    });
  });

  group('createCk2', () {
    test('has count 2', () {
      final packet = createCk2(
        ssrc: 1,
        timestamp1: 100,
        timestamp2: 200,
        timestamp3: 300,
      );
      expect(packet.count, 2);
    });

    test('copies timestamp1 and timestamp2 from CK1', () {
      final ck0 = createCk0(ssrc: 10, timestamp1: 1000);
      final ck1 = createCk1(
        ssrc: 20,
        timestamp1: ck0.timestamp1,
        timestamp2: 2000,
      );
      final ck2 = createCk2(
        ssrc: 10,
        timestamp1: ck1.timestamp1,
        timestamp2: ck1.timestamp2,
        timestamp3: 3000,
      );
      expect(ck2.timestamp1, 1000);
      expect(ck2.timestamp2, 2000);
    });

    test('sets timestamp3', () {
      final packet = createCk2(
        ssrc: 1,
        timestamp1: 100,
        timestamp2: 200,
        timestamp3: 300,
      );
      expect(packet.timestamp3, 300);
    });

    test('all three timestamps are set', () {
      final packet = createCk2(
        ssrc: 1,
        timestamp1: 111,
        timestamp2: 222,
        timestamp3: 333,
      );
      expect(packet.timestamp1, 111);
      expect(packet.timestamp2, 222);
      expect(packet.timestamp3, 333);
    });

    test('roundtrips via encode/decode', () {
      final original = createCk2(
        ssrc: 5,
        timestamp1: 500,
        timestamp2: 600,
        timestamp3: 700,
      );
      final decoded = ClockSyncPacket.decode(original.encode());
      expect(decoded, equals(original));
    });
  });

  group('computeOffset', () {
    group('known value calculations', () {
      test('t1=100, t2=200, t3=300 -> offset=0, latency=100 (in ticks)', () {
        // offset_ticks = ((100+300) - 2*200) / 2 = (400 - 400) / 2 = 0
        // latency_ticks = (300-100) / 2 = 100
        // Convert to microseconds: *100
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 100,
          timestamp2: 200,
          timestamp3: 300,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0);
        expect(result.latencyMicroseconds, 10000); // 100 ticks * 100 us/tick
      });

      test('t1=100, t2=250, t3=300 -> offset=-50 ticks, latency=100 ticks', () {
        // offset_ticks = ((100+300) - 2*250) / 2 = (400 - 500) / 2 = -50
        // latency_ticks = (300-100) / 2 = 100
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 100,
          timestamp2: 250,
          timestamp3: 300,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, -5000); // -50 * 100
        expect(result.latencyMicroseconds, 10000); // 100 * 100
      });

      test('t1=1000, t2=1050, t3=1100 -> offset=0, latency=50 ticks', () {
        // offset_ticks = ((1000+1100) - 2*1050) / 2 = (2100 - 2100) / 2 = 0
        // latency_ticks = (1100-1000) / 2 = 50
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 1000,
          timestamp2: 1050,
          timestamp3: 1100,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0);
        expect(result.latencyMicroseconds, 5000); // 50 * 100
      });

      test('asymmetric network: t1=100, t2=110, t3=200', () {
        // offset_ticks = ((100+200) - 2*110) / 2 = (300 - 220) / 2 = 40
        // latency_ticks = (200-100) / 2 = 50
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 100,
          timestamp2: 110,
          timestamp3: 200,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 4000); // 40 * 100
        expect(result.latencyMicroseconds, 5000); // 50 * 100
      });

      test('negative offset: remote clock is behind', () {
        // t1=100, t2=300, t3=200
        // offset_ticks = ((100+200) - 2*300) / 2 = (300 - 600) / 2 = -150
        // latency_ticks = (200-100) / 2 = 50
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 100,
          timestamp2: 300,
          timestamp3: 200,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, -15000); // -150 * 100
        expect(result.latencyMicroseconds, 5000); // 50 * 100
      });

      test('zero latency scenario: t1=t2=t3=1000', () {
        // offset_ticks = ((1000+1000) - 2*1000) / 2 = 0
        // latency_ticks = (1000-1000) / 2 = 0
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 1000,
          timestamp2: 1000,
          timestamp3: 1000,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0);
        expect(result.latencyMicroseconds, 0);
      });
    });

    group('edge cases', () {
      test('all timestamps zero', () {
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 0,
          timestamp2: 0,
          timestamp3: 0,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0);
        expect(result.latencyMicroseconds, 0);
      });

      test('equal timestamps (t1=t2=t3)', () {
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 500,
          timestamp2: 500,
          timestamp3: 500,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0);
        expect(result.latencyMicroseconds, 0);
      });

      test('very large timestamps', () {
        // Use large values that are safe for Dart integers
        const t1 = 1000000000; // 1 billion ticks
        const t2 = 1000000050;
        const t3 = 1000000100;
        // offset_ticks = ((1000000000+1000000100) - 2*1000000050) / 2 = 0
        // latency_ticks = (1000000100-1000000000) / 2 = 50
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: t1,
          timestamp2: t2,
          timestamp3: t3,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0);
        expect(result.latencyMicroseconds, 5000); // 50 * 100
      });

      test('timestamp1 equals timestamp3 (instant reply)', () {
        // t1=500, t2=600, t3=500 (impossible in reality but tests math)
        // offset_ticks = ((500+500) - 2*600) / 2 = (1000 - 1200) / 2 = -100
        // latency_ticks = (500-500) / 2 = 0
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 500,
          timestamp2: 600,
          timestamp3: 500,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, -10000); // -100 * 100
        expect(result.latencyMicroseconds, 0);
      });

      test('minimal non-zero: t1=0, t2=0, t3=1', () {
        // offset_ticks = ((0+1) - 2*0) / 2 = 1/2 = 0 (integer division)
        // latency_ticks = (1-0) / 2 = 0 (integer division)
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 0,
          timestamp2: 0,
          timestamp3: 1,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 0); // truncated
        expect(result.latencyMicroseconds, 0); // truncated
      });

      test('odd total for integer division truncation: t1=1, t2=0, t3=2', () {
        // offset_ticks = ((1+2) - 2*0) / 2 = 3/2 = 1 (truncated)
        // latency_ticks = (2-1) / 2 = 0 (truncated)
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 1,
          timestamp2: 0,
          timestamp3: 2,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 100); // 1 * 100
        expect(result.latencyMicroseconds, 0);
      });
    });

    group('conversion from ticks to microseconds', () {
      test('1 tick = 100 microseconds', () {
        // With offset of 1 tick and latency of 1 tick:
        // t1=0, t2=0, t3=4 -> offset_ticks = ((0+4) - 0) / 2 = 2
        // latency_ticks = 4/2 = 2
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 0,
          timestamp2: 0,
          timestamp3: 4,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 200); // 2 ticks * 100
        expect(result.latencyMicroseconds, 200); // 2 ticks * 100
      });

      test('10 ticks = 1000 microseconds = 1 millisecond', () {
        // t1=0, t2=0, t3=20 -> offset = 10 ticks, latency = 10 ticks
        final ck2 = createCk2(
          ssrc: 1,
          timestamp1: 0,
          timestamp2: 0,
          timestamp3: 20,
        );
        final result = computeOffset(ck2);
        expect(result.offsetMicroseconds, 1000);
        expect(result.latencyMicroseconds, 1000);
      });
    });
  });

  group('ClockSyncResult', () {
    test('equality works', () {
      const a = ClockSyncResult(
        offsetMicroseconds: 100,
        latencyMicroseconds: 50,
      );
      const b = ClockSyncResult(
        offsetMicroseconds: 100,
        latencyMicroseconds: 50,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different offset means not equal', () {
      const a = ClockSyncResult(
        offsetMicroseconds: 100,
        latencyMicroseconds: 50,
      );
      const b = ClockSyncResult(
        offsetMicroseconds: 200,
        latencyMicroseconds: 50,
      );
      expect(a, isNot(equals(b)));
    });

    test('different latency means not equal', () {
      const a = ClockSyncResult(
        offsetMicroseconds: 100,
        latencyMicroseconds: 50,
      );
      const b = ClockSyncResult(
        offsetMicroseconds: 100,
        latencyMicroseconds: 75,
      );
      expect(a, isNot(equals(b)));
    });

    test('toString produces readable output', () {
      const result = ClockSyncResult(
        offsetMicroseconds: -5000,
        latencyMicroseconds: 10000,
      );
      final str = result.toString();
      expect(str, contains('-5000'));
      expect(str, contains('10000'));
      expect(str, contains('us'));
    });
  });

  group('full clock sync exchange flow', () {
    test('initiator sends CK0, responder sends CK1, initiator sends CK2', () {
      const initiatorSsrc = 0x11111111;
      const responderSsrc = 0x22222222;

      // Step 1: Initiator creates CK0 with its current timestamp
      final ck0 = createCk0(ssrc: initiatorSsrc, timestamp1: 1000);
      expect(ck0.count, 0);
      expect(ck0.timestamp1, 1000);

      // Encode and decode (simulating network transit)
      final ck0Received = ClockSyncPacket.decode(ck0.encode())!;
      expect(ck0Received.count, 0);

      // Step 2: Responder creates CK1, copying t1, adding its own t2
      final ck1 = createCk1(
        ssrc: responderSsrc,
        timestamp1: ck0Received.timestamp1,
        timestamp2: 1050, // responder's clock at time of reply
      );
      expect(ck1.count, 1);
      expect(ck1.timestamp1, 1000);
      expect(ck1.timestamp2, 1050);

      final ck1Received = ClockSyncPacket.decode(ck1.encode())!;

      // Step 3: Initiator creates CK2, copying t1 and t2, adding t3
      final ck2 = createCk2(
        ssrc: initiatorSsrc,
        timestamp1: ck1Received.timestamp1,
        timestamp2: ck1Received.timestamp2,
        timestamp3: 1100, // initiator's clock at time of final send
      );
      expect(ck2.count, 2);

      // Step 4: Compute offset
      final result = computeOffset(ck2);
      // offset_ticks = ((1000+1100) - 2*1050) / 2 = 0
      // latency_ticks = (1100-1000) / 2 = 50
      expect(result.offsetMicroseconds, 0);
      expect(result.latencyMicroseconds, 5000); // 50 * 100
    });

    test('flow with clock offset between peers', () {
      const initiatorSsrc = 0xAAAA;
      const responderSsrc = 0xBBBB;

      // Initiator clock starts at 0, responder clock is 500 ticks ahead
      final ck0 = createCk0(ssrc: initiatorSsrc, timestamp1: 1000);

      // Network takes 10 ticks each way
      // Responder receives at its clock = 1000 + 500(offset) + 10(latency) = 1510
      final ck1 = createCk1(
        ssrc: responderSsrc,
        timestamp1: ck0.timestamp1,
        timestamp2: 1510,
      );

      // Initiator receives CK1 at its clock = 1000 + 10(to responder) + 10(back) = 1020
      final ck2 = createCk2(
        ssrc: initiatorSsrc,
        timestamp1: ck1.timestamp1,
        timestamp2: ck1.timestamp2,
        timestamp3: 1020,
      );

      final result = computeOffset(ck2);
      // offset_ticks = ((1000+1020) - 2*1510) / 2 = (2020 - 3020) / 2 = -500
      // latency_ticks = (1020-1000) / 2 = 10
      expect(result.offsetMicroseconds, -50000); // -500 * 100
      expect(result.latencyMicroseconds, 1000); // 10 * 100
    });
  });
}
