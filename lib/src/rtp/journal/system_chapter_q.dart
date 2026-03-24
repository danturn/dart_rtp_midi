import 'dart:typed_data';

/// Chapter Q — Sequencer State Commands (variable length).
///
/// Wire format (RFC 6295, Figure B.3.1):
/// ```
/// Byte 0: S(1) N(1) D(1) C(1) T(1) TOP(3)
/// ```
/// If C=1, 2 additional bytes follow (CLOCK, 16-bit big-endian).
/// If T=1, 3 additional bytes follow (TIMETOOLS, 24-bit big-endian).
///
/// Song position = 65536*TOP + CLOCK (19-bit), in MIDI clocks.
/// N = sequencer running (Start/Continue most recent).
/// T = TIMETOOLS present (non-compliant sequencers only; default MUST be 0).
class SystemChapterQ {
  /// History trimmed flag.
  final bool s;

  /// Sequencer running (Start/Continue most recent = true, Stop = false).
  final bool n;

  /// Downbeat played.
  final bool d;

  /// CLOCK field present.
  final bool c;

  /// TIMETOOLS field present.
  final bool t;

  /// 3-bit TOP field (high bits of song position).
  final int top;

  /// 16-bit CLOCK field (low bits of song position). Present when [c] is true.
  final int? clock;

  /// 24-bit TIMETOOLS field (ms offset for non-compliant sequencers).
  /// Present when [t] is true.
  final int? timetools;

  const SystemChapterQ({
    this.s = false,
    this.n = false,
    this.d = false,
    this.c = false,
    this.t = false,
    required this.top,
    this.clock,
    this.timetools,
  });

  /// Minimum size in bytes (header only).
  static const int minSize = 1;

  /// Actual size in bytes for this instance.
  int get size => minSize + (c ? 2 : 0) + (t ? 3 : 0);

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    final data = Uint8List(size);

    data[0] = (s ? 0x80 : 0) |
        (n ? 0x40 : 0) |
        (d ? 0x20 : 0) |
        (c ? 0x10 : 0) |
        (t ? 0x08 : 0) |
        (top & 0x07);

    int pos = 1;

    if (c) {
      final clk = clock ?? 0;
      data[pos] = (clk >> 8) & 0xFF;
      data[pos + 1] = clk & 0xFF;
      pos += 2;
    }

    if (t) {
      final tt = timetools ?? 0;
      data[pos] = (tt >> 16) & 0xFF;
      data[pos + 1] = (tt >> 8) & 0xFF;
      data[pos + 2] = tt & 0xFF;
      pos += 3;
    }

    return data;
  }

  /// Decode Chapter Q from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (SystemChapterQ, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < minSize) return null;

    final byte0 = bytes[offset];
    final cFlag = (byte0 & 0x10) != 0;
    final tFlag = (byte0 & 0x08) != 0;
    final totalSize = minSize + (cFlag ? 2 : 0) + (tFlag ? 3 : 0);

    if (bytes.length - offset < totalSize) return null;

    int pos = offset + 1;

    int? clock;
    if (cFlag) {
      clock = (bytes[pos] << 8) | bytes[pos + 1];
      pos += 2;
    }

    int? timetools;
    if (tFlag) {
      timetools = (bytes[pos] << 16) | (bytes[pos + 1] << 8) | bytes[pos + 2];
      pos += 3;
    }

    return (
      SystemChapterQ(
        s: (byte0 & 0x80) != 0,
        n: (byte0 & 0x40) != 0,
        d: (byte0 & 0x20) != 0,
        c: cFlag,
        t: tFlag,
        top: byte0 & 0x07,
        clock: clock,
        timetools: timetools,
      ),
      totalSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemChapterQ &&
          s == other.s &&
          n == other.n &&
          d == other.d &&
          c == other.c &&
          t == other.t &&
          top == other.top &&
          clock == other.clock &&
          timetools == other.timetools;

  @override
  int get hashCode => Object.hash(s, n, d, c, t, top, clock, timetools);

  @override
  String toString() => 'SystemChapterQ(S=$s, N=$n, D=$d, C=$c, T=$t, TOP=$top'
      '${c ? ', CLOCK=$clock' : ''}${t ? ', TIMETOOLS=$timetools' : ''})';
}
