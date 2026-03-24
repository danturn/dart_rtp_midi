import '../../api/midi_message.dart';
import 'midi_state.dart';

/// Pure function: apply a MIDI message to produce an updated [MidiState].
///
/// Only channel voice messages modify state. System messages are no-ops.
/// [seq] is the RTP sequence number that produced this message (default 0
/// for receiver-side updates where seqnum tagging is not needed).
MidiState updateState(MidiState state, MidiMessage message, {int seq = 0}) {
  return switch (message) {
    NoteOn(:final channel, :final note, :final velocity) =>
      _noteOn(state, channel, note, velocity, seq),
    NoteOff(:final channel, :final note) => _noteOff(state, channel, note, seq),
    ControlChange(:final channel, :final controller, :final value) =>
      _controlChange(state, channel, controller, value, seq),
    ProgramChange(:final channel, :final program) =>
      _programChange(state, channel, program, seq),
    PitchBend(:final channel, :final value) =>
      _pitchBend(state, channel, value, seq),
    ChannelAftertouch(:final channel, :final pressure) =>
      _channelAftertouch(state, channel, pressure, seq),
    PolyAftertouch(:final channel, :final note, :final pressure) =>
      _polyAftertouch(state, channel, note, pressure, seq),
    _ => state, // System messages: no-op
  };
}

MidiState _noteOn(
    MidiState state, int channel, int note, int velocity, int seq) {
  final ch = state.channels[channel];
  if (velocity == 0) {
    // NoteOn with velocity 0 is equivalent to NoteOff.
    return _noteOff(state, channel, note, seq);
  }
  final notes = Map<int, Seq<int>>.of(ch.activeNotes);
  notes[note] = (value: velocity, seq: seq);
  // Remove from released notes if re-triggered.
  if (ch.releasedNotes.containsKey(note)) {
    final released = Map<int, int>.of(ch.releasedNotes)..remove(note);
    return state.withChannel(
        channel, ch.copyWith(activeNotes: notes, releasedNotes: released));
  }
  return state.withChannel(channel, ch.copyWith(activeNotes: notes));
}

MidiState _noteOff(MidiState state, int channel, int note, int seq) {
  final ch = state.channels[channel];
  if (!ch.activeNotes.containsKey(note)) return state;
  final notes = Map<int, Seq<int>>.of(ch.activeNotes)..remove(note);
  final released = Map<int, int>.of(ch.releasedNotes);
  released[note] = seq;
  return state.withChannel(
      channel, ch.copyWith(activeNotes: notes, releasedNotes: released));
}

MidiState _controlChange(
    MidiState state, int channel, int controller, int value, int seq) {
  final ch = state.channels[channel];
  final ccs = Map<int, Seq<int>>.of(ch.controllers);
  ccs[controller] = (value: value, seq: seq);

  // Special-case bank select controllers.
  if (controller == 0) {
    return state.withChannel(
      channel,
      ch.copyWith(controllers: ccs, bankMsb: () => (value: value, seq: seq)),
    );
  }
  if (controller == 32) {
    return state.withChannel(
      channel,
      ch.copyWith(controllers: ccs, bankLsb: () => (value: value, seq: seq)),
    );
  }

  return state.withChannel(channel, ch.copyWith(controllers: ccs));
}

MidiState _programChange(MidiState state, int channel, int program, int seq) {
  final ch = state.channels[channel];
  return state.withChannel(
      channel, ch.copyWith(program: () => (value: program, seq: seq)));
}

MidiState _pitchBend(MidiState state, int channel, int value, int seq) {
  final ch = state.channels[channel];
  final lsb = value & 0x7F;
  final msb = (value >> 7) & 0x7F;
  return state.withChannel(
    channel,
    ch.copyWith(
      pitchBendFirst: () => (value: lsb, seq: seq),
      pitchBendSecond: () => (value: msb, seq: seq),
    ),
  );
}

MidiState _channelAftertouch(
    MidiState state, int channel, int pressure, int seq) {
  final ch = state.channels[channel];
  return state.withChannel(
      channel, ch.copyWith(channelPressure: () => (value: pressure, seq: seq)));
}

MidiState _polyAftertouch(
    MidiState state, int channel, int note, int pressure, int seq) {
  final ch = state.channels[channel];
  final pressures = Map<int, Seq<int>>.of(ch.polyPressure);
  pressures[note] = (value: pressure, seq: seq);
  return state.withChannel(channel, ch.copyWith(polyPressure: pressures));
}
