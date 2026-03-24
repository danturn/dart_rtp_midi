import 'dart:typed_data';

/// A single poly aftertouch log entry in Chapter A.
///
/// Wire format (2 bytes):
/// ```
/// Byte 0: S(1) NOTENUM(7)
/// Byte 1: X(1) PRESSURE(7)
/// ```
class PolyAftertouchLog {
  /// History trimmed flag for this log.
  final bool s;

  /// 7-bit note number (0–127).
  final int noteNum;

  /// Reserved/extra flag.
  final bool x;

  /// 7-bit pressure value (0–127).
  final int pressure;

  const PolyAftertouchLog({
    this.s = false,
    required this.noteNum,
    this.x = false,
    required this.pressure,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolyAftertouchLog &&
          s == other.s &&
          noteNum == other.noteNum &&
          x == other.x &&
          pressure == other.pressure;

  @override
  int get hashCode => Object.hash(s, noteNum, x, pressure);

  @override
  String toString() =>
      'PolyAftertouchLog(S=$s, NOTENUM=$noteNum, X=$x, PRESSURE=$pressure)';
}

/// Channel Chapter A — Poly Aftertouch (variable length).
///
/// Wire format (RFC 6295, Figure C.9.1):
/// ```
/// Byte 0: S(1) LEN(7)     — LEN = log count minus 1
/// Per log (2 bytes): S(1) NOTENUM(7) | X(1) PRESSURE(7)
/// ```
/// Total: `1 + (LEN+1)*2` bytes.
class ChannelChapterA {
  /// History trimmed flag.
  final bool s;

  /// Poly aftertouch log entries.
  final List<PolyAftertouchLog> logs;

  const ChannelChapterA({this.s = false, required this.logs});

  /// Minimum size in bytes (header + 1 log).
  static const int minSize = 3;

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    final len = logs.length - 1;
    final data = Uint8List(1 + logs.length * 2);

    data[0] = (s ? 0x80 : 0) | (len & 0x7F);

    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      data[1 + i * 2] = (log.s ? 0x80 : 0) | (log.noteNum & 0x7F);
      data[1 + i * 2 + 1] = (log.x ? 0x80 : 0) | (log.pressure & 0x7F);
    }

    return data;
  }

  /// Decode Chapter A from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterA, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < minSize) return null;

    final byte0 = bytes[offset];
    final logCount = (byte0 & 0x7F) + 1;
    final totalSize = 1 + logCount * 2;

    if (bytes.length - offset < totalSize) return null;

    final logs = <PolyAftertouchLog>[];
    for (int i = 0; i < logCount; i++) {
      final b0 = bytes[offset + 1 + i * 2];
      final b1 = bytes[offset + 1 + i * 2 + 1];
      logs.add(PolyAftertouchLog(
        s: (b0 & 0x80) != 0,
        noteNum: b0 & 0x7F,
        x: (b1 & 0x80) != 0,
        pressure: b1 & 0x7F,
      ));
    }

    return (
      ChannelChapterA(
        s: (byte0 & 0x80) != 0,
        logs: logs,
      ),
      totalSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterA && s == other.s && _logsEqual(logs, other.logs);

  static bool _logsEqual(List<PolyAftertouchLog> a, List<PolyAftertouchLog> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(s, Object.hashAll(logs));

  @override
  String toString() => 'ChannelChapterA(S=$s, logs=$logs)';
}
