import 'dart:typed_data';

/// A MIDI 1.0 message.
///
/// This is the user-facing model for MIDI messages sent and received over
/// RTP-MIDI sessions. Each subtype provides [toBytes] for encoding and
/// the static [MidiMessage.fromBytes] factory for decoding.
sealed class MidiMessage {
  const MidiMessage();

  /// Encode this message to raw MIDI bytes.
  Uint8List toBytes();

  /// Decode a MIDI message from raw bytes.
  ///
  /// Returns `null` if [bytes] is empty or contains an unrecognized status.
  static MidiMessage? fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final status = bytes[0];

    // Channel voice messages (high nibble 0x8–0xE).
    if (status >= 0x80 && status <= 0xEF) {
      return _decodeChannelMessage(status, bytes);
    }

    // System messages (0xF0–0xFF).
    switch (status) {
      case 0xF0:
        return _decodeSysEx(bytes);
      case 0xF1:
        if (bytes.length < 2) return null;
        return MtcQuarterFrame(bytes[1] & 0x7F);
      case 0xF2:
        if (bytes.length < 3) return null;
        return SongPosition((bytes[2] & 0x7F) << 7 | (bytes[1] & 0x7F));
      case 0xF3:
        if (bytes.length < 2) return null;
        return SongSelect(bytes[1] & 0x7F);
      case 0xF6:
        return const TuneRequest();
      case 0xF8:
        return const TimingClock();
      case 0xFA:
        return const Start();
      case 0xFB:
        return const Continue();
      case 0xFC:
        return const Stop();
      case 0xFE:
        return const ActiveSensing();
      case 0xFF:
        return const SystemReset();
      default:
        return null;
    }
  }

  static MidiMessage? _decodeChannelMessage(int status, Uint8List bytes) {
    final type = status & 0xF0;
    final channel = status & 0x0F;

    switch (type) {
      case 0x80:
        if (bytes.length < 3) return null;
        return NoteOff(
            channel: channel, note: bytes[1] & 0x7F, velocity: bytes[2] & 0x7F);
      case 0x90:
        if (bytes.length < 3) return null;
        return NoteOn(
            channel: channel, note: bytes[1] & 0x7F, velocity: bytes[2] & 0x7F);
      case 0xA0:
        if (bytes.length < 3) return null;
        return PolyAftertouch(
            channel: channel, note: bytes[1] & 0x7F, pressure: bytes[2] & 0x7F);
      case 0xB0:
        if (bytes.length < 3) return null;
        return ControlChange(
            channel: channel,
            controller: bytes[1] & 0x7F,
            value: bytes[2] & 0x7F);
      case 0xC0:
        if (bytes.length < 2) return null;
        return ProgramChange(channel: channel, program: bytes[1] & 0x7F);
      case 0xD0:
        if (bytes.length < 2) return null;
        return ChannelAftertouch(channel: channel, pressure: bytes[1] & 0x7F);
      case 0xE0:
        if (bytes.length < 3) return null;
        final value = (bytes[2] & 0x7F) << 7 | (bytes[1] & 0x7F);
        return PitchBend(channel: channel, value: value);
      default:
        return null;
    }
  }

  static SysEx? _decodeSysEx(Uint8List bytes) {
    // Expect F0 ... F7
    if (bytes.length < 2) return null;
    int end = bytes.length;
    if (bytes[end - 1] == 0xF7) {
      end--;
    }
    // Data is everything between F0 and F7.
    return SysEx(bytes.sublist(1, end));
  }
}

// ---------------------------------------------------------------------------
// Channel Voice Messages
// ---------------------------------------------------------------------------

/// Note On message.
class NoteOn extends MidiMessage {
  final int channel;
  final int note;
  final int velocity;

  const NoteOn({
    required this.channel,
    required this.note,
    required this.velocity,
  });

  @override
  Uint8List toBytes() => Uint8List.fromList([0x90 | channel, note, velocity]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteOn &&
          channel == other.channel &&
          note == other.note &&
          velocity == other.velocity;

  @override
  int get hashCode => Object.hash(channel, note, velocity);

  @override
  String toString() => 'NoteOn(ch: $channel, note: $note, velocity: $velocity)';
}

/// Note Off message.
class NoteOff extends MidiMessage {
  final int channel;
  final int note;
  final int velocity;

