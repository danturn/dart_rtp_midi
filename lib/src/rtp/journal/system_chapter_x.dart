import 'dart:typed_data';

/// Chapter X — System Exclusive (1 byte header + variable data).
///
/// Wire format:
/// ```
/// Byte 0: S(1) T(1) C(1) F(1) D(1) L(1) STA(2)
/// ```
/// Followed by variable-length payload data whose structure depends
/// on the T, C, F, D, L flags. The total chapter length is determined
/// by the caller (from the system journal LENGTH field).
class SystemChapterX {
  /// History trimmed flag.
  final bool s;

  /// TCOUNT field present.
  final bool t;

  /// COUNT field present.
  final bool c;

  /// FIRST field present.
  final bool f;

  /// DATA field present.
  final bool d;

  /// LIST field present.
  final bool l;

  /// 2-bit SysEx status (0–3).
  final int sta;

  /// Raw payload data after the 1-byte header.
  final Uint8List? data;

  const SystemChapterX({
    this.s = false,
    this.t = false,
    this.c = false,
    this.f = false,
    this.d = false,
    this.l = false,
    required this.sta,
    this.data,
  });

  /// Minimum size in bytes (header only).
  static const int minSize = 1;

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    final dataBytes = data ?? Uint8List(0);
    final result = Uint8List(minSize + dataBytes.length);

    result[0] = (s ? 0x80 : 0) |
        (t ? 0x40 : 0) |
        (c ? 0x20 : 0) |
        (f ? 0x10 : 0) |
        (d ? 0x08 : 0) |
        (l ? 0x04 : 0) |
        (sta & 0x03);

    for (int i = 0; i < dataBytes.length; i++) {
      result[minSize + i] = dataBytes[i];
    }

    return result;
  }

  /// Decode Chapter X from [bytes] at [offset].
  ///
  /// The [length] parameter specifies the total chapter size (including
  /// the 1-byte header), as determined by the system journal.
  /// Returns `(chapter, bytesConsumed)` or `null` if data is invalid.
  static (SystemChapterX, int)? decode(
    Uint8List bytes, {
    int offset = 0,
    required int length,
  }) {
    if (length < minSize) return null;
    if (bytes.length - offset < length) return null;

    final byte0 = bytes[offset];

    Uint8List? data;
    if (length > minSize) {
      data = bytes.sublist(offset + minSize, offset + length);
    }

    return (
      SystemChapterX(
        s: (byte0 & 0x80) != 0,
        t: (byte0 & 0x40) != 0,
        c: (byte0 & 0x20) != 0,
        f: (byte0 & 0x10) != 0,
        d: (byte0 & 0x08) != 0,
        l: (byte0 & 0x04) != 0,
        sta: byte0 & 0x03,
        data: data,
      ),
      length,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemChapterX &&
          s == other.s &&
          t == other.t &&
          c == other.c &&
          f == other.f &&
          d == other.d &&
          l == other.l &&
          sta == other.sta &&
          _bytesEqual(data, other.data);

  @override
  int get hashCode => Object.hash(
        s,
        t,
        c,
        f,
        d,
        l,
        sta,
        data == null ? null : Object.hashAll(data!),
      );

  static bool _bytesEqual(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'SystemChapterX(S=$s, T=$t, C=$c, F=$f, D=$d, L=$l, '
      'STA=$sta, dataLen=${data?.length ?? 0})';
}
