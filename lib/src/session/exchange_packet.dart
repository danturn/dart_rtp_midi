import 'dart:convert';
import 'dart:typed_data';

/// The 2-byte signature that begins every RTP-MIDI exchange packet.
const int exchangeSignature = 0xFFFF;

/// The fixed protocol version for Apple's RTP-MIDI session protocol.
const int protocolVersion = 2;

/// Commands used in the RTP-MIDI session exchange protocol.
///
/// Each command is represented by a 2-byte ASCII code in the wire format.
enum ExchangeCommand {
  /// Invitation request (`IN`, 0x494E).
  invitation(0x494E),

  /// Invitation accepted (`OK`, 0x4F4B).
  ok(0x4F4B),

  /// Invitation rejected (`NO`, 0x4E4F).
  no(0x4E4F),

  /// Session teardown (`BY`, 0x4259).
  bye(0x4259);

  const ExchangeCommand(this.code);

  /// The 2-byte command code as it appears on the wire.
  final int code;

  /// Look up a command by its 2-byte wire code.
  ///
  /// Returns `null` if the code does not match any known command.
  static ExchangeCommand? fromCode(int code) {
    for (final cmd in values) {
      if (cmd.code == code) return cmd;
    }
    return null;
  }
}

/// An immutable RTP-MIDI session exchange packet.
///
/// Exchange packets are used for session management: invitation handshake
/// (`IN`/`OK`/`NO`) and session teardown (`BY`). They are sent on both the
/// control and data ports during the session establishment sequence.
///
/// Wire format (big-endian):
/// ```
/// Offset  Size  Field
///   0       2   Signature (0xFFFF)
///   2       2   Command (2-byte ASCII)
///   4       4   Protocol Version (uint32)
///   8       4   Initiator Token (uint32)
///  12       4   Sender SSRC (uint32)
///  16     var   Name (UTF-8, NUL-terminated)
/// ```
class ExchangePacket {
  /// The command type for this packet.
  final ExchangeCommand command;

  /// The protocol version. Always [protocolVersion] (2).
  final int protocolVersion;

  /// An opaque token chosen by the invitation initiator, echoed in replies.
  final int initiatorToken;

  /// The SSRC identifier of the sender.
  final int ssrc;

  /// The human-readable session name, without any NUL terminator.
  final String name;

  const ExchangePacket({
    required this.command,
    this.protocolVersion = 2,
    required this.initiatorToken,
    required this.ssrc,
    required this.name,
  });

  /// Minimum size of an exchange packet (no name, just the NUL terminator).
  static const int minSize = 17; // 2 + 2 + 4 + 4 + 4 + 1(NUL)

  /// Encode this packet to bytes suitable for transmission.
  Uint8List encode() {
    final nameBytes = utf8.encode(name);
    // 2 (sig) + 2 (cmd) + 4 (ver) + 4 (token) + 4 (ssrc) + name + 1 (NUL)
    final length = 16 + nameBytes.length + 1;
    final data = Uint8List(length);
    final view = ByteData.sublistView(data);

    view.setUint16(0, exchangeSignature);
    view.setUint16(2, command.code);
    view.setUint32(4, protocolVersion);
    view.setUint32(8, initiatorToken);
    view.setUint32(12, ssrc);
    data.setRange(16, 16 + nameBytes.length, nameBytes);
    data[16 + nameBytes.length] = 0; // NUL terminator

    return data;
  }

