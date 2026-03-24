import 'dart:typed_data';

/// Signature for Apple RTP-MIDI session protocol packets.
const int _signature = 0xFFFF;

/// Command code for Receiver Feedback ("RS").
const int rsCommandCode = 0x5253;

/// RS (Receiver Feedback) packet: 12 bytes on the control port.
///
/// Tells the sender "I have received up to seqnum N." This enables
/// journal trimming — the sender can stop including state that the
/// receiver has confirmed.
///
/// Format (big-endian):
/// ```
/// Offset  Size  Field
/// 0-1     2B    Signature: 0xFFFF
/// 2-3     2B    Command: 0x5253 ("RS")
/// 4-7     4B    SSRC (uint32)
/// 8-11    4B    Sequence number (uint32, upper 16 bits = RTP seqnum)
/// ```
class RsPacket {
  final int ssrc;
  final int sequenceNumber;

  const RsPacket({required this.ssrc, required this.sequenceNumber});

  static const int size = 12;

  /// Encode this RS packet into bytes.
  Uint8List encode() {
    final data = Uint8List(size);
    final view = ByteData.sublistView(data);
    view.setUint16(0, _signature);
    view.setUint16(2, rsCommandCode);
    view.setUint32(4, ssrc);
    view.setUint32(8, sequenceNumber << 16);
    return data;
  }

  /// Decode an RS packet from [bytes]. Returns `null` if invalid.
  static RsPacket? decode(Uint8List bytes) {
    if (bytes.length < size) return null;
    final view = ByteData.sublistView(bytes);
    if (view.getUint16(0) != _signature) return null;
    if (view.getUint16(2) != rsCommandCode) return null;
    final ssrc = view.getUint32(4);
    // rtpmidid reads uint16 at offset 8 for the seqnum.
    final seqNum = view.getUint16(8);
    return RsPacket(ssrc: ssrc, sequenceNumber: seqNum);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RsPacket &&
          ssrc == other.ssrc &&
          sequenceNumber == other.sequenceNumber;

  @override
  int get hashCode => Object.hash(ssrc, sequenceNumber);

  @override
  String toString() =>
      'RsPacket(ssrc: 0x${ssrc.toRadixString(16)}, seq: $sequenceNumber)';
}

/// Returns `true` if [bytes] is an RS packet (12 bytes, 0xFFFF 0x5253).
bool isRsPacket(Uint8List bytes) {
  if (bytes.length != RsPacket.size) return false;
  final view = ByteData.sublistView(bytes);
  return view.getUint16(0) == _signature && view.getUint16(2) == rsCommandCode;
}
