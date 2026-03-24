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

/// Pure function: build recovery journal bytes from [state].
///
/// Returns `null` if the state is entirely empty (no journal needed).
/// Uses chapters P, C, W, N, T, A. Skips M and E (deferred).
Uint8List? buildJournal(MidiState state, int checkpointSeqNum) {
  final journals = <ChannelJournal>[];

  for (int ch = 0; ch < 16; ch++) {
    final channelState = state.channels[ch];
    if (channelState.isEmpty) continue;

    final journal = _buildChannelJournal(ch, channelState);
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

ChannelJournal? _buildChannelJournal(int channel, ChannelState state) {
  final chapterP = _buildChapterP(state);
  final chapterC = _buildChapterC(state);
  final chapterW = _buildChapterW(state);
  final chapterN = _buildChapterN(state);
  final chapterT = _buildChapterT(state);
  final chapterA = _buildChapterA(state);

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

ChannelChapterP? _buildChapterP(ChannelState state) {
  if (state.program == null) return null;
  return ChannelChapterP(
    s: true,
    program: state.program!,
    b: state.bankMsb != null,
    bankMsb: state.bankMsb ?? 0,
    x: state.bankLsb != null,
    bankLsb: state.bankLsb ?? 0,
  );
}

ChannelChapterC? _buildChapterC(ChannelState state) {
  if (state.controllers.isEmpty) return null;
  final logs = state.controllers.entries
      .map((e) => ControllerLog(s: true, number: e.key, value: e.value))
      .toList();
  return ChannelChapterC(s: true, logs: logs);
}

ChannelChapterW? _buildChapterW(ChannelState state) {
  if (state.pitchBendFirst == null) return null;
  return ChannelChapterW(
    s: true,
    first: state.pitchBendFirst!,
    second: state.pitchBendSecond ?? 0,
  );
}

ChannelChapterN? _buildChapterN(ChannelState state) {
  if (state.activeNotes.isEmpty && state.releasedNotes.isEmpty) return null;
  final logs = state.activeNotes.entries
      .map((e) => NoteLog(s: true, noteNum: e.key, y: true, velocity: e.value))
      .toList();

  if (state.releasedNotes.isEmpty) {
    return ChannelChapterN(logs: logs, low: 15, high: 0);
  }

  // Build offbit bitmap from released notes.
  final low = state.releasedNotes.reduce((a, b) => a < b ? a : b) ~/ 8;
  final high = state.releasedNotes.reduce((a, b) => a > b ? a : b) ~/ 8;
  final offBits = Uint8List(high - low + 1);
  for (final note in state.releasedNotes) {
    final octet = note ~/ 8 - low;
    final bit = note % 8;
    offBits[octet] |= 0x80 >> bit; // MSB-first
  }

  return ChannelChapterN(
      b: true, logs: logs, low: low, high: high, offBits: offBits);
}

ChannelChapterT? _buildChapterT(ChannelState state) {
  if (state.channelPressure == null) return null;
  return ChannelChapterT(s: true, pressure: state.channelPressure!);
}

ChannelChapterA? _buildChapterA(ChannelState state) {
  if (state.polyPressure.isEmpty) return null;
  final logs = state.polyPressure.entries
      .map((e) => PolyAftertouchLog(s: true, noteNum: e.key, pressure: e.value))
      .toList();
  return ChannelChapterA(s: true, logs: logs);
}
