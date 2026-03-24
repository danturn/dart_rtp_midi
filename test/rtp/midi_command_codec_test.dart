import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:test/test.dart';

void main() {
  group('decodeMidiCommands', () {
    test('single NoteOn without delta time (zFlag=false)', () {
      final bytes = Uint8List.fromList([0x90, 60, 100]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(1));
      expect(commands[0].deltaTime, equals(0));
      expect(commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
    });

    test('single NoteOn with delta time (zFlag=true)', () {
      // Delta time = 10 (single byte), then Note On
      final bytes = Uint8List.fromList([0x0A, 0x90, 60, 100]);
      final commands = decodeMidiCommands(bytes, zFlag: true);
      expect(commands.length, equals(1));
      expect(commands[0].deltaTime, equals(10));
      expect(commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
    });

    test('multiple commands with delta times', () {
      // First: Note On (no delta), Second: Note Off (delta=50)
      final bytes = Uint8List.fromList([
        0x90, 60, 100, // Note On ch0 note60 vel100
        50, // delta time
        0x80, 60, 0, // Note Off ch0 note60 vel0
      ]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(2));
      expect(commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
      expect(commands[0].deltaTime, equals(0));
      expect(commands[1].message,
          equals(const NoteOff(channel: 0, note: 60, velocity: 0)));
      expect(commands[1].deltaTime, equals(50));
    });

    test('running status', () {
      // Note On, then running status Note On (same channel)
      final bytes = Uint8List.fromList([
        0x90, 60, 100, // Note On ch0
        10, // delta time
        72, 80, // Running status: Note On ch0 note72 vel80
      ]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(2));
      expect(commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
      expect(commands[1].message,
          equals(const NoteOn(channel: 0, note: 72, velocity: 80)));
    });

    test('system real-time interleaved (does not cancel running status)', () {
      // Note On, timing clock, then running status Note On
      final bytes = Uint8List.fromList([
        0x90, 60, 100, // Note On ch0
        5, // delta time
        0xF8, // Timing Clock (single byte, does NOT cancel running status)
        10, // delta time
        72, 80, // Running status: Note On ch0
      ]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(3));
      expect(commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
      expect(commands[1].message, equals(const TimingClock()));
      expect(commands[2].message,
          equals(const NoteOn(channel: 0, note: 72, velocity: 80)));
    });

    test('system common cancels running status', () {
      // Note On, then Tune Request (system common, cancels running status),
      // then data bytes without status should fail
      final bytes = Uint8List.fromList([
        0x90, 60, 100, // Note On ch0
        5, // delta time
        0xF6, // Tune Request (cancels running status)
        // No more commands that rely on running status
      ]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(2));
      expect(commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
      expect(commands[1].message, equals(const TuneRequest()));
    });

    test('program change (1 data byte)', () {
      final bytes = Uint8List.fromList([0xC0, 42]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(1));
      expect(commands[0].message,
          equals(const ProgramChange(channel: 0, program: 42)));
    });

    test('SysEx in command list', () {
      final bytes = Uint8List.fromList([
        0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7, // SysEx
      ]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(1));
      expect(
          commands[0].message, equals(const SysEx([0x7E, 0x7F, 0x09, 0x01])));
    });

    test('empty bytes returns empty list', () {
      expect(decodeMidiCommands(Uint8List(0)), isEmpty);
    });

    test('all channel voice message types', () {
      final bytes = Uint8List.fromList([
        0x80, 60, 0, // Note Off
        1,
        0x90, 60, 100, // Note On
        1,
        0xA0, 60, 50, // Poly Aftertouch
        1,
        0xB0, 7, 100, // CC
        1,
        0xC0, 42, // Program Change
        1,
        0xD0, 80, // Channel Aftertouch
        1,
        0xE0, 0x00, 0x40, // Pitch Bend center
      ]);
      final commands = decodeMidiCommands(bytes);
      expect(commands.length, equals(7));
      expect(commands[0].message, isA<NoteOff>());
      expect(commands[1].message, isA<NoteOn>());
      expect(commands[2].message, isA<PolyAftertouch>());
      expect(commands[3].message, isA<ControlChange>());
      expect(commands[4].message, isA<ProgramChange>());
      expect(commands[5].message, isA<ChannelAftertouch>());
      expect(commands[6].message, isA<PitchBend>());
    });
  });

  group('encodeMidiCommands', () {
    test('single command without first delta time', () {
      final commands = [
        const TimestampedMidiCommand(
            0, NoteOn(channel: 0, note: 60, velocity: 100)),
      ];
      final bytes = encodeMidiCommands(commands);
      expect(bytes, equals([0x90, 60, 100]));
    });

    test('single command with first delta time', () {
      final commands = [
        const TimestampedMidiCommand(
            10, NoteOn(channel: 0, note: 60, velocity: 100)),
      ];
      final bytes = encodeMidiCommands(commands, omitFirstDeltaTime: false);
      expect(bytes, equals([0x0A, 0x90, 60, 100]));
    });

    test('multiple commands with delta times', () {
      final commands = [
        const TimestampedMidiCommand(
            0, NoteOn(channel: 0, note: 60, velocity: 100)),
        const TimestampedMidiCommand(
            50, NoteOff(channel: 0, note: 60, velocity: 0)),
      ];
      final bytes = encodeMidiCommands(commands);
      expect(
          bytes,
          equals([
            0x90, 60, 100, // Note On
            50, // delta time
            0x80, 60, 0, // Note Off
          ]));
    });

    test('empty list returns empty bytes', () {
      expect(encodeMidiCommands([]), equals(Uint8List(0)));
    });
  });

  group('encode/decode roundtrip', () {
    test('single NoteOn', () {
      final original = [
        const TimestampedMidiCommand(
            0, NoteOn(channel: 0, note: 60, velocity: 100)),
      ];
      final encoded = encodeMidiCommands(original);
      final decoded = decodeMidiCommands(encoded);
      expect(decoded.length, equals(1));
      expect(decoded[0].message, equals(original[0].message));
    });

    test('multiple messages roundtrip', () {
      final original = [
        const TimestampedMidiCommand(
            0, NoteOn(channel: 0, note: 60, velocity: 100)),
        const TimestampedMidiCommand(
            100, NoteOff(channel: 0, note: 60, velocity: 0)),
        const TimestampedMidiCommand(
            50, ControlChange(channel: 0, controller: 7, value: 64)),
      ];
      final encoded = encodeMidiCommands(original);
      final decoded = decodeMidiCommands(encoded);
      expect(decoded.length, equals(3));
      for (int i = 0; i < original.length; i++) {
        expect(decoded[i].message, equals(original[i].message));
        if (i > 0) {
          expect(decoded[i].deltaTime, equals(original[i].deltaTime));
        }
      }
    });

    test('system messages roundtrip', () {
      final original = [
        const TimestampedMidiCommand(0, TimingClock()),
        const TimestampedMidiCommand(10, Start()),
        const TimestampedMidiCommand(20, Stop()),
      ];
      final encoded = encodeMidiCommands(original);
      final decoded = decodeMidiCommands(encoded);
      expect(decoded.length, equals(3));
      expect(decoded[0].message, equals(const TimingClock()));
      expect(decoded[1].message, equals(const Start()));
      expect(decoded[2].message, equals(const Stop()));
    });
  });

  group('TimestampedMidiCommand', () {
    test('equality', () {
      const a = TimestampedMidiCommand(
          10, NoteOn(channel: 0, note: 60, velocity: 100));
      const b = TimestampedMidiCommand(
          10, NoteOn(channel: 0, note: 60, velocity: 100));
      const c = TimestampedMidiCommand(
          20, NoteOn(channel: 0, note: 60, velocity: 100));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
