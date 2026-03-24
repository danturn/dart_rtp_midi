import 'dart:typed_data';

import 'system_chapter_d.dart';
import 'system_chapter_f.dart';
import 'system_chapter_q.dart';
import 'system_chapter_v.dart';
import 'system_chapter_x.dart';

/// System journal — 2-byte header + chapters D, V, Q, F, X.
///
/// Wire format (header):
/// ```
/// Byte 0: S(1) D(1) V(1) Q(1) F(1) X(1) LENGTH[9:8](2)
/// Byte 1: LENGTH[7:0](8)
/// ```
/// LENGTH is the total system journal size including this 2-byte header.
/// Chapters appear in wire order: D, V, Q, F, X.
class SystemJournal {
  /// History trimmed flag.
  final bool s;

  final SystemChapterD? chapterD;
  final SystemChapterV? chapterV;
  final SystemChapterQ? chapterQ;
  final SystemChapterF? chapterF;
  final SystemChapterX? chapterX;

  const SystemJournal({
    this.s = false,
    this.chapterD,
    this.chapterV,
    this.chapterQ,
    this.chapterF,
    this.chapterX,
  });

  /// Minimum size in bytes (header only).
  static const int headerSize = 2;

  /// Encode this system journal to a [Uint8List].
  Uint8List encode() {
    final dBytes = chapterD?.encode();
    final vBytes = chapterV?.encode();
    final qBytes = chapterQ?.encode();
    final fBytes = chapterF?.encode();
    final xBytes = chapterX?.encode();

    final totalLength = headerSize +
        (dBytes?.length ?? 0) +
        (vBytes?.length ?? 0) +
        (qBytes?.length ?? 0) +
        (fBytes?.length ?? 0) +
        (xBytes?.length ?? 0);

    final data = Uint8List(totalLength);

    data[0] = (s ? 0x80 : 0) |
        (chapterD != null ? 0x40 : 0) |
        (chapterV != null ? 0x20 : 0) |
        (chapterQ != null ? 0x10 : 0) |
        (chapterF != null ? 0x08 : 0) |
        (chapterX != null ? 0x04 : 0) |
        ((totalLength >> 8) & 0x03);
    data[1] = totalLength & 0xFF;

    int pos = headerSize;

    if (dBytes != null) {
      data.setRange(pos, pos + dBytes.length, dBytes);
      pos += dBytes.length;
    }
    if (vBytes != null) {
      data.setRange(pos, pos + vBytes.length, vBytes);
      pos += vBytes.length;
    }
    if (qBytes != null) {
      data.setRange(pos, pos + qBytes.length, qBytes);
      pos += qBytes.length;
    }
    if (fBytes != null) {
      data.setRange(pos, pos + fBytes.length, fBytes);
      pos += fBytes.length;
    }
    if (xBytes != null) {
      data.setRange(pos, pos + xBytes.length, xBytes);
      pos += xBytes.length;
    }

    return data;
  }

  /// Decode a system journal from [bytes] at [offset].
  ///
  /// Returns `(journal, bytesConsumed)` or `null` if data is invalid.
  static (SystemJournal, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < headerSize) return null;

    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];

    final sFlag = (byte0 & 0x80) != 0;
    final dPresent = (byte0 & 0x40) != 0;
    final vPresent = (byte0 & 0x20) != 0;
    final qPresent = (byte0 & 0x10) != 0;
    final fPresent = (byte0 & 0x08) != 0;
    final xPresent = (byte0 & 0x04) != 0;
    final totalLength = ((byte0 & 0x03) << 8) | byte1;

    if (bytes.length - offset < totalLength) return null;

    int pos = offset + headerSize;

    SystemChapterD? chapterD;
    if (dPresent) {
      final result = SystemChapterD.decode(bytes, pos);
      if (result == null) return null;
      chapterD = result.$1;
      pos += result.$2;
    }

    SystemChapterV? chapterV;
    if (vPresent) {
      final result = SystemChapterV.decode(bytes, pos);
      if (result == null) return null;
      chapterV = result.$1;
      pos += result.$2;
    }

    SystemChapterQ? chapterQ;
    if (qPresent) {
      final result = SystemChapterQ.decode(bytes, pos);
      if (result == null) return null;
      chapterQ = result.$1;
      pos += result.$2;
    }

    SystemChapterF? chapterF;
    if (fPresent) {
      final result = SystemChapterF.decode(bytes, pos);
      if (result == null) return null;
      chapterF = result.$1;
      pos += result.$2;
    }

    SystemChapterX? chapterX;
    if (xPresent) {
      final xLength = offset + totalLength - pos;
      final result = SystemChapterX.decode(bytes, offset: pos, length: xLength);
      if (result == null) return null;
      chapterX = result.$1;
      pos += result.$2;
    }

    return (
      SystemJournal(
        s: sFlag,
        chapterD: chapterD,
        chapterV: chapterV,
        chapterQ: chapterQ,
        chapterF: chapterF,
        chapterX: chapterX,
      ),
      totalLength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemJournal &&
          s == other.s &&
          chapterD == other.chapterD &&
          chapterV == other.chapterV &&
          chapterQ == other.chapterQ &&
          chapterF == other.chapterF &&
          chapterX == other.chapterX;

  @override
  int get hashCode =>
      Object.hash(s, chapterD, chapterV, chapterQ, chapterF, chapterX);

  @override
  String toString() {
    final parts = <String>['S=$s'];
    if (chapterD != null) parts.add('D=$chapterD');
    if (chapterV != null) parts.add('V');
    if (chapterQ != null) parts.add('Q=$chapterQ');
    if (chapterF != null) parts.add('F=$chapterF');
    if (chapterX != null) parts.add('X=$chapterX');
    return 'SystemJournal(${parts.join(', ')})';
  }
}
