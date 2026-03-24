import 'dart:typed_data';

/// The 12-byte RTP header for RTP-MIDI packets.
///
/// Wire format (big-endian):
/// ```
/// Byte 0: V(2) P(1) X(1) CC(4)
/// Byte 1: M(1) PT(7)
/// Bytes 2-3: Sequence Number (uint16)
/// Bytes 4-7: Timestamp (uint32)
/// Bytes 8-11: SSRC (uint32)
/// ```
class RtpHeader {
  /// RTP version (always 2).
  final int version;

  /// Padding flag.
  final bool padding;

  /// Extension flag.
  final bool extension;

  /// CSRC count.
  final int csrcCount;

  /// Marker bit. Set to 1 when the MIDI command section contains data.
  final bool marker;

  /// Payload type. 97 for RTP-MIDI per convention.
  final int payloadType;

  /// 16-bit sequence number, wrapping.
  final int sequenceNumber;

  /// 32-bit RTP timestamp.
  final int timestamp;

  /// Synchronization source identifier.
  final int ssrc;

  const RtpHeader({
    this.version = 2,
    this.padding = false,
    this.extension = false,
    this.csrcCount = 0,
    this.marker = true,
    this.payloadType = 97,
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
  });

  /// Size of the fixed RTP header in bytes.
  static const int size = 12;

  /// Encode this header to a 12-byte [Uint8List].
  Uint8List encode() {
    final data = Uint8List(size);
    final view = ByteData.sublistView(data);

    data[0] = (version << 6) |
        (padding ? 0x20 : 0) |
        (extension ? 0x10 : 0) |
        (csrcCount & 0x0F);
    data[1] = (marker ? 0x80 : 0) | (payloadType & 0x7F);
    view.setUint16(2, sequenceNumber & 0xFFFF);
    view.setUint32(4, timestamp & 0xFFFFFFFF);
    view.setUint32(8, ssrc & 0xFFFFFFFF);

    return data;
  }

  /// Decode an RTP header from [bytes].
  ///
  /// Returns `null` if [bytes] is shorter than 12 bytes or the version
  /// is not 2.
  static RtpHeader? decode(Uint8List bytes) {
    if (bytes.length < size) return null;

    final view = ByteData.sublistView(bytes);

    final byte0 = bytes[0];
    final version = (byte0 >> 6) & 0x03;
    if (version != 2) return null;

    final padding = (byte0 & 0x20) != 0;
    final ext = (byte0 & 0x10) != 0;
    final csrcCount = byte0 & 0x0F;

    final byte1 = bytes[1];
    final marker = (byte1 & 0x80) != 0;
    final payloadType = byte1 & 0x7F;

    final sequenceNumber = view.getUint16(2);
    final timestamp = view.getUint32(4);
    final ssrc = view.getUint32(8);

    return RtpHeader(
      version: version,
      padding: padding,
      extension: ext,
      csrcCount: csrcCount,
      marker: marker,
      payloadType: payloadType,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp,
      ssrc: ssrc,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtpHeader &&
          version == other.version &&
          padding == other.padding &&
          extension == other.extension &&
          csrcCount == other.csrcCount &&
          marker == other.marker &&
          payloadType == other.payloadType &&
          sequenceNumber == other.sequenceNumber &&
          timestamp == other.timestamp &&
          ssrc == other.ssrc;

  @override
  int get hashCode => Object.hash(
        version,
        padding,
        extension,
        csrcCount,
        marker,
        payloadType,
        sequenceNumber,
        timestamp,
        ssrc,
      );

  @override
  String toString() => 'RtpHeader(V=$version, M=$marker, PT=$payloadType, '
      'seq=$sequenceNumber, ts=$timestamp, '
      'ssrc=0x${ssrc.toRadixString(16)})';
}