  const NoteOff({
    required this.channel,
    required this.note,
    required this.velocity,
  });

  @override
  Uint8List toBytes() => Uint8List.fromList([0x80 | channel, note, velocity]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteOff &&
          channel == other.channel &&
          note == other.note &&
          velocity == other.velocity;

  @override
  int get hashCode => Object.hash(channel, note, velocity);

  @override
  String toString() =>
      'NoteOff(ch: $channel, note: $note, velocity: $velocity)';
}

/// Control Change message.
class ControlChange extends MidiMessage {
  final int channel;
  final int controller;
  final int value;

  const ControlChange({
    required this.channel,
    required this.controller,
    required this.value,
  });

  @override
  Uint8List toBytes() =>
      Uint8List.fromList([0xB0 | channel, controller, value]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlChange &&
          channel == other.channel &&
          controller == other.controller &&
          value == other.value;

  @override
  int get hashCode => Object.hash(channel, controller, value);

  @override
  String toString() =>
      'ControlChange(ch: $channel, cc: $controller, value: $value)';
}

/// Program Change message.
class ProgramChange extends MidiMessage {
  final int channel;
  final int program;

  const ProgramChange({required this.channel, required this.program});

  @override
  Uint8List toBytes() => Uint8List.fromList([0xC0 | channel, program]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgramChange &&
          channel == other.channel &&
          program == other.program;

  @override
  int get hashCode => Object.hash(channel, program);

  @override
  String toString() => 'ProgramChange(ch: $channel, program: $program)';
}

/// Pitch Bend message.
///
/// [value] is a 14-bit value (0–16383) with 8192 as center.
class PitchBend extends MidiMessage {
  final int channel;
  final int value;

  const PitchBend({required this.channel, required this.value});

  @override
  Uint8List toBytes() =>
      Uint8List.fromList([0xE0 | channel, value & 0x7F, (value >> 7) & 0x7F]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PitchBend && channel == other.channel && value == other.value;

  @override
  int get hashCode => Object.hash(channel, value);

  @override
  String toString() => 'PitchBend(ch: $channel, value: $value)';
}

/// Channel Aftertouch (mono pressure).
class ChannelAftertouch extends MidiMessage {
  final int channel;
  final int pressure;

  const ChannelAftertouch({required this.channel, required this.pressure});

  @override
  Uint8List toBytes() => Uint8List.fromList([0xD0 | channel, pressure]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelAftertouch &&
          channel == other.channel &&
          pressure == other.pressure;

  @override
  int get hashCode => Object.hash(channel, pressure);

  @override
  String toString() => 'ChannelAftertouch(ch: $channel, pressure: $pressure)';
}

/// Polyphonic Aftertouch (per-note pressure).
class PolyAftertouch extends MidiMessage {
  final int channel;
  final int note;
  final int pressure;

  const PolyAftertouch({
    required this.channel,
    required this.note,
    required this.pressure,
  });

  @override
  Uint8List toBytes() => Uint8List.fromList([0xA0 | channel, note, pressure]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolyAftertouch &&
          channel == other.channel &&
          note == other.note &&
          pressure == other.pressure;

  @override
  int get hashCode => Object.hash(channel, note, pressure);

  @override
  String toString() =>
      'PolyAftertouch(ch: $channel, note: $note, pressure: $pressure)';
}

// ---------------------------------------------------------------------------
// System Common Messages
// ---------------------------------------------------------------------------

/// MIDI Time Code Quarter Frame.
class MtcQuarterFrame extends MidiMessage {
  final int data;

  const MtcQuarterFrame(this.data);

  @override
  Uint8List toBytes() => Uint8List.fromList([0xF1, data & 0x7F]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MtcQuarterFrame && data == other.data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'MtcQuarterFrame(0x${data.toRadixString(16)})';
}

/// Song Position Pointer (14-bit value in MIDI beats).
class SongPosition extends MidiMessage {
  final int position;

  const SongPosition(this.position);

  @override
  Uint8List toBytes() =>
      Uint8List.fromList([0xF2, position & 0x7F, (position >> 7) & 0x7F]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongPosition && position == other.position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'SongPosition($position)';
}

/// Song Select.
class SongSelect extends MidiMessage {
  final int song;

  const SongSelect(this.song);

