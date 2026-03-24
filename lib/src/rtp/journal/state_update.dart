import '../../api/midi_message.dart';
import 'midi_state.dart';

/// Pure function: apply a MIDI message to produce an updated [MidiState].
///
/// Only channel voice messages modify state. System messages are no-ops.
MidiState updateState(MidiState state, MidiMessage message) {
  return switch (message) {
    NoteOn(:final channel, :final note, :final velocity) =>
      _noteOn(state, channel, note, velocity),
    NoteOff(:final channel, :final note) => _noteOff(state, channel, note),
    ControlChange(:final channel, :final controller, :final value) =>
      _controlChange(state, channel, controller, value),
    ProgramChange(:final channel, :final program) =>
      _programChange(state, channel, program),
    PitchBend(:final channel, :final value) =>
      _pitchBend(state, channel, value),
    ChannelAftertouch(:final channel, :final pressure) =>
      _channelAftertouch(state, channel, pressure),
    PolyAftertouch(:final channel, :final note, :final pressure) =>
      _polyAftertouch(state, channel, note, pressure),
    _ => state, // System messages: no-op
  };
}

MidiState _noteOn(MidiState state, int channel, int note, int velocity) {
  final ch = state.channels[channel];
  if (velocity == 0) {
    // NoteOn with velocity 0 is equivalent to NoteOff.
    return _noteOff(state, channel, note);
  }
  final notes = Map<int, int>.of(ch.activeNotes);
  notes[note] = velocity;
  // Remove from released notes if re-triggered.
  if (ch.releasedNotes.contains(note)) {
    final released = Set<int>.of(ch.releasedNotes)..remove(note);
    return state.withChannel(
        channel, ch.copyWith(activeNotes: notes, releasedNotes: released));
  }
  return state.withChannel(channel, ch.copyWith(activeNotes: notes));
}

MidiState _noteOff(MidiState state, int channel, int note) {
  final ch = state.channels[channel];
  if (!ch.activeNotes.containsKey(note)) return state;
  final notes = Map<int, int>.of(ch.activeNotes)..remove(note);
  final released = Set<int>.of(ch.releasedNotes)..add(note);
  return state.withChannel(
      channel, ch.copyWith(activeNotes: notes, releasedNotes: released));
}

MidiState _controlChange(
    MidiState state, int channel, int controller, int value) {
  final ch = state.channels[channel];
  final ccs = Map<int, int>.of(ch.controllers);
  ccs[controller] = value;

  // Special-case bank select controllers.
  if (controller == 0) {
    return state.withChannel(
      channel,
      ch.copyWith(controllers: ccs, bankMsb: () => value),
    );
  }
  if (controller == 32) {
    return state.withChannel(
      channel,
      ch.copyWith(controllers: ccs, bankLsb: () => value),
    );
  }

  return state.withChannel(channel, ch.copyWith(controllers: ccs));
}

MidiState _programChange(MidiState state, int channel, int program) {
  final ch = state.channels[channel];
  return state.withChannel(channel, ch.copyWith(program: () => program));
}

MidiState _pitchBend(MidiState state, int channel, int value) {
  final ch = state.channels[channel];
  final lsb = value & 0x7F;
  final msb = (value >> 7) & 0x7F;
  return state.withChannel(
    channel,
    ch.copyWith(pitchBendFirst: () => lsb, pitchBendSecond: () => msb),
  );
}

MidiState _channelAftertouch(MidiState state, int channel, int pressure) {
  final ch = state.channels[channel];
  return state.withChannel(
      channel, ch.copyWith(channelPressure: () => pressure));
}

MidiState _polyAftertouch(
    MidiState state, int channel, int note, int pressure) {
  final ch = state.channels[channel];
  final pressures = Map<int, int>.of(ch.polyPressure);
  pressures[note] = pressure;
  return state.withChannel(channel, ch.copyWith(polyPressure: pressures));
}
