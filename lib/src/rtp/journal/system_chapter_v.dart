import 'dart:typed_data';

/// Chapter V — Active Sensing (1 byte).
///
/// Wire format (RFC 6295, Figure B.2.1):
/// ```
/// Byte 0: S(1) COUNT(7)
/// ```
class SystemChapterV {
  /// History trimmed flag.
  final bool s;

  /// 7-bit active sensing count (modulo 128).
  final int count;

  const SystemChapterV({this.s = false, this.count = 0});

  /// Size of the chapter in bytes.
  static const int size = 1;

  /// Encode this chapter to a 1-byte [Uint8List].
  Uint8List encode() {
    return Uint8List.fromList([(s ? 0x80 : 0) | (count & 0x7F)]);
  }

  /// Decode Chapter V from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (SystemChapterV, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) return null;
    final byte0 = bytes[offset];
    return (
      SystemChapterV(
        s: (byte0 & 0x80) != 0,
        count: byte0 & 0x7F,
      ),
      size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemChapterV && s == other.s && count == other.count;

  @override
  int get hashCode => Object.hash(s, count);

  @override
  String toString() => 'SystemChapterV(S=$s, COUNT=$count)';
}
