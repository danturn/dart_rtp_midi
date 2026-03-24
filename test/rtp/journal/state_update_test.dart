import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/journal/midi_state.dart';
import 'package:dart_rtp_midi/src/rtp/journal/state_update.dart';
import 'package:test/test.dart';

/// Extract just the value from a `Seq<int>` map for easy assertion.
Map<int, int> _values(Map<int, Seq<int>> m) =>
    m.map((k, v) => MapEntry(k, v.value));

void main() {
  group('updateState', () {
    group('NoteOn', () {
      test('adds note to activeNotes', () {
        final state = updateState(
          MidiState.empty,
          const NoteOn(channel: 0, note: 60, velocity: 100),
        );
        expect(_values(state.channels[0].activeNotes), {60: 100});
      });

      test('multiple notes on same channel', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 64, velocity: 80));
        expect(_values(state.channels[0].activeNotes), {60: 100, 64: 80});
      });

      test('replaces velocity for same note', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 50));
        expect(_values(state.channels[0].activeNotes), {60: 50});
      });

      test('velocity 0 removes note (equivalent to NoteOff)', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state =
            updateState(state, const NoteOn(channel: 0, note: 60, velocity: 0));
        expect(state.channels[0].activeNotes, isEmpty);
      });

      test('different channels are independent', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 1, note: 60, velocity: 80));
        expect(_values(state.channels[0].activeNotes), {60: 100});
        expect(_values(state.channels[1].activeNotes), {60: 80});
      });
    });

    group('NoteOff', () {
      test('removes active note', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 64));
        expect(state.channels[0].activeNotes, isEmpty);
      });

      test('NoteOff for non-active note is no-op', () {
        final state = updateState(
          MidiState.empty,
          const NoteOff(channel: 0, note: 60, velocity: 0),
        );
        expect(state.channels[0].activeNotes, isEmpty);
        // Should return same instance when no change
        expect(identical(state, MidiState.empty), isTrue);
      });

      test('does not affect other notes', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 64, velocity: 80));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        expect(_values(state.channels[0].activeNotes), {64: 80});
      });

      test('adds note to releasedNotes', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        expect(state.channels[0].releasedNotes.keys, contains(60));
      });

      test('NoteOff for non-active note does not add to releasedNotes', () {
        final state = updateState(
          MidiState.empty,
          const NoteOff(channel: 0, note: 60, velocity: 0),
        );
        expect(state.channels[0].releasedNotes, isEmpty);
      });

      test('NoteOn vel=0 adds to releasedNotes', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state =
            updateState(state, const NoteOn(channel: 0, note: 60, velocity: 0));
        expect(state.channels[0].releasedNotes.keys, contains(60));
        expect(state.channels[0].activeNotes, isEmpty);
      });
    });

    group('releasedNotes tracking', () {
      test('NoteOn removes note from releasedNotes (re-trigger)', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        expect(state.channels[0].releasedNotes.keys, contains(60));
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 80));
        expect(state.channels[0].releasedNotes, isEmpty);
        expect(_values(state.channels[0].activeNotes), {60: 80});
      });

      test('multiple released notes accumulate', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 64, velocity: 80));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        state = updateState(
            state, const NoteOff(channel: 0, note: 64, velocity: 0));
        expect(state.channels[0].releasedNotes.keys, containsAll([60, 64]));
      });

      test('channel with only released notes is not empty', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        expect(state.channels[0].isEmpty, isFalse);
      });
    });

    group('ControlChange', () {
      test('sets controller value', () {
        final state = updateState(
          MidiState.empty,
          const ControlChange(channel: 0, controller: 7, value: 100),
        );
        expect(state.channels[0].controllers[7]?.value, 100);
      });

      test('updates existing controller', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 100));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 50));
        expect(state.channels[0].controllers[7]?.value, 50);
      });

      test('CC#0 also sets bankMsb', () {
        final state = updateState(
          MidiState.empty,
          const ControlChange(channel: 0, controller: 0, value: 5),
        );
        expect(state.channels[0].controllers[0]?.value, 5);
        expect(state.channels[0].bankMsb?.value, 5);
      });

      test('CC#32 also sets bankLsb', () {
        final state = updateState(
          MidiState.empty,
          const ControlChange(channel: 0, controller: 32, value: 3),
        );
        expect(state.channels[0].controllers[32]?.value, 3);
        expect(state.channels[0].bankLsb?.value, 3);
      });

      test('multiple controllers on same channel', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 100));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 11, value: 80));
        expect(_values(state.channels[0].controllers), {7: 100, 11: 80});
      });
    });

    group('ProgramChange', () {
      test('sets program', () {
        final state = updateState(
          MidiState.empty,
          const ProgramChange(channel: 0, program: 42),
        );
        expect(state.channels[0].program?.value, 42);
      });

      test('updates existing program', () {
        var state = MidiState.empty;
        state =
            updateState(state, const ProgramChange(channel: 0, program: 42));
        state =
            updateState(state, const ProgramChange(channel: 0, program: 10));
        expect(state.channels[0].program?.value, 10);
      });
    });

    group('PitchBend', () {
      test('sets pitch bend LSB and MSB', () {
        final state = updateState(
          MidiState.empty,
          const PitchBend(channel: 0, value: 8192), // center
        );
        // 8192 = 0x2000, LSB = 0x00, MSB = 0x40
        expect(state.channels[0].pitchBendFirst?.value, 0);
        expect(state.channels[0].pitchBendSecond?.value, 64);
      });

      test('pitch bend zero', () {
        final state = updateState(
          MidiState.empty,
          const PitchBend(channel: 0, value: 0),
        );
        expect(state.channels[0].pitchBendFirst?.value, 0);
        expect(state.channels[0].pitchBendSecond?.value, 0);
      });

      test('pitch bend max', () {
        final state = updateState(
          MidiState.empty,
          const PitchBend(channel: 0, value: 16383),
        );
        // 16383 = 0x3FFF, LSB = 0x7F, MSB = 0x7F
        expect(state.channels[0].pitchBendFirst?.value, 127);
        expect(state.channels[0].pitchBendSecond?.value, 127);
      });
    });

    group('ChannelAftertouch', () {
      test('sets channel pressure', () {
        final state = updateState(
          MidiState.empty,
          const ChannelAftertouch(channel: 0, pressure: 100),
        );
        expect(state.channels[0].channelPressure?.value, 100);
      });

      test('updates channel pressure', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ChannelAftertouch(channel: 0, pressure: 100));
        state = updateState(
            state, const ChannelAftertouch(channel: 0, pressure: 50));
        expect(state.channels[0].channelPressure?.value, 50);
      });
    });

    group('PolyAftertouch', () {
      test('sets per-note pressure', () {
        final state = updateState(
          MidiState.empty,
          const PolyAftertouch(channel: 0, note: 60, pressure: 80),
        );
        expect(_values(state.channels[0].polyPressure), {60: 80});
      });

      test('multiple notes with different pressures', () {
        var state = MidiState.empty;
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 60, pressure: 80));
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 64, pressure: 50));
        expect(_values(state.channels[0].polyPressure), {60: 80, 64: 50});
      });

      test('updates existing note pressure', () {
        var state = MidiState.empty;
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 60, pressure: 80));
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 60, pressure: 30));
        expect(_values(state.channels[0].polyPressure), {60: 30});
      });
    });

    group('System messages', () {
      test('TimingClock is no-op', () {
        final state = updateState(MidiState.empty, const TimingClock());
        expect(identical(state, MidiState.empty), isTrue);
      });

      test('Start is no-op', () {
        final state = updateState(MidiState.empty, const Start());
        expect(identical(state, MidiState.empty), isTrue);
      });

      test('SystemReset is no-op', () {
        final state = updateState(MidiState.empty, const SystemReset());
        expect(identical(state, MidiState.empty), isTrue);
      });

      test('SysEx is no-op', () {
        final state = updateState(MidiState.empty, const SysEx([0x7E, 0x7F]));
        expect(identical(state, MidiState.empty), isTrue);
      });
    });

    group('cross-channel isolation', () {
      test('updates to channel 5 do not affect channel 0', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 5, note: 60, velocity: 100));
        state = updateState(
            state, const ControlChange(channel: 5, controller: 7, value: 80));
        expect(state.channels[0], ChannelState.empty);
        expect(_values(state.channels[5].activeNotes), {60: 100});
        expect(state.channels[5].controllers[7]?.value, 80);
      });
    });
  });
}
