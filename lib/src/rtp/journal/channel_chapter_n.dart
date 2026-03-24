import 'dart:typed_data';

/// A single note log entry in Chapter N.
///
/// Wire format (2 bytes):
/// ```
/// Byte 0: S(1) NOTENUM(7)
/// Byte 1: Y(1) VELOCITY(7)
/// ```
class NoteLog {
  /// History trimmed flag for this log.
  final bool s;

  /// 7-bit note number (0–127).
  final int noteNum;

  /// Play/sustain flag.
  final bool y;

  /// 7-bit velocity (0–127).
  final int velocity;

  const NoteLog({
    this.s = false,
    required this.noteNum,
    this.y = false,
    required this.velocity,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteLog &&
          s == other.s &&
          noteNum == other.noteNum &&
          y == other.y &&
          velocity == other.velocity;

  @override
  int get hashCode => Object.hash(s, noteNum, y, velocity);

  @override
  String toString() =>
      'NoteLog(S=$s, NOTENUM=$noteNum, Y=$y, VELOCITY=$velocity)';
}

/// Channel Chapter N — NoteOn/Off (variable length).
///
/// Wire format (RFC 6295, Figure C.5.1):
/// ```
/// Header (2 bytes): B(1) LEN(7) | LOW(4) HIGH(4)
/// Note logs: LEN × 2 bytes, each: S(1) NOTENUM(7) | Y(1) VELOCITY(7)
/// NoteOff bitfield: offbitCount(LOW, HIGH) bytes
/// ```
/// Special cases for offbit count:
/// - LOW=15, HIGH=0 → 0 bytes (no bitfield)
/// - LOW=15, HIGH=1 → 0 bytes (no bitfield)
/// - LOW<=HIGH → HIGH-LOW+1 bytes
/// - LOW>HIGH → 0 bytes
class ChannelChapterN {
  /// NoteOff bitfield present flag.
  final bool b;

  /// Note log entries.
  final List<NoteLog> logs;

  /// 4-bit LOW field (0–15).
  final int low;

  /// 4-bit HIGH field (0–15).
  final int high;

  /// NoteOff bitfield bytes. Length must match [offbitCount].
  final Uint8List? offBits;

  const ChannelChapterN({
    this.b = false,
    required this.logs,
    this.low = 15,
    this.high = 0,
    this.offBits,
  });

  /// Minimum size in bytes (header only, no logs, no offbits).
  static const int headerSize = 2;

  /// Compute the number of offbit bytes from LOW and HIGH.
  static int offbitCount(int low, int high) {
    if (low == 15 && high == 0) return 0;
    if (low == 15 && high == 1) return 0;
    if (low <= high) return high - low + 1;
    return 0;
  }

  /// Total encoded size for this instance.
  int get size => headerSize + logs.length * 2 + offbitCount(low, high);

  /// Encode this chapter to a [Uint8List].
  ///
  /// Special case: 128 logs encoded as LEN=127 + LOW=15, HIGH=0
  /// (RFC 6295 A.6, Wireshark decode_cj_chapter_n).
  Uint8List encode() {
    final offCount = offbitCount(low, high);
    final data = Uint8List(headerSize + logs.length * 2 + offCount);

    // LEN=127 + LOW=15 + HIGH=0 encodes 128 note logs.
    final encodedLen = (logs.length == 128) ? 127 : (logs.length & 0x7F);
    final encodedLow = (logs.length == 128) ? 15 : low;
    final encodedHigh = (logs.length == 128) ? 0 : high;

    data[0] = (b ? 0x80 : 0) | encodedLen;
    data[1] = ((encodedLow & 0x0F) << 4) | (encodedHigh & 0x0F);

    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      data[headerSize + i * 2] = (log.s ? 0x80 : 0) | (log.noteNum & 0x7F);
      data[headerSize + i * 2 + 1] = (log.y ? 0x80 : 0) | (log.velocity & 0x7F);
    }

    if (offCount > 0 && offBits != null) {
      final offStart = headerSize + logs.length * 2;
      for (int i = 0; i < offCount && i < offBits!.length; i++) {
        data[offStart + i] = offBits![i];
      }
    }

    return data;
  }

  /// Decode Chapter N from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterN, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < headerSize) return null;

    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];

    final bFlag = (byte0 & 0x80) != 0;
    var logCount = byte0 & 0x7F;
    final low = (byte1 >> 4) & 0x0F;
    final high = byte1 & 0x0F;

    // Special case: LEN=127, LOW=15, HIGH=0 encodes 128 note logs.
    if (logCount == 127 && low == 15 && high == 0) {
      logCount = 128;
    }

    final offCount = offbitCount(low, high);
    final totalSize = headerSize + logCount * 2 + offCount;

    if (bytes.length - offset < totalSize) return null;

    final logs = <NoteLog>[];
    for (int i = 0; i < logCount; i++) {
      final b0 = bytes[offset + headerSize + i * 2];
      final b1 = bytes[offset + headerSize + i * 2 + 1];
      logs.add(NoteLog(
        s: (b0 & 0x80) != 0,
        noteNum: b0 & 0x7F,
        y: (b1 & 0x80) != 0,
        velocity: b1 & 0x7F,
      ));
    }

    Uint8List? offBits;
    if (offCount > 0) {
      final offStart = offset + headerSize + logCount * 2;
      offBits = bytes.sublist(offStart, offStart + offCount);
    }

    return (
      ChannelChapterN(
        b: bFlag,
        logs: logs,
        low: low,
        high: high,
        offBits: offBits,
      ),
      totalSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterN &&
          b == other.b &&
          low == other.low &&
          high == other.high &&
          _logsEqual(logs, other.logs) &&
          _bytesEqual(offBits, other.offBits);

  static bool _logsEqual(List<NoteLog> a, List<NoteLog> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
  int get hashCode => Object.hash(
        b,
        low,
        high,
        Object.hashAll(logs),
        offBits == null ? null : Object.hashAll(offBits!),
      );

  @override
  String toString() => 'ChannelChapterN(B=$b, LEN=${logs.length}, '
      'LOW=$low, HIGH=$high, offBitLen=${offBits?.length ?? 0})';
}
