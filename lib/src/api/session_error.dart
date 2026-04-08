import 'dart:math';
import 'dart:typed_data';

/// Packet types for [MalformedPacket] errors.
enum PacketType {
  /// AppleMIDI exchange (invitation, OK, NO, BY) packet.
  exchange,

  /// Clock synchronization (CK0/CK1/CK2) packet.
  clockSync,

  /// RTP-MIDI data packet.
  rtpMidi,

  /// Receiver feedback (RS) packet.
  receiverFeedback,
}

/// Reasons a connection attempt failed.
enum ConnectionFailedReason {
  /// The invitation timed out after exhausting retries.
  timeout,

  /// The remote peer rejected the invitation.
  rejected,

  /// The data-port handshake failed after the control port succeeded.
  dataHandshakeFailed,
}

/// Reasons for a protocol violation.
enum ProtocolViolationReason {
  /// The initiator token in the response did not match the one sent.
  tokenMismatch,

  /// Attempted to send MIDI before the session was ready.
  sendBeforeReady,

  /// Clock sync timed out.
  clockSyncTimeout
}

/// Reasons a peer disconnected.
enum PeerDisconnectedReason {
  /// The remote peer sent a BYE packet.
  byeReceived,

  /// The session timed out due to inactivity.
  idleTimeout,
}

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

  /// Creates a [MalformedPacket] error.
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

  /// Creates a [ConnectionFailed] error.
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

  /// Creates a [ProtocolViolation] error.
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

  /// Creates a [PeerDisconnected] error.
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
