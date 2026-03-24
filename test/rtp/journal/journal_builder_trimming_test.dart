import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/journal/channel_journal.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_builder.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_header.dart';
import 'package:dart_rtp_midi/src/rtp/journal/midi_state.dart';
import 'package:dart_rtp_midi/src/rtp/journal/state_update.dart';
import 'package:test/test.dart';

void main() {
  group('buildJournal checkpoint filtering', () {
    test('includes entries with seq after checkpoint', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterN, isNotNull);
      expect(ch.chapterN!.logs.length, 1);
    });

    test('includes entries with seq at checkpoint', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 5);
      final bytes = buildJournal(state, 5);
      expect(bytes, isNotNull);
    });

    test('excludes entries with seq before checkpoint', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 3);
      final bytes = buildJournal(state, 5);
      expect(bytes, isNull);
    });

    test('mixed seqs: only newer entries included', () {
      var state = MidiState.empty;
      state = updateState(
          state, const ControlChange(channel: 0, controller: 7, value: 100),
          seq: 3);
      state = updateState(
          state, const ControlChange(channel: 0, controller: 11, value: 80),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterC!.logs.length, 1);
      expect(ch.chapterC!.logs[0].number, 11);
    });

    test('program excluded when before checkpoint', () {
      var state = MidiState.empty;
      state = updateState(state, const ProgramChange(channel: 0, program: 42),
          seq: 3);
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterP, isNull);
      expect(ch.chapterN, isNotNull);
    });

    test('pitchBend excluded when before checkpoint', () {
      var state = MidiState.empty;
      state =
          updateState(state, const PitchBend(channel: 0, value: 8192), seq: 3);
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterW, isNull);
    });

    test('channelPressure excluded when before checkpoint', () {
      var state = MidiState.empty;
      state = updateState(
          state, const ChannelAftertouch(channel: 0, pressure: 100),
          seq: 3);
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterT, isNull);
    });

    test('polyPressure partially filtered', () {
      var state = MidiState.empty;
      state = updateState(
          state, const PolyAftertouch(channel: 0, note: 60, pressure: 80),
          seq: 3);
      state = updateState(
          state, const PolyAftertouch(channel: 0, note: 64, pressure: 50),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterA!.logs.length, 1);
      expect(ch.chapterA!.logs[0].noteNum, 64);
    });

    test('released notes filtered by checkpoint', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 2);
      state = updateState(
          state, const NoteOff(channel: 0, note: 60, velocity: 0),
          seq: 3);
      // Released note at seq 3, checkpoint at 5: excluded
      final bytes = buildJournal(state, 5);
      expect(bytes, isNull);
    });

    test('wrapping: entry at seq 1 included when checkpoint is 65534', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 1);
      final bytes = buildJournal(state, 65534)!;
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.chapterN!.logs.length, 1);
    });

    test('channel excluded entirely when all entries before checkpoint', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 3);
      state = updateState(
          state, const NoteOn(channel: 5, note: 48, velocity: 80),
          seq: 10);
      final bytes = buildJournal(state, 5)!;
      final header = JournalHeader.decode(bytes)!;
      expect(header.totalChannels, 0); // only channel 5
      final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
      expect(ch.channel, 5);
    });
  });
}
