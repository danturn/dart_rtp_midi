import 'dart:typed_data';

import 'channel_chapter_a.dart';
import 'channel_chapter_c.dart';
import 'channel_chapter_e.dart';
import 'channel_chapter_m.dart';
import 'channel_chapter_n.dart';
import 'channel_chapter_p.dart';
import 'channel_chapter_t.dart';
import 'channel_chapter_w.dart';
import 'channel_journal_header.dart';

/// Channel journal — 3-byte header + chapters P, C, M, W, N, E, T, A.
///
/// Wire format: see [ChannelJournalHeader] for the 3-byte header.
/// Chapters appear in wire order: P, C, M, W, N, E, T, A.
/// The header LENGTH field is the total channel journal size including
/// the 3-byte header.
class ChannelJournal {
  /// History trimmed flag.
  final bool s;

  /// 4-bit MIDI channel number (0–15).
  final int channel;

  /// Enhanced encoding flag.
  final bool h;

  final ChannelChapterP? chapterP;
  final ChannelChapterC? chapterC;
  final ChannelChapterM? chapterM;
  final ChannelChapterW? chapterW;
  final ChannelChapterN? chapterN;
  final ChannelChapterE? chapterE;
  final ChannelChapterT? chapterT;
  final ChannelChapterA? chapterA;

  const ChannelJournal({
    this.s = false,
    required this.channel,
    this.h = false,
    this.chapterP,
    this.chapterC,
    this.chapterM,
    this.chapterW,
    this.chapterN,
    this.chapterE,
    this.chapterT,
    this.chapterA,
  });

  /// Minimum size in bytes (header only).
  static const int headerSize = ChannelJournalHeader.size;

  /// Encode this channel journal to a [Uint8List].
  Uint8List encode() {
    final pBytes = chapterP?.encode();
    final cBytes = chapterC?.encode();
    final mBytes = chapterM?.encode();
    final wBytes = chapterW?.encode();
    final nBytes = chapterN?.encode();
    final eBytes = chapterE?.encode();
    final tBytes = chapterT?.encode();
    final aBytes = chapterA?.encode();

    final totalLength = headerSize +
        (pBytes?.length ?? 0) +
        (cBytes?.length ?? 0) +
        (mBytes?.length ?? 0) +
        (wBytes?.length ?? 0) +
        (nBytes?.length ?? 0) +
        (eBytes?.length ?? 0) +
        (tBytes?.length ?? 0) +
        (aBytes?.length ?? 0);

    final header = ChannelJournalHeader(
      s: s,
      channel: channel,
      h: h,
      length: totalLength,
      chapterP: chapterP != null,
      chapterC: chapterC != null,
      chapterM: chapterM != null,
      chapterW: chapterW != null,
      chapterN: chapterN != null,
      chapterE: chapterE != null,
      chapterT: chapterT != null,
      chapterA: chapterA != null,
    );

    final data = Uint8List(totalLength);
    final headerBytes = header.encode();
    data.setRange(0, headerSize, headerBytes);

    int pos = headerSize;

    void writeChapter(Uint8List? bytes) {
      if (bytes != null) {
        data.setRange(pos, pos + bytes.length, bytes);
        pos += bytes.length;
      }
    }

    writeChapter(pBytes);
    writeChapter(cBytes);
    writeChapter(mBytes);
    writeChapter(wBytes);
    writeChapter(nBytes);
    writeChapter(eBytes);
    writeChapter(tBytes);
    writeChapter(aBytes);

    return data;
  }

  /// Decode a channel journal from [bytes] at [offset].
  ///
  /// Returns `(journal, bytesConsumed)` or `null` if data is invalid.
  static (ChannelJournal, int)? decode(Uint8List bytes, [int offset = 0]) {
    final headerResult = ChannelJournalHeader.decode(bytes, offset);
    if (headerResult == null) return null;
    final (header, _) = headerResult;

    if (bytes.length - offset < header.length) return null;

    int pos = offset + headerSize;

    ChannelChapterP? chapterP;
    if (header.chapterP) {
      final result = ChannelChapterP.decode(bytes, pos);
      if (result == null) return null;
      chapterP = result.$1;
      pos += result.$2;
    }

    ChannelChapterC? chapterC;
    if (header.chapterC) {
      final result = ChannelChapterC.decode(bytes, pos);
      if (result == null) return null;
      chapterC = result.$1;
      pos += result.$2;
    }

    ChannelChapterM? chapterM;
    if (header.chapterM) {
      final result = ChannelChapterM.decode(bytes, pos);
      if (result == null) return null;
      chapterM = result.$1;
      pos += result.$2;
    }

    ChannelChapterW? chapterW;
    if (header.chapterW) {
      final result = ChannelChapterW.decode(bytes, pos);
      if (result == null) return null;
      chapterW = result.$1;
      pos += result.$2;
    }

    ChannelChapterN? chapterN;
    if (header.chapterN) {
      final result = ChannelChapterN.decode(bytes, pos);
      if (result == null) return null;
      chapterN = result.$1;
      pos += result.$2;
    }

    ChannelChapterE? chapterE;
    if (header.chapterE) {
      final result = ChannelChapterE.decode(bytes, pos);
      if (result == null) return null;
      chapterE = result.$1;
      pos += result.$2;
    }

    ChannelChapterT? chapterT;
    if (header.chapterT) {
      final result = ChannelChapterT.decode(bytes, pos);
      if (result == null) return null;
      chapterT = result.$1;
      pos += result.$2;
    }

    ChannelChapterA? chapterA;
    if (header.chapterA) {
      final result = ChannelChapterA.decode(bytes, pos);
      if (result == null) return null;
      chapterA = result.$1;
      pos += result.$2;
    }

    return (
      ChannelJournal(
        s: header.s,
        channel: header.channel,
        h: header.h,
        chapterP: chapterP,
        chapterC: chapterC,
        chapterM: chapterM,
        chapterW: chapterW,
        chapterN: chapterN,
        chapterE: chapterE,
        chapterT: chapterT,
        chapterA: chapterA,
      ),
      header.length,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelJournal &&
          s == other.s &&
          channel == other.channel &&
          h == other.h &&
          chapterP == other.chapterP &&
          chapterC == other.chapterC &&
          chapterM == other.chapterM &&
          chapterW == other.chapterW &&
          chapterN == other.chapterN &&
          chapterE == other.chapterE &&
          chapterT == other.chapterT &&
          chapterA == other.chapterA;

  @override
  int get hashCode => Object.hash(
        s,
        channel,
        h,
        chapterP,
        chapterC,
        chapterM,
        chapterW,
        chapterN,
        chapterE,
        chapterT,
        chapterA,
      );

  @override
  String toString() {
    final parts = <String>['S=$s', 'CHAN=$channel'];
    if (chapterP != null) parts.add('P=$chapterP');
    if (chapterC != null) parts.add('C');
    if (chapterM != null) parts.add('M');
    if (chapterW != null) parts.add('W=$chapterW');
    if (chapterN != null) parts.add('N');
    if (chapterE != null) parts.add('E');
    if (chapterT != null) parts.add('T=$chapterT');
    if (chapterA != null) parts.add('A');
    return 'ChannelJournal(${parts.join(', ')})';
  }
}
