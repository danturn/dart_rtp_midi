import 'dart:typed_data';

/// Chapter D — Simple System Commands (variable length).
///
/// Wire format (RFC 6295, Figure B.1.1):
/// ```
/// Byte 0: S(1) B(1) G(1) H(1) J(1) K(1) Y(1) Z(1)
/// ```
/// Followed by command logs in flag order:
/// - B: Reset log (1 byte: S|COUNT)
/// - G: Tune Request log (1 byte: S|COUNT)
/// - H: Song Select log (1 byte: S|VALUE)
/// - J: Undefined 0xF4 log (2+ bytes, 10-bit LENGTH in header)
/// - K: Undefined 0xF5 log (2+ bytes, 10-bit LENGTH in header)
/// - Y: Undefined 0xF9 log (1+ bytes, 5-bit LENGTH in header)
/// - Z: Undefined 0xFD log (1+ bytes, 5-bit LENGTH in header)
class SystemChapterD {
  /// History trimmed flag.
  final bool s;

  /// Reset log present.
  final bool b;

  /// Tune Request log present.
  final bool g;

  /// Song Select log present.
  final bool h;

  /// Undefined 0xF4 log present.
  final bool j;

  /// Undefined 0xF5 log present.
  final bool k;

  /// Undefined 0xF9 log present.
  final bool y;

  /// Undefined 0xFD log present.
  final bool z;

  /// Raw bytes of command logs after the 1-byte header.
  final Uint8List? logData;

  const SystemChapterD({
    this.s = false,
    this.b = false,
    this.g = false,
    this.h = false,
    this.j = false,
    this.k = false,
    this.y = false,
    this.z = false,
    this.logData,
  });

  /// Minimum size in bytes (header only).
  static const int minSize = 1;

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    final logBytes = logData ?? Uint8List(0);
    final data = Uint8List(minSize + logBytes.length);

    data[0] = (s ? 0x80 : 0) |
        (b ? 0x40 : 0) |
        (g ? 0x20 : 0) |
        (h ? 0x10 : 0) |
        (j ? 0x08 : 0) |
        (k ? 0x04 : 0) |
        (y ? 0x02 : 0) |
        (z ? 0x01 : 0);

    for (int i = 0; i < logBytes.length; i++) {
      data[minSize + i] = logBytes[i];
    }

    return data;
  }

  /// Decode Chapter D from [bytes] at [offset].
  ///
  /// Self-sizing: parses sub-log headers to determine total length.
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (SystemChapterD, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < minSize) return null;

    final byte0 = bytes[offset];
    final bFlag = (byte0 & 0x40) != 0;
    final gFlag = (byte0 & 0x20) != 0;
    final hFlag = (byte0 & 0x10) != 0;
    final jFlag = (byte0 & 0x08) != 0;
    final kFlag = (byte0 & 0x04) != 0;
    final yFlag = (byte0 & 0x02) != 0;
    final zFlag = (byte0 & 0x01) != 0;

    int logSize = 0;
    int pos = offset + minSize;

    // B (Reset): 1 byte [S|COUNT]
    if (bFlag) {
      if (bytes.length - pos < 1) return null;
      logSize += 1;
      pos += 1;
    }
    // G (Tune Request): 1 byte [S|COUNT]
    if (gFlag) {
      if (bytes.length - pos < 1) return null;
      logSize += 1;
      pos += 1;
    }
    // H (Song Select): 1 byte [S|VALUE]
    if (hFlag) {
      if (bytes.length - pos < 1) return null;
      logSize += 1;
      pos += 1;
    }
    // J (0xF4 undefined syscom): 2-byte header with 10-bit LENGTH
    if (jFlag) {
      final len = _syscomLogLength(bytes, pos);
      if (len == null) return null;
      logSize += len;
      pos += len;
    }
    // K (0xF5 undefined syscom): 2-byte header with 10-bit LENGTH
    if (kFlag) {
      final len = _syscomLogLength(bytes, pos);
      if (len == null) return null;
      logSize += len;
      pos += len;
    }
    // Y (0xF9 undefined sysreal): 1-byte header with 5-bit LENGTH
    if (yFlag) {
      final len = _sysrealLogLength(bytes, pos);
      if (len == null) return null;
      logSize += len;
      pos += len;
    }
    // Z (0xFD undefined sysreal): 1-byte header with 5-bit LENGTH
    if (zFlag) {
      final len = _sysrealLogLength(bytes, pos);
      if (len == null) return null;
      logSize += len;
      pos += len;
    }

    final totalSize = minSize + logSize;

    Uint8List? logData;
    if (logSize > 0) {
      logData = bytes.sublist(offset + minSize, offset + totalSize);
    }

    return (
      SystemChapterD(
        s: (byte0 & 0x80) != 0,
        b: bFlag,
        g: gFlag,
        h: hFlag,
        j: jFlag,
        k: kFlag,
        y: yFlag,
        z: zFlag,
        logData: logData,
      ),
      totalSize,
    );
  }

  /// Parse the length of an undefined System Common log (J, K).
  ///
  /// 2-byte header: S(1)|C(1)|V(1)|L(1)|DSZ(2)|LENGTH(10).
  /// LENGTH includes the 2-byte header.
  static int? _syscomLogLength(Uint8List bytes, int pos) {
    if (bytes.length - pos < 2) return null;
    final length = ((bytes[pos] & 0x03) << 8) | bytes[pos + 1];
    if (length < 2) return null;
    if (bytes.length - pos < length) return null;
    return length;
  }

  /// Parse the length of an undefined System Real-Time log (Y, Z).
  ///
  /// 1-byte header: S(1)|C(1)|L(1)|LENGTH(5).
  /// LENGTH includes the 1-byte header.
  static int? _sysrealLogLength(Uint8List bytes, int pos) {
    if (bytes.length - pos < 1) return null;
    final length = bytes[pos] & 0x1F;
    if (length < 1) return null;
    if (bytes.length - pos < length) return null;
    return length;
  }

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
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemChapterD &&
          s == other.s &&
          b == other.b &&
          g == other.g &&
          h == other.h &&
          j == other.j &&
          k == other.k &&
          y == other.y &&
          z == other.z &&
          _bytesEqual(logData, other.logData);

  @override
  int get hashCode => Object.hash(
        s,
        b,
        g,
        h,
        j,
        k,
        y,
        z,
        logData == null ? null : Object.hashAll(logData!),
      );

  @override
  String toString() => 'SystemChapterD(S=$s, B=$b, G=$g, H=$h, J=$j, K=$k, '
      'Y=$y, Z=$z)';
}
