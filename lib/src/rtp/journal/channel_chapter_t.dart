import 'dart:typed_data';

/// Channel Chapter T — Channel Aftertouch (1 byte).
///
/// Wire format (RFC 6295, Figure C.8.1):
/// ```
/// Byte 0: S(1) PRESSURE(7)
/// ```
class ChannelChapterT {
  /// History trimmed flag.
  final bool s;

  /// 7-bit channel pressure value (0–127).
  final int pressure;

  const ChannelChapterT({this.s = false, this.pressure = 0});

  /// Size of the chapter in bytes.
  static const int size = 1;

  /// Encode this chapter to a 1-byte [Uint8List].
  Uint8List encode() {
    return Uint8List.fromList([(s ? 0x80 : 0) | (pressure & 0x7F)]);
  }

  /// Decode Chapter T from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterT, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) return null;
    final byte0 = bytes[offset];
    return (
      ChannelChapterT(
        s: (byte0 & 0x80) != 0,
        pressure: byte0 & 0x7F,
      ),
      size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterT && s == other.s && pressure == other.pressure;

  @override
  int get hashCode => Object.hash(s, pressure);

  @override
  String toString() => 'ChannelChapterT(S=$s, PRESSURE=$pressure)';
}
