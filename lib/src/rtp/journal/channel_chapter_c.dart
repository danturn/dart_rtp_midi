import 'dart:typed_data';

/// A single controller log entry in Chapter C.
///
/// Wire format (2 bytes):
/// ```
/// Byte 0: S(1) NUMBER(7)
/// Byte 1: A(1) VALUE/ALT(7)
/// ```
class ControllerLog {
  /// History trimmed flag for this log.
  final bool s;

  /// 7-bit controller number (0–127).
  final int number;

  /// Alternate interpretation flag.
  final bool a;

  /// 7-bit value (or alternate value when [a] is set).
  final int value;

  const ControllerLog({
    this.s = false,
    required this.number,
    this.a = false,
    required this.value,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControllerLog &&
          s == other.s &&
          number == other.number &&
          a == other.a &&
          value == other.value;

  @override
  int get hashCode => Object.hash(s, number, a, value);

  @override
  String toString() =>
      'ControllerLog(S=$s, NUMBER=$number, A=$a, VALUE=$value)';
}

/// Channel Chapter C — Control Change (variable length).
///
/// Wire format (RFC 6295, Figure C.2.1):
/// ```
/// Byte 0: S(1) LEN(7)     — LEN = log count minus 1
/// Per log (2 bytes): S(1) NUMBER(7) | A(1) VALUE/ALT(7)
/// ```
/// Total: `1 + (LEN+1)*2` bytes.
class ChannelChapterC {
  /// History trimmed flag.
  final bool s;

  /// Controller log entries.
  final List<ControllerLog> logs;

  const ChannelChapterC({this.s = false, required this.logs});

  /// Minimum size in bytes (header + 1 log).
  static const int minSize = 3;

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    final len = logs.length - 1;
    final data = Uint8List(1 + logs.length * 2);

    data[0] = (s ? 0x80 : 0) | (len & 0x7F);

    for (int i = 0; i < logs.length; i++) {
      final log = logs[i];
      data[1 + i * 2] = (log.s ? 0x80 : 0) | (log.number & 0x7F);
      data[1 + i * 2 + 1] = (log.a ? 0x80 : 0) | (log.value & 0x7F);
    }

    return data;
  }

  /// Decode Chapter C from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterC, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < minSize) return null;

    final byte0 = bytes[offset];
    final logCount = (byte0 & 0x7F) + 1;
    final totalSize = 1 + logCount * 2;

    if (bytes.length - offset < totalSize) return null;

    final logs = <ControllerLog>[];
    for (int i = 0; i < logCount; i++) {
      final b0 = bytes[offset + 1 + i * 2];
      final b1 = bytes[offset + 1 + i * 2 + 1];
      logs.add(ControllerLog(
        s: (b0 & 0x80) != 0,
        number: b0 & 0x7F,
        a: (b1 & 0x80) != 0,
        value: b1 & 0x7F,
      ));
    }

    return (
      ChannelChapterC(
        s: (byte0 & 0x80) != 0,
        logs: logs,
      ),
      totalSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterC && s == other.s && _logsEqual(logs, other.logs);

  static bool _logsEqual(List<ControllerLog> a, List<ControllerLog> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(s, Object.hashAll(logs));

  @override
  String toString() => 'ChannelChapterC(S=$s, logs=$logs)';
}