  @override
  Uint8List toBytes() => Uint8List.fromList([0xF3, song & 0x7F]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SongSelect && song == other.song;

  @override
  int get hashCode => song.hashCode;

  @override
  String toString() => 'SongSelect($song)';
}

/// Tune Request.
class TuneRequest extends MidiMessage {
  const TuneRequest();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xF6]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TuneRequest;

  @override
  int get hashCode => 0xF6;

  @override
  String toString() => 'TuneRequest()';
}

// ---------------------------------------------------------------------------
// System Real-Time Messages
// ---------------------------------------------------------------------------

/// Timing Clock.
class TimingClock extends MidiMessage {
  const TimingClock();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xF8]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TimingClock;

  @override
  int get hashCode => 0xF8;

  @override
  String toString() => 'TimingClock()';
}

/// Start.
class Start extends MidiMessage {
  const Start();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xFA]);

  @override
  bool operator ==(Object other) => identical(this, other) || other is Start;

  @override
  int get hashCode => 0xFA;

  @override
  String toString() => 'Start()';
}

/// Continue.
class Continue extends MidiMessage {
  const Continue();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xFB]);

  @override
  bool operator ==(Object other) => identical(this, other) || other is Continue;

  @override
  int get hashCode => 0xFB;

  @override
  String toString() => 'Continue()';
}

/// Stop.
class Stop extends MidiMessage {
  const Stop();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xFC]);

  @override
  bool operator ==(Object other) => identical(this, other) || other is Stop;

  @override
  int get hashCode => 0xFC;

  @override
  String toString() => 'Stop()';
}

/// Active Sensing.
class ActiveSensing extends MidiMessage {
  const ActiveSensing();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xFE]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ActiveSensing;

  @override
  int get hashCode => 0xFE;

  @override
  String toString() => 'ActiveSensing()';
}

/// System Reset.
class SystemReset extends MidiMessage {
  const SystemReset();

  @override
  Uint8List toBytes() => Uint8List.fromList([0xFF]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SystemReset;

  @override
  int get hashCode => 0xFF;

  @override
  String toString() => 'SystemReset()';
}

// ---------------------------------------------------------------------------
// System Exclusive
// ---------------------------------------------------------------------------

/// System Exclusive message.
///
/// [data] contains the SysEx payload without the F0/F7 framing bytes.
class SysEx extends MidiMessage {
  final List<int> data;

  const SysEx(this.data);

  @override
  Uint8List toBytes() {
    final result = Uint8List(data.length + 2);
    result[0] = 0xF0;
    result.setRange(1, 1 + data.length, data);
    result[result.length - 1] = 0xF7;
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SysEx && _listEquals(data, other.data);

  @override
  int get hashCode => Object.hashAll(data);

  @override
  String toString() =>
      'SysEx(${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')})';
}

bool _listEquals(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Return the number of data bytes expected after a MIDI status byte.
///
/// Returns -1 for SysEx (variable length) and 0 for single-byte system
/// real-time messages. Returns `null` for unrecognized status bytes.
int? midiDataLength(int status) {
  if (status < 0x80) return null;

  if (status < 0xF0) {
    // Channel messages.
    switch (status & 0xF0) {
      case 0x80:
        return 2; // Note Off
      case 0x90:
        return 2; // Note On
      case 0xA0:
        return 2; // Poly Aftertouch
      case 0xB0:
        return 2; // Control Change
      case 0xC0:
        return 1; // Program Change
      case 0xD0:
        return 1; // Channel Aftertouch
      case 0xE0:
        return 2; // Pitch Bend
      default:
        return null;
    }
  }

  // System messages.
  switch (status) {
    case 0xF0:
      return -1; // SysEx start (variable length)
    case 0xF1:
      return 1; // MTC Quarter Frame
    case 0xF2:
      return 2; // Song Position
    case 0xF3:
      return 1; // Song Select
    case 0xF6:
      return 0; // Tune Request
    case 0xF7:
      return 0; // SysEx End
    case 0xF8:
      return 0; // Timing Clock
    case 0xFA:
      return 0; // Start
    case 0xFB:
      return 0; // Continue
    case 0xFC:
      return 0; // Stop
    case 0xFE:
      return 0; // Active Sensing
    case 0xFF:
      return 0; // System Reset
    default:
      return null;
  }
}
