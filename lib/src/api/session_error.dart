import 'dart:math';
import 'dart:typed_data';

/// Packet types for [MalformedPacket] errors.
enum PacketType { exchange, clockSync, rtpMidi, receiverFeedback }

/// Reasons a connection attempt failed.
enum ConnectionFailedReason { timeout, rejected, dataHandshakeFailed }

/// Reasons for a protocol violation.
enum ProtocolViolationReason {
  tokenMismatch,
  sendBeforeReady,
  clockSyncTimeout
}

/// Reasons a peer disconnected.
enum PeerDisconnectedReason { byeReceived, idleTimeout }

/// Typed errors emitted by [RtpMidiSession.onError].
///
/// Sealed so consumers can switch exhaustively.
sealed class SessionError {
  /// Plain-English description safe for end users.
  String get message;

  /// First 64 bytes of raw data hex-encoded, for bug reports.
  String get hexDump;

  @override
  String toString();
}

/// A received packet could not be decoded.
class MalformedPacket extends SessionError {
  @override
  final String message;

  /// Address of the sender.
  final String address;

  /// Port the packet arrived on.
  final int port;

  /// The raw bytes that failed to decode.
  final Uint8List rawBytes;

  /// Which packet type was expected.
  final PacketType packetType;

  MalformedPacket({
    required this.message,
    required this.address,
    required this.port,
    required this.rawBytes,
    required this.packetType,
  });

  @override
  String get hexDump => _toHex(rawBytes);

  @override
  String toString() => 'MalformedPacket: $message [$hexDump]';
}

/// A connection attempt failed during the invitation handshake.
class ConnectionFailed extends SessionError {
  @override
  final String message;

  /// Address of the remote peer.
  final String address;

  /// Port of the remote peer.
  final int port;

  /// Why the connection failed.
  final ConnectionFailedReason reason;

  ConnectionFailed({
    required this.message,
    required this.address,
    required this.port,
    required this.reason,
  });

  @override
  String get hexDump => '';

  @override
  String toString() => 'ConnectionFailed: $message';
}

/// The remote peer violated the protocol.
class ProtocolViolation extends SessionError {
  @override
  final String message;

  /// Address of the remote peer.
  final String address;

  /// Port of the remote peer.
  final int port;

  /// Raw bytes, if available.
  final Uint8List? rawBytes;

  /// Why this is a violation.
  final ProtocolViolationReason reason;

  ProtocolViolation({
    required this.message,
    required this.address,
    required this.port,
    this.rawBytes,
    required this.reason,
  });

  @override
  String get hexDump => rawBytes != null ? _toHex(rawBytes!) : '';

  @override
  String toString() {
    final hex = hexDump;
    return hex.isEmpty
        ? 'ProtocolViolation: $message'
        : 'ProtocolViolation: $message [$hex]';
  }
}

/// The remote peer disconnected.
class PeerDisconnected extends SessionError {
  @override
  final String message;

  /// Address of the remote peer.
  final String address;

  /// Port of the remote peer.
  final int port;

  /// Why the peer disconnected.
  final PeerDisconnectedReason reason;

  PeerDisconnected({
    required this.message,
    required this.address,
    required this.port,
    required this.reason,
  });

  @override
  String get hexDump => '';

  @override
  String toString() => 'PeerDisconnected: $message';
}

/// Hex-encode the first 64 bytes of [bytes].
String _toHex(Uint8List bytes) {
  final len = min(bytes.length, 64);
  final buf = StringBuffer();
  for (var i = 0; i < len; i++) {
    buf.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}
