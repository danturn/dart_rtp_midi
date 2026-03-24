import 'package:dart_rtp_midi/src/rtp/journal/midi_state.dart';
import 'package:test/test.dart';

void main() {
  group('ChannelState', () {
    test('empty is empty', () {
      expect(ChannelState.empty.isEmpty, isTrue);
    });

    test('empty has null fields and empty maps', () {
      const s = ChannelState.empty;
      expect(s.program, isNull);
      expect(s.bankMsb, isNull);
      expect(s.bankLsb, isNull);
      expect(s.controllers, isEmpty);
      expect(s.activeNotes, isEmpty);
      expect(s.pitchBendFirst, isNull);
      expect(s.pitchBendSecond, isNull);
      expect(s.channelPressure, isNull);
      expect(s.polyPressure, isEmpty);
    });

    test('copyWith program makes it non-empty', () {
      final s = ChannelState.empty.copyWith(program: () => 42);
      expect(s.isEmpty, isFalse);
      expect(s.program, 42);
    });

    test('copyWith preserves other fields', () {
      final s = ChannelState.empty
          .copyWith(program: () => 1)
          .copyWith(controllers: {7: 100});
      expect(s.program, 1);
      expect(s.controllers, {7: 100});
    });

    test('copyWith can clear a field to null', () {
      final s = ChannelState.empty.copyWith(program: () => 5);
      final cleared = s.copyWith(program: () => null);
      expect(cleared.program, isNull);
    });

    test('equality for identical states', () {
      final a = ChannelState.empty.copyWith(
        activeNotes: {60: 100, 64: 80},
      );
      final b = ChannelState.empty.copyWith(
        activeNotes: {60: 100, 64: 80},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when fields differ', () {
      final a = ChannelState.empty.copyWith(program: () => 1);
      final b = ChannelState.empty.copyWith(program: () => 2);
      expect(a, isNot(equals(b)));
    });

    test('inequality when maps differ', () {
      final a = ChannelState.empty.copyWith(controllers: {1: 10});
      final b = ChannelState.empty.copyWith(controllers: {1: 20});
      expect(a, isNot(equals(b)));
    });

    test('controllers map is unmodifiable after copyWith', () {
      final s = ChannelState.empty.copyWith(controllers: {1: 10});
      expect(() => s.controllers[2] = 20, throwsUnsupportedError);
    });

    test('activeNotes map is unmodifiable after copyWith', () {
      final s = ChannelState.empty.copyWith(activeNotes: {60: 100});
      expect(() => s.activeNotes[61] = 50, throwsUnsupportedError);
    });

    test('polyPressure map is unmodifiable after copyWith', () {
      final s = ChannelState.empty.copyWith(polyPressure: {60: 50});
      expect(() => s.polyPressure[61] = 30, throwsUnsupportedError);
    });

    test('isEmpty with only pitchBend set', () {
      final s = ChannelState.empty.copyWith(
        pitchBendFirst: () => 0,
        pitchBendSecond: () => 64,
      );
      expect(s.isEmpty, isFalse);
    });

    test('isEmpty with only channelPressure set', () {
      final s = ChannelState.empty.copyWith(channelPressure: () => 50);
      expect(s.isEmpty, isFalse);
    });
  });

  group('MidiState', () {
    test('empty has 16 channels', () {
      expect(MidiState.empty.channels.length, 16);
    });

    test('empty is empty', () {
      expect(MidiState.empty.isEmpty, isTrue);
    });

    test('all channels are empty by default', () {
      for (final ch in MidiState.empty.channels) {
        expect(ch.isEmpty, isTrue);
      }
    });

    test('withChannel returns new state with updated channel', () {
      final updated = MidiState.empty.withChannel(
        0,
        ChannelState.empty.copyWith(program: () => 42),
      );
      expect(updated.channels[0].program, 42);
      expect(updated.channels[1].isEmpty, isTrue);
      expect(updated.isEmpty, isFalse);
    });

    test('withChannel does not modify original', () {
      final original = MidiState.empty;
      original.withChannel(3, ChannelState.empty.copyWith(program: () => 10));
      expect(original.channels[3].isEmpty, isTrue);
    });

    test('equality for identical states', () {
      final a = MidiState.empty.withChannel(
        5,
        ChannelState.empty.copyWith(controllers: {7: 100}),
      );
      final b = MidiState.empty.withChannel(
        5,
        ChannelState.empty.copyWith(controllers: {7: 100}),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when different channels modified', () {
      final a = MidiState.empty.withChannel(
        0,
        ChannelState.empty.copyWith(program: () => 1),
      );
      final b = MidiState.empty.withChannel(
        1,
        ChannelState.empty.copyWith(program: () => 1),
      );
      expect(a, isNot(equals(b)));
    });

    test('channels list is unmodifiable', () {
      expect(
        () => (MidiState.empty.channels as List)[0] = ChannelState.empty,
        throwsUnsupportedError,
      );
    });
  });
}