  /// Decode an exchange packet from [bytes].
  ///
  /// Returns `null` if the data is too short, has the wrong signature,
  /// contains an unknown command, or the command bytes are `CK` (which
  /// indicates a [ClockSyncPacket] instead).
  static ExchangePacket? decode(Uint8List bytes) {
    if (bytes.length < minSize) return null;

    final view = ByteData.sublistView(bytes);

    final sig = view.getUint16(0);
    if (sig != exchangeSignature) return null;

    final cmdCode = view.getUint16(2);

    // 'CK' (0x434B) indicates a clock sync packet, not an exchange packet.
    if (cmdCode == 0x434B) return null;

    final command = ExchangeCommand.fromCode(cmdCode);
    if (command == null) return null;

    final version = view.getUint32(4);
    final token = view.getUint32(8);
    final ssrc = view.getUint32(12);

    // Find the NUL terminator for the name field.
    int nameEnd = 16;
    while (nameEnd < bytes.length && bytes[nameEnd] != 0) {
      nameEnd++;
    }
    final name = utf8.decode(bytes.sublist(16, nameEnd));

    return ExchangePacket(
      command: command,
      protocolVersion: version,
      initiatorToken: token,
      ssrc: ssrc,
      name: name,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExchangePacket &&
          command == other.command &&
          protocolVersion == other.protocolVersion &&
          initiatorToken == other.initiatorToken &&
          ssrc == other.ssrc &&
          name == other.name;

  @override
  int get hashCode => Object.hash(
        command,
        protocolVersion,
        initiatorToken,
        ssrc,
        name,
      );

  @override
  String toString() =>
      'ExchangePacket(command: $command, version: $protocolVersion, '
      'token: 0x${initiatorToken.toRadixString(16)}, '
      'ssrc: 0x${ssrc.toRadixString(16)}, name: "$name")';
}

/// An immutable RTP-MIDI clock synchronization packet.
///
/// Clock sync uses a three-way exchange (CK0, CK1, CK2) to estimate the
/// clock offset and network latency between two peers.
///
/// Wire format (big-endian):
/// ```
/// Offset  Size  Field
///   0       2   Signature (0xFFFF)
///   2       2   Command 'CK' (0x434B)
///   4       4   Sender SSRC (uint32)
///   8       1   Count (0, 1, or 2)
///   9       3   Padding (zeros)
///  12       4   Timestamp 1 Hi (uint32)
///  16       4   Timestamp 1 Lo (uint32)
///  20       4   Timestamp 2 Hi (uint32)
///  24       4   Timestamp 2 Lo (uint32)
///  28       4   Timestamp 3 Hi (uint32)
///  32       4   Timestamp 3 Lo (uint32)
/// ```
///
/// Timestamps are 64-bit values representing 100-microsecond ticks.
class ClockSyncPacket {
  /// The SSRC identifier of the sender.
  final int ssrc;

  /// The sync step: 0 (CK0), 1 (CK1), or 2 (CK2).
  final int count;

  /// First timestamp (set by the initiator in CK0, copied in CK1 and CK2).
  final int timestamp1;

  /// Second timestamp (set by the responder in CK1, copied in CK2).
  final int timestamp2;

  /// Third timestamp (set by the initiator in CK2).
  final int timestamp3;

  const ClockSyncPacket({
    required this.ssrc,
    required this.count,
    required this.timestamp1,
    this.timestamp2 = 0,
    this.timestamp3 = 0,
  }) : assert(count >= 0 && count <= 2, 'Count must be 0, 1, or 2');

  /// The 2-byte command code for clock sync packets.
  static const int commandCode = 0x434B; // 'CK'

  /// Fixed size of a clock sync packet in bytes.
  static const int size = 36;

  /// Encode this packet to bytes suitable for transmission.
  Uint8List encode() {
    final data = Uint8List(size);
    final view = ByteData.sublistView(data);

    view.setUint16(0, exchangeSignature);
    view.setUint16(2, commandCode);
    view.setUint32(4, ssrc);
    data[8] = count;
    // Bytes 9, 10, 11 are padding (already zero).
    _setUint64(view, 12, timestamp1);
    _setUint64(view, 20, timestamp2);
    _setUint64(view, 28, timestamp3);

    return data;
  }

  /// Decode a clock sync packet from [bytes].
  ///
  /// Returns `null` if the data is too short, has the wrong signature,
  /// or is not a `CK` command.
  static ClockSyncPacket? decode(Uint8List bytes) {
    if (bytes.length < size) return null;

    final view = ByteData.sublistView(bytes);

    final sig = view.getUint16(0);
    if (sig != exchangeSignature) return null;

    final cmdCode = view.getUint16(2);
    if (cmdCode != commandCode) return null;

    final ssrc = view.getUint32(4);
    final count = bytes[8];
    if (count > 2) return null;

    final t1 = _getUint64(view, 12);
    final t2 = _getUint64(view, 20);
    final t3 = _getUint64(view, 28);

    return ClockSyncPacket(
      ssrc: ssrc,
      count: count,
      timestamp1: t1,
      timestamp2: t2,
      timestamp3: t3,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClockSyncPacket &&
          ssrc == other.ssrc &&
          count == other.count &&
          timestamp1 == other.timestamp1 &&
          timestamp2 == other.timestamp2 &&
          timestamp3 == other.timestamp3;

  @override
  int get hashCode =>
      Object.hash(ssrc, count, timestamp1, timestamp2, timestamp3);

  @override
  String toString() =>
      'ClockSyncPacket(ssrc: 0x${ssrc.toRadixString(16)}, count: $count, '
      't1: $timestamp1, t2: $timestamp2, t3: $timestamp3)';
}

/// Determine whether [bytes] contain a clock sync packet or an exchange packet.
///
/// Returns `true` for clock sync (`CK`), `false` for exchange packets,
/// or `null` if the data is too short or has an invalid signature.
bool? isClockSyncPacket(Uint8List bytes) {
  if (bytes.length < 4) return null;
  final view = ByteData.sublistView(bytes);
  if (view.getUint16(0) != exchangeSignature) return null;
  return view.getUint16(2) == ClockSyncPacket.commandCode;
}

/// Write a 64-bit unsigned integer as two big-endian 32-bit words.
void _setUint64(ByteData view, int offset, int value) {
  view.setUint32(offset, (value >> 32) & 0xFFFFFFFF);
  view.setUint32(offset + 4, value & 0xFFFFFFFF);
}

/// Read a 64-bit unsigned integer from two big-endian 32-bit words.
int _getUint64(ByteData view, int offset) {
  final hi = view.getUint32(offset);
  final lo = view.getUint32(offset + 4);
  return (hi << 32) | lo;
}
