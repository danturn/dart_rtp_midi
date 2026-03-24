import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/sysex_reassembly.dart';
import 'package:test/test.dart';

void main() {
  group('SysExReassembler', () {
    late SysExReassembler reassembler;

    setUp(() {
      reassembler = SysExReassembler();
    });

    test('complete SysEx in one packet', () {
      final data = Uint8List.fromList([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]);
      final result = reassembler.process(data);
      expect(result, isNotNull);
      expect(result, equals(const SysEx([0x7E, 0x7F, 0x09, 0x01])));
      expect(reassembler.isAccumulating, isFalse);
    });

    test('segmented SysEx: start + end', () {
      // Start segment (F0 ... no F7)
      final start = Uint8List.fromList([0xF0, 0x43, 0x12]);
      expect(reassembler.process(start), isNull);
      expect(reassembler.isAccumulating, isTrue);

      // End segment (... F7)
      final end = Uint8List.fromList([0x00, 0x01, 0xF7]);
      final result = reassembler.process(end);
      expect(result, isNotNull);
      expect(result, equals(const SysEx([0x43, 0x12, 0x00, 0x01])));
      expect(reassembler.isAccumulating, isFalse);
    });

    test('segmented SysEx: start + continue + end', () {
      final start = Uint8List.fromList([0xF0, 0x43]);
      expect(reassembler.process(start), isNull);

      final cont = Uint8List.fromList([0x12, 0x00]);
      expect(reassembler.process(cont), isNull);
      expect(reassembler.isAccumulating, isTrue);

      final end = Uint8List.fromList([0x01, 0xF7]);
      final result = reassembler.process(end);
      expect(result, equals(const SysEx([0x43, 0x12, 0x00, 0x01])));
    });

    test('cancel discards partial data', () {
      final start = Uint8List.fromList([0xF0, 0x43, 0x12]);
      reassembler.process(start);
      expect(reassembler.isAccumulating, isTrue);

      reassembler.cancel();
      expect(reassembler.isAccumulating, isFalse);

      // End segment without start should return null
      final end = Uint8List.fromList([0x00, 0xF7]);
      expect(reassembler.process(end), isNull);
    });

    test('reset discards partial data', () {
      final start = Uint8List.fromList([0xF0, 0x43]);
      reassembler.process(start);
      expect(reassembler.isAccumulating, isTrue);

      reassembler.reset();
      expect(reassembler.isAccumulating, isFalse);
    });

    test('end segment without start returns null', () {
      final end = Uint8List.fromList([0x00, 0x01, 0xF7]);
      expect(reassembler.process(end), isNull);
    });

    test('continue segment without start returns null', () {
      final cont = Uint8List.fromList([0x12, 0x00]);
      expect(reassembler.process(cont), isNull);
    });

    test('empty data returns null', () {
      expect(reassembler.process(Uint8List(0)), isNull);
    });

    test('new start resets previous accumulation', () {
      // Start first SysEx
      final start1 = Uint8List.fromList([0xF0, 0x01, 0x02]);
      reassembler.process(start1);

      // Start second SysEx (should reset)
      final start2 = Uint8List.fromList([0xF0, 0x03, 0x04]);
      reassembler.process(start2);

      // End the second one
      final end = Uint8List.fromList([0x05, 0xF7]);
      final result = reassembler.process(end);
      expect(result, equals(const SysEx([0x03, 0x04, 0x05])));
    });

    test('complete SysEx clears any pending accumulation', () {
      // Start accumulating
      final start = Uint8List.fromList([0xF0, 0x01]);
      reassembler.process(start);
      expect(reassembler.isAccumulating, isTrue);

      // Complete SysEx should clear state
      final complete = Uint8List.fromList([0xF0, 0x02, 0x03, 0xF7]);
      final result = reassembler.process(complete);
      expect(result, equals(const SysEx([0x02, 0x03])));
      expect(reassembler.isAccumulating, isFalse);
    });

    test('minimal SysEx (just F0 F7)', () {
      final data = Uint8List.fromList([0xF0, 0xF7]);
      final result = reassembler.process(data);
      expect(result, equals(const SysEx([])));
    });
  });
}
