import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/session_error.dart';
import 'package:test/test.dart';

void main() {
  group('hexDump', () {
    test('encodes bytes as hex pairs', () {
      final error = MalformedPacket(
        message: 'bad packet',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: Uint8List.fromList([0xFF, 0xFF, 0x00, 0xAB]),
        packetType: PacketType.exchange,
      );
      expect(error.hexDump, 'ffff00ab');
    });

    test('truncates to first 64 bytes', () {
      final bytes = Uint8List(128);
      for (var i = 0; i < 128; i++) {
        bytes[i] = i;
      }
      final error = MalformedPacket(
        message: 'big packet',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: bytes,
        packetType: PacketType.rtpMidi,
      );
      // 64 bytes = 128 hex chars
      expect(error.hexDump.length, 128);
      // Starts with 00010203...
      expect(error.hexDump.substring(0, 8), '00010203');
      // Ends with byte 63 = 0x3f
      expect(error.hexDump.substring(126, 128), '3f');
    });

    test('handles empty bytes', () {
      final error = MalformedPacket(
        message: 'empty',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: Uint8List(0),
        packetType: PacketType.exchange,
      );
      expect(error.hexDump, '');
    });
  });

  group('MalformedPacket', () {
    test('stores all fields', () {
      final raw = Uint8List.fromList([1, 2, 3]);
      final error = MalformedPacket(
        message: 'Invalid handshake packet',
        address: '192.168.1.100',
        port: 5004,
        rawBytes: raw,
        packetType: PacketType.exchange,
      );
      expect(error.message, 'Invalid handshake packet');
      expect(error.address, '192.168.1.100');
      expect(error.port, 5004);
      expect(error.rawBytes, raw);
      expect(error.packetType, PacketType.exchange);
    });

    test('toString includes type, message, and hexDump', () {
      final error = MalformedPacket(
        message: 'bad',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: Uint8List.fromList([0xDE, 0xAD]),
        packetType: PacketType.clockSync,
      );
      expect(error.toString(), 'MalformedPacket: bad [dead]');
    });
  });

  group('ConnectionFailed', () {
    test('stores all fields', () {
      final error = ConnectionFailed(
        message: 'No response after 12 retries',
        address: '192.168.1.100',
        port: 5004,
        reason: ConnectionFailedReason.timeout,
      );
      expect(error.message, 'No response after 12 retries');
      expect(error.address, '192.168.1.100');
      expect(error.port, 5004);
      expect(error.reason, ConnectionFailedReason.timeout);
    });

    test('toString format', () {
      final error = ConnectionFailed(
        message: 'Rejected',
        address: '10.0.0.1',
        port: 5004,
        reason: ConnectionFailedReason.rejected,
      );
      expect(error.toString(), 'ConnectionFailed: Rejected');
    });
  });

  group('ProtocolViolation', () {
    test('stores all fields including optional rawBytes', () {
      final raw = Uint8List.fromList([0xCA, 0xFE]);
      final error = ProtocolViolation(
        message: 'Token mismatch',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: raw,
        reason: ProtocolViolationReason.tokenMismatch,
      );
      expect(error.rawBytes, raw);
      expect(error.reason, ProtocolViolationReason.tokenMismatch);
    });

    test('toString with rawBytes', () {
      final error = ProtocolViolation(
        message: 'Token mismatch',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: Uint8List.fromList([0xAB]),
        reason: ProtocolViolationReason.tokenMismatch,
      );
      expect(error.toString(), 'ProtocolViolation: Token mismatch [ab]');
    });

    test('toString without rawBytes', () {
      final error = ProtocolViolation(
        message: 'Send before ready',
        address: '10.0.0.1',
        port: 5004,
        reason: ProtocolViolationReason.sendBeforeReady,
      );
      expect(error.toString(), 'ProtocolViolation: Send before ready');
    });
  });

  group('PeerDisconnected', () {
    test('stores all fields', () {
      final error = PeerDisconnected(
        message: 'Remote sent BYE',
        address: '192.168.1.100',
        port: 5004,
        reason: PeerDisconnectedReason.byeReceived,
      );
      expect(error.message, 'Remote sent BYE');
      expect(error.reason, PeerDisconnectedReason.byeReceived);
    });

    test('toString format', () {
      final error = PeerDisconnected(
        message: 'Idle timeout',
        address: '10.0.0.1',
        port: 5004,
        reason: PeerDisconnectedReason.idleTimeout,
      );
      expect(error.toString(), 'PeerDisconnected: Idle timeout');
    });
  });

  group('pattern matching', () {
    test('sealed class enables exhaustive switch', () {
      final SessionError error = MalformedPacket(
        message: 'bad',
        address: '10.0.0.1',
        port: 5004,
        rawBytes: Uint8List(0),
        packetType: PacketType.exchange,
      );

      // Exhaustive switch — if this compiles, the sealed class works.
      final result = switch (error) {
        MalformedPacket() => 'malformed',
        ConnectionFailed() => 'connection',
        ProtocolViolation() => 'violation',
        PeerDisconnected() => 'disconnected',
      };
      expect(result, 'malformed');
    });
  });
}
