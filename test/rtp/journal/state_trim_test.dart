import 'package:rtp_midi/src/api/midi_message.dart';
import 'package:rtp_midi/src/rtp/journal/midi_state.dart';
import 'package:rtp_midi/src/rtp/journal/state_trim.dart';
import 'package:rtp_midi/src/rtp/journal/state_update.dart';
import 'package:test/test.dart';

void main() {
  group('trimState', () {
    test('empty state stays empty', () {
      final result = trimState(MidiState.empty, 100);
      expect(result.isEmpty, isTrue);
    });

    test('removes program when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(state, const ProgramChange(channel: 0, program: 42),
          seq: 5);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].program, isNull);
    });

    test('keeps program when seq > confirmed', () {
      var state = MidiState.empty;
      state = updateState(state, const ProgramChange(channel: 0, program: 42),
          seq: 10);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].program?.value, 42);
    });

    test('removes bankMsb when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const ControlChange(channel: 0, controller: 0, value: 5),
          seq: 3);
      final trimmed = trimState(state, 3);
      expect(trimmed.channels[0].bankMsb, isNull);
    });

    test('removes bankLsb when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const ControlChange(channel: 0, controller: 32, value: 3),
          seq: 3);
      final trimmed = trimState(state, 3);
      expect(trimmed.channels[0].bankLsb, isNull);
    });

    test('removes controllers when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const ControlChange(channel: 0, controller: 7, value: 100),
          seq: 5);
      state = updateState(
          state, const ControlChange(channel: 0, controller: 11, value: 80),
          seq: 10);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].controllers.containsKey(7), isFalse);
      expect(trimmed.channels[0].controllers[11]?.value, 80);
    });

    test('removes active notes when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 3);
      state = updateState(
          state, const NoteOn(channel: 0, note: 64, velocity: 80),
          seq: 8);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].activeNotes.containsKey(60), isFalse);
      expect(trimmed.channels[0].activeNotes[64]?.value, 80);
    });

    test('removes released notes when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 2);
      state = updateState(
          state, const NoteOff(channel: 0, note: 60, velocity: 0),
          seq: 3);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].releasedNotes, isEmpty);
    });

    test('keeps released notes when seq > confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 2);
      state = updateState(
          state, const NoteOff(channel: 0, note: 60, velocity: 0),
          seq: 8);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].releasedNotes.containsKey(60), isTrue);
    });

    test('removes pitchBend when seq <= confirmed', () {
      var state = MidiState.empty;
      state =
          updateState(state, const PitchBend(channel: 0, value: 8192), seq: 3);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].pitchBendFirst, isNull);
      expect(trimmed.channels[0].pitchBendSecond, isNull);
    });

    test('keeps pitchBend when seq > confirmed', () {
      var state = MidiState.empty;
      state =
          updateState(state, const PitchBend(channel: 0, value: 8192), seq: 10);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].pitchBendFirst?.value, 0);
      expect(trimmed.channels[0].pitchBendSecond?.value, 64);
    });

    test('removes channelPressure when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const ChannelAftertouch(channel: 0, pressure: 100),
          seq: 4);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].channelPressure, isNull);
    });

    test('removes polyPressure when seq <= confirmed', () {
      var state = MidiState.empty;
      state = updateState(
          state, const PolyAftertouch(channel: 0, note: 60, pressure: 80),
          seq: 3);
      state = updateState(
          state, const PolyAftertouch(channel: 0, note: 64, pressure: 50),
          seq: 10);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].polyPressure.containsKey(60), isFalse);
      expect(trimmed.channels[0].polyPressure[64]?.value, 50);
    });

    test('handles wrapping seqnums correctly', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 65534);
      state = updateState(
          state, const NoteOn(channel: 0, note: 64, velocity: 80),
          seq: 1); // wrapped
      // Confirm up to 65535 — note at 65534 should be trimmed, note at 1 kept
      final trimmed = trimState(state, 65535);
      expect(trimmed.channels[0].activeNotes.containsKey(60), isFalse);
      expect(trimmed.channels[0].activeNotes[64]?.value, 80);
    });

    test('trims across multiple channels', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 3);
      state = updateState(
          state, const NoteOn(channel: 5, note: 48, velocity: 80),
          seq: 8);
      final trimmed = trimState(state, 5);
      expect(trimmed.channels[0].activeNotes, isEmpty);
      expect(trimmed.channels[5].activeNotes[48]?.value, 80);
    });

    test('fully trimmed state is empty', () {
      var state = MidiState.empty;
      state = updateState(
          state, const NoteOn(channel: 0, note: 60, velocity: 100),
          seq: 3);
      state = updateState(
          state, const ControlChange(channel: 0, controller: 7, value: 80),
          seq: 4);
      final trimmed = trimState(state, 10);
      expect(trimmed.channels[0].isEmpty, isTrue);
    });
  });
}
