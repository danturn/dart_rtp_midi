import 'dart:typed_data';

/// Chapter F — MTC Tape Position (variable length).
///
/// Wire format (RFC 6295, Figure B.4.1):
/// ```
/// Byte 0: S(1) C(1) P(1) Q(1) D(1) POINT(3)
/// ```
/// If C=1, 4 additional bytes follow (COMPLETE, 32-bit big-endian).
///   - Q=1: packed quarter-frame nibbles MT0–MT7 (Figure B.4.2)
///   - Q=0: HR/MN/SC/FR full frame values (Figure B.4.3)
/// If P=1, 4 additional bytes follow (PARTIAL, 32-bit big-endian).
///   - Always packed quarter-frame nibbles MT0–MT7.
class SystemChapterF {
  /// History trimmed flag.
  final bool s;

  /// COMPLETE field present (adds 4 bytes when true).
  final bool c;

  /// PARTIAL field present (adds 4 bytes when true).
  final bool p;

  /// COMPLETE field format: true = quarter-frame nibbles, false = HR/MN/SC/FR.
  final bool q;

  /// Tape direction: false = forward, true = reverse.
  final bool d;

  /// 3-bit quarter frame index (0–7).
  final int point;

  /// 32-bit COMPLETE field (present when [c] is true).
  final int? complete;

  /// 32-bit PARTIAL field (present when [p] is true).
  final int? partial;

  const SystemChapterF({
    this.s = false,
    this.c = false,
    this.p = false,
    this.q = false,
    this.d = false,
    required this.point,
    this.complete,
    this.partial,
  });

  /// Minimum size in bytes (header only).
  static const int minSize = 1;

  /// Actual size in bytes for this instance.
  int get size => minSize + (c ? 4 : 0) + (p ? 4 : 0);

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    final data = Uint8List(size);

    data[0] = (s ? 0x80 : 0) |
        (c ? 0x40 : 0) |
        (p ? 0x20 : 0) |
        (q ? 0x10 : 0) |
        (d ? 0x08 : 0) |
        (point & 0x07);

    int pos = 1;

    if (c) {
      final comp = complete ?? 0;
      data[pos] = (comp >> 24) & 0xFF;
      data[pos + 1] = (comp >> 16) & 0xFF;
      data[pos + 2] = (comp >> 8) & 0xFF;
      data[pos + 3] = comp & 0xFF;
      pos += 4;
    }

    if (p) {
      final part = partial ?? 0;
      data[pos] = (part >> 24) & 0xFF;
      data[pos + 1] = (part >> 16) & 0xFF;
      data[pos + 2] = (part >> 8) & 0xFF;
      data[pos + 3] = part & 0xFF;
      pos += 4;
    }

    return data;
  }

  /// Decode Chapter F from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (SystemChapterF, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < minSize) return null;

    final byte0 = bytes[offset];
    final cFlag = (byte0 & 0x40) != 0;
    final pFlag = (byte0 & 0x20) != 0;
    final totalSize = minSize + (cFlag ? 4 : 0) + (pFlag ? 4 : 0);

    if (bytes.length - offset < totalSize) return null;

    int pos = offset + 1;

    int? complete;
    if (cFlag) {
      complete = (bytes[pos] << 24) |
          (bytes[pos + 1] << 16) |
          (bytes[pos + 2] << 8) |
          bytes[pos + 3];
      pos += 4;
    }

    int? partial;
    if (pFlag) {
      partial = (bytes[pos] << 24) |
          (bytes[pos + 1] << 16) |
          (bytes[pos + 2] << 8) |
          bytes[pos + 3];
      pos += 4;
    }

    return (
      SystemChapterF(
        s: (byte0 & 0x80) != 0,
        c: cFlag,
        p: pFlag,
        q: (byte0 & 0x10) != 0,
        d: (byte0 & 0x08) != 0,
        point: byte0 & 0x07,
        complete: complete,
        partial: partial,
      ),
      totalSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemChapterF &&
          s == other.s &&
          c == other.c &&
          p == other.p &&
          q == other.q &&
          d == other.d &&
          point == other.point &&
          complete == other.complete &&
          partial == other.partial;

  @override
  int get hashCode => Object.hash(s, c, p, q, d, point, complete, partial);

  @override
  String toString() => 'SystemChapterF(S=$s, C=$c, P=$p, Q=$q, D=$d, '
      'POINT=$point'
      '${c ? ', COMPLETE=0x${complete?.toRadixString(16)}' : ''}'
      '${p ? ', PARTIAL=0x${partial?.toRadixString(16)}' : ''})';
}
