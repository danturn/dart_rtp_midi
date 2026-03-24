import 'dart:collection';

/// Immutable snapshot of one MIDI channel's state.
///
/// Tracks the latest values for program, bank select, controllers,
/// active notes, pitch bend, channel pressure, and poly pressure.
class ChannelState {
  final int? program;
  final int? bankMsb;
  final int? bankLsb;
  final Map<int, int> controllers;
  final Map<int, int> activeNotes;
  final Set<int> releasedNotes;
  final int? pitchBendFirst;
  final int? pitchBendSecond;
  final int? channelPressure;
  final Map<int, int> polyPressure;

  const ChannelState._({
    this.program,
    this.bankMsb,
    this.bankLsb,
    this.controllers = const {},
    this.activeNotes = const {},
    this.releasedNotes = const {},
    this.pitchBendFirst,
    this.pitchBendSecond,
    this.channelPressure,
    this.polyPressure = const {},
  });

  static const empty = ChannelState._();

  ChannelState copyWith({
    int? Function()? program,
    int? Function()? bankMsb,
    int? Function()? bankLsb,
    Map<int, int>? controllers,
    Map<int, int>? activeNotes,
    Set<int>? releasedNotes,
    int? Function()? pitchBendFirst,
    int? Function()? pitchBendSecond,
    int? Function()? channelPressure,
    Map<int, int>? polyPressure,
  }) {
    return ChannelState._(
      program: program != null ? program() : this.program,
      bankMsb: bankMsb != null ? bankMsb() : this.bankMsb,
      bankLsb: bankLsb != null ? bankLsb() : this.bankLsb,
      controllers: controllers != null
          ? Map.unmodifiable(controllers)
          : this.controllers,
      activeNotes: activeNotes != null
          ? Map.unmodifiable(activeNotes)
          : this.activeNotes,
      releasedNotes: releasedNotes != null
          ? Set.unmodifiable(releasedNotes)
          : this.releasedNotes,
      pitchBendFirst:
          pitchBendFirst != null ? pitchBendFirst() : this.pitchBendFirst,
      pitchBendSecond:
          pitchBendSecond != null ? pitchBendSecond() : this.pitchBendSecond,
      channelPressure:
          channelPressure != null ? channelPressure() : this.channelPressure,
      polyPressure: polyPressure != null
          ? Map.unmodifiable(polyPressure)
          : this.polyPressure,
    );
  }

  bool get isEmpty =>
      program == null &&
      bankMsb == null &&
      bankLsb == null &&
      controllers.isEmpty &&
      activeNotes.isEmpty &&
      releasedNotes.isEmpty &&
      pitchBendFirst == null &&
      pitchBendSecond == null &&
      channelPressure == null &&
      polyPressure.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelState &&
          program == other.program &&
          bankMsb == other.bankMsb &&
          bankLsb == other.bankLsb &&
          _mapEquals(controllers, other.controllers) &&
          _mapEquals(activeNotes, other.activeNotes) &&
          _setEquals(releasedNotes, other.releasedNotes) &&
          pitchBendFirst == other.pitchBendFirst &&
          pitchBendSecond == other.pitchBendSecond &&
          channelPressure == other.channelPressure &&
          _mapEquals(polyPressure, other.polyPressure);

  @override
  int get hashCode => Object.hash(
        program,
        bankMsb,
        bankLsb,
        Object.hashAll(SplayTreeMap<int, int>.from(controllers)
            .entries
            .map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(SplayTreeMap<int, int>.from(activeNotes)
            .entries
            .map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(SplayTreeSet<int>.from(releasedNotes)),
        pitchBendFirst,
        pitchBendSecond,
        channelPressure,
        Object.hashAll(SplayTreeMap<int, int>.from(polyPressure)
            .entries
            .map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() {
    final parts = <String>[];
    if (program != null) parts.add('program=$program');
    if (bankMsb != null) parts.add('bankMsb=$bankMsb');
    if (bankLsb != null) parts.add('bankLsb=$bankLsb');
    if (controllers.isNotEmpty) parts.add('cc=${controllers.length}');
    if (activeNotes.isNotEmpty) parts.add('notes=${activeNotes.length}');
    if (releasedNotes.isNotEmpty) {
      parts.add('released=${releasedNotes.length}');
    }
    if (pitchBendFirst != null) {
      parts.add('pitchBend=$pitchBendFirst/$pitchBendSecond');
    }
    if (channelPressure != null) parts.add('pressure=$channelPressure');
    if (polyPressure.isNotEmpty) {
      parts.add('polyPressure=${polyPressure.length}');
    }
    return 'ChannelState(${parts.join(', ')})';
  }
}

/// Immutable snapshot of all 16 MIDI channels.
class MidiState {
  final List<ChannelState> channels;

  MidiState._({required List<ChannelState> channels})
      : channels = List.unmodifiable(channels);

  static final empty =
      MidiState._(channels: List.filled(16, ChannelState.empty));

  MidiState withChannel(int channel, ChannelState state) {
    final list = List<ChannelState>.of(channels);
    list[channel] = state;
    return MidiState._(channels: list);
  }

  bool get isEmpty => channels.every((ch) => ch.isEmpty);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MidiState && _listEquals(channels, other.channels);

  @override
  int get hashCode => Object.hashAll(channels);

  @override
  String toString() {
    final active = <String>[];
    for (int i = 0; i < channels.length; i++) {
      if (!channels[i].isEmpty) active.add('ch$i');
    }
    return 'MidiState(${active.isEmpty ? 'empty' : active.join(', ')})';
  }
}

bool _setEquals(Set<int> a, Set<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool _mapEquals(Map<int, int> a, Map<int, int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals(List<ChannelState> a, List<ChannelState> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
