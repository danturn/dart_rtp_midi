import 'dart:typed_data';

/// A single note command extras log entry in Chapter E.
///
/// Wire format (2 bytes):
/// ```
/// Byte 0: S(1) NOTENUM(7)
/// Byte 1: V(1) COUNT/VEL(7)
/// ```
class NoteExtraLog {
  /// History trimmed flag for this log.
  final bool s;

  /// 7-bit note number (0–127).
  final int noteNum;

  /// Velocity interpretation flag.
  final bool v;

  /// 7-bit count or velocity value.
  final int countVel;

  const NoteExtraLog({
    this.s = false,
    required this.noteNum,
    this.v = false,
    required this.countVel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteExtraLog &&
          s == other.s &&
          noteNum == other.noteNum &&
          v == other.v &&
          countVel == other.countVel;

  @override
  int get hashCode => Object.hash(s, noteNum, v, countVel);

  @override
  String toString() =>
      'NoteExtraLog(S=$s, NOTENUM=$noteNum, V=$v, COUNT/VEL=$countVel)';
}

/// Channel Chapter E — Note Command Extras (variable length).
///
/// Wire format (RFC 6295, Figure C.6.1):
/// ```
/// Byte 0: S(1) LEN(7)     — LEN = log count minus 1
/// Per log (2 bytes): S(1) NOTENUM(7) | V(1) COUNT/VEL(7)
/// ```
/// Total: `1 + (LEN+1)*2` bytes.
class ChannelChapterE {
  /// History trimmed flag.
  final bool s;

  /// Note command extras log entries.
  final List<NoteExtraLog> logs;

  const ChannelChapterE({this.s = false, required this.logs});

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
      data[1 + i * 2 + 1] = (log.v ? 0x80 : 0) | (log.countVel & 0x7F);
    }

    return data;
  }

  /// Decode Chapter E from [bytes] at [offset].
  ///
  /// Returns `(chapter, bytesConsumed)` or `null` if data is truncated.
  static (ChannelChapterE, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < minSize) return null;

    final byte0 = bytes[offset];
    final logCount = (byte0 & 0x7F) + 1;
    final totalSize = 1 + logCount * 2;

    if (bytes.length - offset < totalSize) return null;

    final logs = <NoteExtraLog>[];
    for (int i = 0; i < logCount; i++) {
      final b0 = bytes[offset + 1 + i * 2];
      final b1 = bytes[offset + 1 + i * 2 + 1];
      logs.add(NoteExtraLog(
        s: (b0 & 0x80) != 0,
        noteNum: b0 & 0x7F,
        v: (b1 & 0x80) != 0,
        countVel: b1 & 0x7F,
      ));
    }

    return (
      ChannelChapterE(
        s: (byte0 & 0x80) != 0,
        logs: logs,
      ),
      totalSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterE && s == other.s && _logsEqual(logs, other.logs);

  static bool _logsEqual(List<NoteExtraLog> a, List<NoteExtraLog> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(s, Object.hashAll(logs));

  @override
  String toString() => 'ChannelChapterE(S=$s, logs=$logs)';
}
