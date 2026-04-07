import 'package:rtp_midi/src/rtp/journal/midi_state.dart';
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
      final s = ChannelState.empty.copyWith(program: () => (value: 42, seq: 0));
      expect(s.isEmpty, isFalse);
      expect(s.program?.value, 42);
    });

    test('copyWith preserves other fields', () {
      final s = ChannelState.empty
          .copyWith(program: () => (value: 1, seq: 0))
          .copyWith(controllers: {7: (value: 100, seq: 0)});
      expect(s.program?.value, 1);
      expect(s.controllers[7]?.value, 100);
    });

    test('copyWith can clear a field to null', () {
      final s = ChannelState.empty.copyWith(program: () => (value: 5, seq: 0));
      final cleared = s.copyWith(program: () => null);
      expect(cleared.program, isNull);
    });

    test('equality for identical states', () {
      final a = ChannelState.empty.copyWith(
        activeNotes: {60: (value: 100, seq: 0), 64: (value: 80, seq: 0)},
      );
      final b = ChannelState.empty.copyWith(
        activeNotes: {60: (value: 100, seq: 0), 64: (value: 80, seq: 0)},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when fields differ', () {
      final a = ChannelState.empty.copyWith(program: () => (value: 1, seq: 0));
      final b = ChannelState.empty.copyWith(program: () => (value: 2, seq: 0));
      expect(a, isNot(equals(b)));
    });

    test('inequality when maps differ', () {
      final a =
          ChannelState.empty.copyWith(controllers: {1: (value: 10, seq: 0)});
      final b =
          ChannelState.empty.copyWith(controllers: {1: (value: 20, seq: 0)});
      expect(a, isNot(equals(b)));
    });

    test('controllers map is unmodifiable after copyWith', () {
      final s =
          ChannelState.empty.copyWith(controllers: {1: (value: 10, seq: 0)});
      expect(() => (s.controllers as Map)[2] = (value: 20, seq: 0),
          throwsUnsupportedError);
    });

    test('activeNotes map is unmodifiable after copyWith', () {
      final s =
          ChannelState.empty.copyWith(activeNotes: {60: (value: 100, seq: 0)});
      expect(() => (s.activeNotes as Map)[61] = (value: 50, seq: 0),
          throwsUnsupportedError);
    });

    test('polyPressure map is unmodifiable after copyWith', () {
      final s =
          ChannelState.empty.copyWith(polyPressure: {60: (value: 50, seq: 0)});
      expect(() => (s.polyPressure as Map)[61] = (value: 30, seq: 0),
          throwsUnsupportedError);
    });

    test('isEmpty with only pitchBend set', () {
      final s = ChannelState.empty.copyWith(
        pitchBendFirst: () => (value: 0, seq: 0),
        pitchBendSecond: () => (value: 64, seq: 0),
      );
      expect(s.isEmpty, isFalse);
    });

    test('isEmpty with only channelPressure set', () {
      final s = ChannelState.empty
          .copyWith(channelPressure: () => (value: 50, seq: 0));
      expect(s.isEmpty, isFalse);
    });

    test('releasedNotes map is unmodifiable after copyWith', () {
      final s = ChannelState.empty.copyWith(releasedNotes: {60: 0});
      expect(() => (s.releasedNotes as Map)[61] = 0, throwsUnsupportedError);
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
        ChannelState.empty.copyWith(program: () => (value: 42, seq: 0)),
      );
      expect(updated.channels[0].program?.value, 42);
      expect(updated.channels[1].isEmpty, isTrue);
      expect(updated.isEmpty, isFalse);
    });

    test('withChannel does not modify original', () {
      final original = MidiState.empty;
      original.withChannel(
          3, ChannelState.empty.copyWith(program: () => (value: 10, seq: 0)));
      expect(original.channels[3].isEmpty, isTrue);
    });

    test('equality for identical states', () {
      final a = MidiState.empty.withChannel(
        5,
        ChannelState.empty.copyWith(controllers: {7: (value: 100, seq: 0)}),
      );
      final b = MidiState.empty.withChannel(
        5,
        ChannelState.empty.copyWith(controllers: {7: (value: 100, seq: 0)}),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when different channels modified', () {
      final a = MidiState.empty.withChannel(
        0,
        ChannelState.empty.copyWith(program: () => (value: 1, seq: 0)),
      );
      final b = MidiState.empty.withChannel(
        1,
        ChannelState.empty.copyWith(program: () => (value: 1, seq: 0)),
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
