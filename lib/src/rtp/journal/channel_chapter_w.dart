import 'dart:typed_data';

/// Channel Chapter W — Pitch Wheel (2 bytes).
///
/// Wire format (RFC 6295, Figure C.7.1):
/// ```
/// Byte 0: S(1) FIRST(7)
/// Byte 1: R(1) SECOND(7)
/// ```
class ChannelChapterW {
  /// History trimmed flag.
  final bool s;

  /// 7-bit FIRST value (pitch wheel LSB).
  final int first;

  /// Reserved flag.
  final bool r;

  /// 7-bit SECOND value (pitch wheel MSB).
  final int second;

  const ChannelChapterW({
    this.s = false,
    this.first = 0,
    this.r = false,
    this.second = 0,
  });

  /// Size of the chapter in bytes.
  static const int size = 2;

  /// Encode this chapter to a 2-byte [Uint8List].
  Uint8List encode() {
    return Uint8List.fromList([
      (s ? 0x80 : 0) | (first & 0x7F),
      (r ? 0x80 : 0) | (second & 0x7F),
    ]);
  }

  /// Decode Chapter W from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterW, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) return null;
    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];
    return (
      ChannelChapterW(
        s: (byte0 & 0x80) != 0,
        first: byte0 & 0x7F,
        r: (byte1 & 0x80) != 0,
        second: byte1 & 0x7F,
      ),
      size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterW &&
          s == other.s &&
          first == other.first &&
          r == other.r &&
          second == other.second;

  @override
  int get hashCode => Object.hash(s, first, r, second);

  @override
  String toString() =>
      'ChannelChapterW(S=$s, FIRST=$first, R=$r, SECOND=$second)';
}
