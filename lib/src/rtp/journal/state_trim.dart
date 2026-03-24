import 'midi_state.dart';
import 'seq_compare.dart';

/// Pure function: remove entries from [state] whose seqnum is at or before
/// [confirmedSeqNum], returning a trimmed [MidiState].
///
/// This is used after receiving RS (Receiver Feedback) — the remote has
/// confirmed receipt up to [confirmedSeqNum], so those entries no longer
/// need to be included in future journals.
MidiState trimState(MidiState state, int confirmedSeqNum) {
  var result = state;
  for (int ch = 0; ch < 16; ch++) {
    final channelState = state.channels[ch];
    if (channelState.isEmpty) continue;
    final trimmed = _trimChannel(channelState, confirmedSeqNum);
    if (trimmed != channelState) {
      result = result.withChannel(ch, trimmed);
    }
  }
  return result;
}

ChannelState _trimChannel(ChannelState ch, int confirmedSeq) {
  Seq<int>? trimSeq(Seq<int>? field) =>
      field != null && !seqAfter(field.seq, confirmedSeq) ? null : field;

  final program = trimSeq(ch.program);
  final bankMsb = trimSeq(ch.bankMsb);
  final bankLsb = trimSeq(ch.bankLsb);
  final pitchBendFirst = trimSeq(ch.pitchBendFirst);
  final pitchBendSecond = trimSeq(ch.pitchBendSecond);
  final channelPressure = trimSeq(ch.channelPressure);

  final controllers = Map<int, Seq<int>>.of(ch.controllers)
    ..removeWhere((_, v) => !seqAfter(v.seq, confirmedSeq));
  final activeNotes = Map<int, Seq<int>>.of(ch.activeNotes)
    ..removeWhere((_, v) => !seqAfter(v.seq, confirmedSeq));
  final releasedNotes = Map<int, int>.of(ch.releasedNotes)
    ..removeWhere((_, seq) => !seqAfter(seq, confirmedSeq));
  final polyPressure = Map<int, Seq<int>>.of(ch.polyPressure)
    ..removeWhere((_, v) => !seqAfter(v.seq, confirmedSeq));

  return ch.copyWith(
    program: () => program,
    bankMsb: () => bankMsb,
    bankLsb: () => bankLsb,
    controllers: controllers,
    activeNotes: activeNotes,
    releasedNotes: releasedNotes,
    pitchBendFirst: () => pitchBendFirst,
    pitchBendSecond: () => pitchBendSecond,
    channelPressure: () => channelPressure,
    polyPressure: polyPressure,
  );
}
