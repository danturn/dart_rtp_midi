import 'dart:typed_data';

/// Channel Chapter P — Program Change (3 bytes).
///
/// Wire format (RFC 6295, Figure C.1.1):
/// ```
/// Byte 0: S(1) PROGRAM(7)
/// Byte 1: B(1) BANK-MSB(7)
/// Byte 2: X(1) BANK-LSB(7)
/// ```
class ChannelChapterP {
  /// History trimmed flag.
  final bool s;

  /// 7-bit program number (0–127).
  final int program;

  /// Bank valid flag.
  final bool b;

  /// 7-bit bank MSB (CC #0 value).
  final int bankMsb;

  /// Bank LSB valid flag.
  final bool x;

  /// 7-bit bank LSB (CC #32 value).
  final int bankLsb;

  const ChannelChapterP({
    this.s = false,
    this.program = 0,
    this.b = false,
    this.bankMsb = 0,
    this.x = false,
    this.bankLsb = 0,
  });

  /// Size of the chapter in bytes.
  static const int size = 3;

  /// Encode this chapter to a 3-byte [Uint8List].
  Uint8List encode() {
    return Uint8List.fromList([
      (s ? 0x80 : 0) | (program & 0x7F),
      (b ? 0x80 : 0) | (bankMsb & 0x7F),
      (x ? 0x80 : 0) | (bankLsb & 0x7F),
    ]);
  }

  /// Decode Chapter P from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterP, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) return null;
    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];
    final byte2 = bytes[offset + 2];
    return (
      ChannelChapterP(
        s: (byte0 & 0x80) != 0,
        program: byte0 & 0x7F,
        b: (byte1 & 0x80) != 0,
        bankMsb: byte1 & 0x7F,
        x: (byte2 & 0x80) != 0,
        bankLsb: byte2 & 0x7F,
      ),
      size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterP &&
          s == other.s &&
          program == other.program &&
          b == other.b &&
          bankMsb == other.bankMsb &&
          x == other.x &&
          bankLsb == other.bankLsb;

  @override
  int get hashCode => Object.hash(s, program, b, bankMsb, x, bankLsb);

  @override
  String toString() => 'ChannelChapterP(S=$s, PROGRAM=$program, B=$b, '
      'BANK-MSB=$bankMsb, X=$x, BANK-LSB=$bankLsb)';
}
