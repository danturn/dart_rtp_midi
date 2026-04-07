import 'dart:typed_data';

import 'package:rtp_midi/src/api/midi_message.dart';
import 'package:test/test.dart';

void main() {
  group('NoteOn', () {
    test('toBytes encodes correctly', () {
      const msg = NoteOn(channel: 0, note: 60, velocity: 100);
      expect(msg.toBytes(), equals([0x90, 60, 100]));
    });

    test('toBytes encodes channel correctly', () {
      const msg = NoteOn(channel: 9, note: 36, velocity: 127);
      expect(msg.toBytes(), equals([0x99, 36, 127]));
    });

    test('roundtrip', () {
      const original = NoteOn(channel: 5, note: 72, velocity: 64);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('equality', () {
      const a = NoteOn(channel: 0, note: 60, velocity: 100);
      const b = NoteOn(channel: 0, note: 60, velocity: 100);
      const c = NoteOn(channel: 1, note: 60, velocity: 100);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('NoteOff', () {
    test('toBytes encodes correctly', () {
      const msg = NoteOff(channel: 0, note: 60, velocity: 0);
      expect(msg.toBytes(), equals([0x80, 60, 0]));
    });

    test('roundtrip', () {
      const original = NoteOff(channel: 15, note: 127, velocity: 64);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('ControlChange', () {
    test('toBytes encodes correctly', () {
      const msg = ControlChange(channel: 0, controller: 7, value: 100);
      expect(msg.toBytes(), equals([0xB0, 7, 100]));
    });

    test('roundtrip', () {
      const original = ControlChange(channel: 3, controller: 64, value: 127);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('ProgramChange', () {
    test('toBytes encodes correctly', () {
      const msg = ProgramChange(channel: 0, program: 42);
      expect(msg.toBytes(), equals([0xC0, 42]));
    });

    test('roundtrip', () {
      const original = ProgramChange(channel: 9, program: 0);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('PitchBend', () {
    test('toBytes encodes center value', () {
      const msg = PitchBend(channel: 0, value: 8192);
      // 8192 = 0x2000 → LSB = 0x00, MSB = 0x40
      expect(msg.toBytes(), equals([0xE0, 0x00, 0x40]));
    });

    test('toBytes encodes max value', () {
      const msg = PitchBend(channel: 0, value: 16383);
      expect(msg.toBytes(), equals([0xE0, 0x7F, 0x7F]));
    });

    test('toBytes encodes min value', () {
      const msg = PitchBend(channel: 0, value: 0);
      expect(msg.toBytes(), equals([0xE0, 0x00, 0x00]));
    });

    test('roundtrip', () {
      const original = PitchBend(channel: 7, value: 12345);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('ChannelAftertouch', () {
    test('roundtrip', () {
      const original = ChannelAftertouch(channel: 0, pressure: 100);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('PolyAftertouch', () {
    test('roundtrip', () {
      const original = PolyAftertouch(channel: 2, note: 60, pressure: 80);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('System Common', () {
    test('MtcQuarterFrame roundtrip', () {
      const original = MtcQuarterFrame(0x51);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('SongPosition roundtrip', () {
      const original = SongPosition(1000);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('SongPosition zero', () {
      const original = SongPosition(0);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('SongPosition max (16383)', () {
      const original = SongPosition(16383);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('SongSelect roundtrip', () {
      const original = SongSelect(42);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('TuneRequest roundtrip', () {
      const original = TuneRequest();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('System Real-Time', () {
    test('TimingClock roundtrip', () {
      const original = TimingClock();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('Start roundtrip', () {
      const original = Start();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('Continue roundtrip', () {
      const original = Continue();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('Stop roundtrip', () {
      const original = Stop();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('ActiveSensing roundtrip', () {
      const original = ActiveSensing();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('SystemReset roundtrip', () {
      const original = SystemReset();
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });
  });

  group('SysEx', () {
    test('toBytes includes F0/F7 framing', () {
      const msg = SysEx([0x7E, 0x7F, 0x09, 0x01]);
      expect(msg.toBytes(), equals([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]));
    });

    test('roundtrip', () {
      const original = SysEx([0x43, 0x12, 0x00]);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('empty data', () {
      const original = SysEx([]);
      final decoded = MidiMessage.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('equality', () {
      const a = SysEx([1, 2, 3]);
      const b = SysEx([1, 2, 3]);
      const c = SysEx([1, 2, 4]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('fromBytes edge cases', () {
    test('empty bytes returns null', () {
      expect(MidiMessage.fromBytes(Uint8List(0)), isNull);
    });

    test('data byte only returns null', () {
      expect(MidiMessage.fromBytes(Uint8List.fromList([0x60])), isNull);
    });

    test('truncated NoteOn returns null', () {
      expect(MidiMessage.fromBytes(Uint8List.fromList([0x90, 60])), isNull);
    });

    test('truncated ProgramChange returns null', () {
      expect(MidiMessage.fromBytes(Uint8List.fromList([0xC0])), isNull);
    });

    test('unrecognized system status returns null', () {
      // 0xF4 and 0xF5 are undefined
      expect(MidiMessage.fromBytes(Uint8List.fromList([0xF4])), isNull);
      expect(MidiMessage.fromBytes(Uint8List.fromList([0xF5])), isNull);
    });
  });

  group('midiDataLength', () {
    test('channel voice messages', () {
      expect(midiDataLength(0x80), equals(2)); // Note Off
      expect(midiDataLength(0x90), equals(2)); // Note On
      expect(midiDataLength(0xA0), equals(2)); // Poly Aftertouch
      expect(midiDataLength(0xB0), equals(2)); // CC
      expect(midiDataLength(0xC0), equals(1)); // Program Change
      expect(midiDataLength(0xD0), equals(1)); // Channel Aftertouch
      expect(midiDataLength(0xE0), equals(2)); // Pitch Bend
    });

    test('channel messages on various channels', () {
      expect(midiDataLength(0x9F), equals(2)); // Note On ch 15
      expect(midiDataLength(0xC5), equals(1)); // PC ch 5
    });

    test('system common messages', () {
      expect(midiDataLength(0xF0), equals(-1)); // SysEx
      expect(midiDataLength(0xF1), equals(1)); // MTC
      expect(midiDataLength(0xF2), equals(2)); // Song Pos
      expect(midiDataLength(0xF3), equals(1)); // Song Select
      expect(midiDataLength(0xF6), equals(0)); // Tune Request
      expect(midiDataLength(0xF7), equals(0)); // SysEx End
    });

    test('system real-time messages', () {
      expect(midiDataLength(0xF8), equals(0)); // Timing Clock
      expect(midiDataLength(0xFA), equals(0)); // Start
      expect(midiDataLength(0xFB), equals(0)); // Continue
      expect(midiDataLength(0xFC), equals(0)); // Stop
      expect(midiDataLength(0xFE), equals(0)); // Active Sensing
      expect(midiDataLength(0xFF), equals(0)); // System Reset
    });

    test('data bytes return null', () {
      expect(midiDataLength(0x00), isNull);
      expect(midiDataLength(0x7F), isNull);
    });

    test('undefined system common returns null', () {
      expect(midiDataLength(0xF4), isNull);
      expect(midiDataLength(0xF5), isNull);
      expect(midiDataLength(0xF9), isNull);
      expect(midiDataLength(0xFD), isNull);
    });
  });
}
