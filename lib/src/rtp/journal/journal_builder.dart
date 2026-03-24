import 'dart:typed_data';

import 'channel_chapter_a.dart';
import 'channel_chapter_c.dart';
import 'channel_chapter_n.dart';
import 'channel_chapter_p.dart';
import 'channel_chapter_t.dart';
import 'channel_chapter_w.dart';
import 'channel_journal.dart';
import 'journal_header.dart';
import 'midi_state.dart';
import 'seq_compare.dart';

/// Pure function: build recovery journal bytes from [state].
///
/// Returns `null` if the state is entirely empty (no journal needed).
/// Uses chapters P, C, W, N, T, A. Skips M and E (deferred).
///
/// When [checkpointSeqNum] is provided, only state entries whose seqnum
/// is after the checkpoint are included (for journal trimming via RS).
Uint8List? buildJournal(MidiState state, int checkpointSeqNum) {
  final journals = <ChannelJournal>[];

  for (int ch = 0; ch < 16; ch++) {
    final channelState = state.channels[ch];
    if (channelState.isEmpty) continue;

    final journal = _buildChannelJournal(ch, channelState, checkpointSeqNum);
    if (journal != null) {
      journals.add(journal);
    }
  }

  if (journals.isEmpty) return null;

  // Encode header + all channel journals.
  final header = JournalHeader(
    singlePacketLoss: true,
    channelJournalsPresent: true,
    totalChannels: journals.length - 1,
    checkpointSeqNum: checkpointSeqNum,
  );

  final headerBytes = header.encode();
  final journalBytesList = journals.map((j) => j.encode()).toList();
  final totalSize = headerBytes.length +
      journalBytesList.fold<int>(0, (s, b) => s + b.length);

  final result = Uint8List(totalSize);
  var offset = 0;
  result.setRange(offset, offset + headerBytes.length, headerBytes);
  offset += headerBytes.length;

  for (final bytes in journalBytesList) {
    result.setRange(offset, offset + bytes.length, bytes);
    offset += bytes.length;
  }

  return result;
}

ChannelJournal? _buildChannelJournal(
    int channel, ChannelState state, int checkpointSeqNum) {
  final chapterP = _buildChapterP(state, checkpointSeqNum);
  final chapterC = _buildChapterC(state, checkpointSeqNum);
  final chapterW = _buildChapterW(state, checkpointSeqNum);
  final chapterN = _buildChapterN(state, checkpointSeqNum);
  final chapterT = _buildChapterT(state, checkpointSeqNum);
  final chapterA = _buildChapterA(state, checkpointSeqNum);

  if (chapterP == null &&
      chapterC == null &&
      chapterW == null &&
      chapterN == null &&
      chapterT == null &&
      chapterA == null) {
    return null;
  }

  return ChannelJournal(
    s: true,
    channel: channel,
    chapterP: chapterP,
    chapterC: chapterC,
    chapterW: chapterW,
    chapterN: chapterN,
    chapterT: chapterT,
    chapterA: chapterA,
  );
}

ChannelChapterP? _buildChapterP(ChannelState state, int checkpoint) {
  if (state.program == null) return null;
  if (!seqAtOrAfter(state.program!.seq, checkpoint)) return null;
  return ChannelChapterP(
    s: true,
    program: state.program!.value,
    b: state.bankMsb != null,
    bankMsb: state.bankMsb?.value ?? 0,
    x: state.bankLsb != null,
    bankLsb: state.bankLsb?.value ?? 0,
  );
}

ChannelChapterC? _buildChapterC(ChannelState state, int checkpoint) {
  final logs = state.controllers.entries
      .where((e) => seqAtOrAfter(e.value.seq, checkpoint))
      .map((e) => ControllerLog(s: true, number: e.key, value: e.value.value))
      .toList();
  if (logs.isEmpty) return null;
  return ChannelChapterC(s: true, logs: logs);
}

ChannelChapterW? _buildChapterW(ChannelState state, int checkpoint) {
  if (state.pitchBendFirst == null) return null;
  if (!seqAtOrAfter(state.pitchBendFirst!.seq, checkpoint)) return null;
  return ChannelChapterW(
    s: true,
    first: state.pitchBendFirst!.value,
    second: state.pitchBendSecond?.value ?? 0,
  );
}

ChannelChapterN? _buildChapterN(ChannelState state, int checkpoint) {
  final activeLogs = state.activeNotes.entries
      .where((e) => seqAtOrAfter(e.value.seq, checkpoint))
      .toList();
  final releasedEntries = state.releasedNotes.entries
      .where((e) => seqAtOrAfter(e.value, checkpoint))
      .toList();

  if (activeLogs.isEmpty && releasedEntries.isEmpty) return null;

  final logs = activeLogs
      .map((e) =>
          NoteLog(s: true, noteNum: e.key, y: true, velocity: e.value.value))
      .toList();

  if (releasedEntries.isEmpty) {
    return ChannelChapterN(logs: logs, low: 15, high: 0);
  }

  // Build offbit bitmap from released notes.
  final releasedNoteNums = releasedEntries.map((e) => e.key);
  final low = releasedNoteNums.reduce((a, b) => a < b ? a : b) ~/ 8;
  final high = releasedNoteNums.reduce((a, b) => a > b ? a : b) ~/ 8;
  final offBits = Uint8List(high - low + 1);
  for (final note in releasedNoteNums) {
    final octet = note ~/ 8 - low;
    final bit = note % 8;
    offBits[octet] |= 0x80 >> bit; // MSB-first
  }

  return ChannelChapterN(
      b: true, logs: logs, low: low, high: high, offBits: offBits);
}

ChannelChapterT? _buildChapterT(ChannelState state, int checkpoint) {
  if (state.channelPressure == null) return null;
  if (!seqAtOrAfter(state.channelPressure!.seq, checkpoint)) return null;
  return ChannelChapterT(s: true, pressure: state.channelPressure!.value);
}

ChannelChapterA? _buildChapterA(ChannelState state, int checkpoint) {
  final logs = state.polyPressure.entries
      .where((e) => seqAtOrAfter(e.value.seq, checkpoint))
      .map((e) =>
          PolyAftertouchLog(s: true, noteNum: e.key, pressure: e.value.value))
      .toList();
  if (logs.isEmpty) return null;
  return ChannelChapterA(s: true, logs: logs);
}
