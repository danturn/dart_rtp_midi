import 'dart:typed_data';

import 'package:rtp_midi/src/session/exchange_packet.dart';
import 'package:rtp_midi/src/session/invitation_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('createInvitation', () {
    test('produces packet with invitation command', () {
      final packet = createInvitation(
        initiatorToken: 0xDEADBEEF,
        ssrc: 0x12345678,
        name: 'TestDevice',
      );
      expect(packet.command, ExchangeCommand.invitation);
    });

    test('sets correct initiatorToken', () {
      final packet = createInvitation(
        initiatorToken: 0xCAFEBABE,
        ssrc: 1,
        name: 'X',
      );
      expect(packet.initiatorToken, 0xCAFEBABE);
    });

    test('sets correct ssrc', () {
      final packet = createInvitation(
        initiatorToken: 1,
        ssrc: 0xABCD1234,
        name: 'X',
      );
      expect(packet.ssrc, 0xABCD1234);
    });

    test('sets correct name', () {
      final packet = createInvitation(
        initiatorToken: 1,
        ssrc: 2,
        name: 'My MIDI Device',
      );
      expect(packet.name, 'My MIDI Device');
    });

    test('has protocolVersion 2', () {
      final packet = createInvitation(
        initiatorToken: 1,
        ssrc: 2,
        name: 'Test',
      );
      expect(packet.protocolVersion, 2);
    });

    test('encodes and decodes correctly', () {
      final packet = createInvitation(
        initiatorToken: 0xFF00FF00,
        ssrc: 0x00FF00FF,
        name: 'Roundtrip',
      );
      final decoded = ExchangePacket.decode(packet.encode());
      expect(decoded, equals(packet));
    });
  });

  group('createOk', () {
    test('produces packet with ok command', () {
      final packet = createOk(
        initiatorToken: 0xDEADBEEF,
        ssrc: 0x12345678,
        name: 'Responder',
      );
      expect(packet.command, ExchangeCommand.ok);
    });

    test('echoes back initiatorToken from invitation', () {
      const token = 0xAAAABBBB;
      final invitation = createInvitation(
        initiatorToken: token,
        ssrc: 1,
        name: 'Initiator',
      );
      final ok = createOk(
        initiatorToken: invitation.initiatorToken,
        ssrc: 2,
        name: 'Responder',
      );
      expect(ok.initiatorToken, token);
      expect(ok.initiatorToken, invitation.initiatorToken);
    });

    test('sets correct ssrc', () {
      final packet = createOk(
        initiatorToken: 1,
        ssrc: 0x99887766,
        name: 'X',
      );
      expect(packet.ssrc, 0x99887766);
    });

    test('sets correct name', () {
      final packet = createOk(
        initiatorToken: 1,
        ssrc: 2,
        name: 'Acceptor',
      );
      expect(packet.name, 'Acceptor');
    });

    test('has protocolVersion 2', () {
      final packet = createOk(
        initiatorToken: 1,
        ssrc: 2,
        name: 'Test',
      );
      expect(packet.protocolVersion, 2);
    });

    test('encodes and decodes correctly', () {
      final packet = createOk(
        initiatorToken: 42,
        ssrc: 99,
        name: 'OkDevice',
      );
      final decoded = ExchangePacket.decode(packet.encode());
      expect(decoded, equals(packet));
    });
  });

  group('createNo', () {
    test('produces packet with no command', () {
      final packet = createNo(
        initiatorToken: 0x11111111,
        ssrc: 0x22222222,
        name: 'Rejector',
      );
      expect(packet.command, ExchangeCommand.no);
    });

    test('echoes back initiatorToken', () {
      const token = 0xCCCCDDDD;
      final packet = createNo(
        initiatorToken: token,
        ssrc: 1,
        name: 'X',
      );
      expect(packet.initiatorToken, token);
    });

    test('sets correct ssrc', () {
      final packet = createNo(
        initiatorToken: 1,
        ssrc: 0xEEEEFFFF,
        name: 'X',
      );
      expect(packet.ssrc, 0xEEEEFFFF);
    });

    test('sets correct name', () {
      final packet = createNo(
        initiatorToken: 1,
        ssrc: 2,
        name: 'NoPeDevice',
      );
      expect(packet.name, 'NoPeDevice');
    });

    test('has protocolVersion 2', () {
      final packet = createNo(
        initiatorToken: 1,
        ssrc: 2,
        name: 'Test',
      );
      expect(packet.protocolVersion, 2);
    });

    test('encodes and decodes correctly', () {
      final packet = createNo(
        initiatorToken: 7,
        ssrc: 8,
        name: 'NoDevice',
      );
      final decoded = ExchangePacket.decode(packet.encode());
      expect(decoded, equals(packet));
    });
  });

  group('createBye', () {
    test('produces packet with bye command', () {
      final packet = createBye(
        initiatorToken: 0xFFFFFFFF,
        ssrc: 0x87654321,
        name: 'Goodbye',
      );
      expect(packet.command, ExchangeCommand.bye);
    });

    test('sets correct initiatorToken', () {
      final packet = createBye(
        initiatorToken: 0xBEEFCAFE,
        ssrc: 1,
        name: 'X',
      );
      expect(packet.initiatorToken, 0xBEEFCAFE);
    });

    test('sets correct ssrc', () {
      final packet = createBye(
        initiatorToken: 1,
        ssrc: 0x44556677,
        name: 'X',
      );
      expect(packet.ssrc, 0x44556677);
    });

    test('sets correct name', () {
      final packet = createBye(
        initiatorToken: 1,
        ssrc: 2,
        name: 'ByeDevice',
      );
      expect(packet.name, 'ByeDevice');
    });

    test('has protocolVersion 2', () {
      final packet = createBye(
        initiatorToken: 1,
        ssrc: 2,
        name: 'Test',
      );
      expect(packet.protocolVersion, 2);
    });

    test('encodes and decodes correctly', () {
      final packet = createBye(
        initiatorToken: 0xAA,
        ssrc: 0xBB,
        name: 'ByeRoundtrip',
      );
      final decoded = ExchangePacket.decode(packet.encode());
      expect(decoded, equals(packet));
    });
  });

  group('nextRetryDelay', () {
    group('exponential backoff with default parameters', () {
      test('attempt 0 returns baseInterval (1500ms)', () {
        final delay = nextRetryDelay(attempt: 0);
        expect(delay, const Duration(milliseconds: 1500));
      });

      test('attempt 1 returns 3000ms', () {
        final delay = nextRetryDelay(attempt: 1);
        expect(delay, const Duration(milliseconds: 3000));
      });

      test('attempt 2 returns 6000ms', () {
        final delay = nextRetryDelay(attempt: 2);
        expect(delay, const Duration(milliseconds: 6000));
      });

      test('attempt 3 returns 12000ms', () {
        final delay = nextRetryDelay(attempt: 3);
        expect(delay, const Duration(milliseconds: 12000));
      });

      test('attempt 4 returns 24000ms', () {
        final delay = nextRetryDelay(attempt: 4);
        expect(delay, const Duration(milliseconds: 24000));
      });

      test('attempt 5 returns 48000ms', () {
        final delay = nextRetryDelay(attempt: 5);
        expect(delay, const Duration(milliseconds: 48000));
      });

      test('attempt 11 returns 3072000ms (~51 minutes)', () {
        final delay = nextRetryDelay(attempt: 11);
        // 1500 * 2^11 = 1500 * 2048 = 3072000
        expect(delay, const Duration(milliseconds: 3072000));
      });

      test('attempt 12 returns null (max retries exceeded)', () {
        final delay = nextRetryDelay(attempt: 12);
        expect(delay, isNull);
      });

      test('attempt 13 returns null', () {
        final delay = nextRetryDelay(attempt: 13);
        expect(delay, isNull);
      });

      test('attempt 100 returns null', () {
        final delay = nextRetryDelay(attempt: 100);
        expect(delay, isNull);
      });
    });

    group('exponential backoff with custom parameters', () {
      test('custom baseInterval 1000ms', () {
        final delay = nextRetryDelay(
          attempt: 0,
          baseInterval: const Duration(milliseconds: 1000),
        );
        expect(delay, const Duration(milliseconds: 1000));
      });

      test('custom baseInterval 1000ms attempt 3', () {
        final delay = nextRetryDelay(
          attempt: 3,
          baseInterval: const Duration(milliseconds: 1000),
        );
        // 1000 * 2^3 = 8000
        expect(delay, const Duration(milliseconds: 8000));
      });

      test('custom maxRetries 3', () {
        expect(
          nextRetryDelay(attempt: 0, maxRetries: 3),
          isNotNull,
        );
        expect(
          nextRetryDelay(attempt: 2, maxRetries: 3),
          isNotNull,
        );
        expect(
          nextRetryDelay(attempt: 3, maxRetries: 3),
          isNull,
        );
      });

      test('maxRetries 1 allows only attempt 0', () {
        expect(nextRetryDelay(attempt: 0, maxRetries: 1), isNotNull);
        expect(nextRetryDelay(attempt: 1, maxRetries: 1), isNull);
      });

      test('maxRetries 0 allows no attempts', () {
        expect(nextRetryDelay(attempt: 0, maxRetries: 0), isNull);
      });
    });

    group('edge cases', () {
      test('negative attempt returns null', () {
        expect(nextRetryDelay(attempt: -1), isNull);
        expect(nextRetryDelay(attempt: -100), isNull);
      });

      test('each successive attempt exactly doubles the previous', () {
        Duration? prev;
        for (var i = 0; i < 12; i++) {
          final current = nextRetryDelay(attempt: i)!;
          if (prev != null) {
            expect(current, prev * 2,
                reason: 'attempt $i should be double attempt ${i - 1}');
          }
          prev = current;
        }
      });

      test('custom base interval with large attempt', () {
        final delay = nextRetryDelay(
          attempt: 10,
          baseInterval: const Duration(seconds: 1),
          maxRetries: 20,
        );
        // 1000 * 2^10 = 1024000ms
        expect(delay, const Duration(milliseconds: 1024000));
      });
    });
  });

  group('all packet constructors produce protocolVersion 2', () {
    test('createInvitation', () {
      expect(
        createInvitation(initiatorToken: 1, ssrc: 2, name: '').protocolVersion,
        2,
      );
    });

    test('createOk', () {
      expect(
        createOk(initiatorToken: 1, ssrc: 2, name: '').protocolVersion,
        2,
      );
    });

    test('createNo', () {
      expect(
        createNo(initiatorToken: 1, ssrc: 2, name: '').protocolVersion,
        2,
      );
    });

    test('createBye', () {
      expect(
        createBye(initiatorToken: 1, ssrc: 2, name: '').protocolVersion,
        2,
      );
    });
  });

  group('all packet constructors produce valid wire format', () {
    test('createInvitation encodes with correct signature and command', () {
      final bytes = createInvitation(
        initiatorToken: 1,
        ssrc: 2,
        name: 'T',
      ).encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint16(0), exchangeSignature);
      expect(view.getUint16(2), ExchangeCommand.invitation.code);
      expect(view.getUint32(4), protocolVersion);
    });

    test('createOk encodes with correct signature and command', () {
      final bytes = createOk(
        initiatorToken: 1,
        ssrc: 2,
        name: 'T',
      ).encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint16(0), exchangeSignature);
      expect(view.getUint16(2), ExchangeCommand.ok.code);
      expect(view.getUint32(4), protocolVersion);
    });

    test('createNo encodes with correct signature and command', () {
      final bytes = createNo(
        initiatorToken: 1,
        ssrc: 2,
        name: 'T',
      ).encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint16(0), exchangeSignature);
      expect(view.getUint16(2), ExchangeCommand.no.code);
      expect(view.getUint32(4), protocolVersion);
    });

    test('createBye encodes with correct signature and command', () {
      final bytes = createBye(
        initiatorToken: 1,
        ssrc: 2,
        name: 'T',
      ).encode();
      final view = ByteData.sublistView(bytes);
      expect(view.getUint16(0), exchangeSignature);
      expect(view.getUint16(2), ExchangeCommand.bye.code);
      expect(view.getUint32(4), protocolVersion);
    });
  });
}
