import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/journal/channel_journal.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_builder.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_header.dart';
import 'package:dart_rtp_midi/src/rtp/journal/midi_state.dart';
import 'package:dart_rtp_midi/src/rtp/journal/state_update.dart';
import 'package:test/test.dart';

void main() {
  group('buildJournal', () {
    test('returns null for empty state', () {
      expect(buildJournal(MidiState.empty, 0), isNull);
    });

    test('returns null when all channels are empty', () {
      expect(buildJournal(MidiState.empty, 1000), isNull);
    });

    group('header', () {
      test('has correct flags for single channel', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 42)!;
        final header = JournalHeader.decode(bytes);
        expect(header, isNotNull);
        expect(header!.singlePacketLoss, isTrue);
        expect(header.systemJournalPresent, isFalse);
        expect(header.channelJournalsPresent, isTrue);
        expect(header.enhancedChapterC, isFalse);
        expect(header.totalChannels, 0); // 1 channel - 1 = 0
        expect(header.checkpointSeqNum, 42);
      });

      test('totalChannels matches active channel count', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 5, note: 64, velocity: 80));
        state = updateState(
            state, const ControlChange(channel: 9, controller: 7, value: 100));
        final bytes = buildJournal(state, 0)!;
        final header = JournalHeader.decode(bytes)!;
        expect(header.totalChannels, 2); // 3 channels - 1 = 2
      });

      test('checkpoint seqnum wraps uint16', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 65535)!;
        final header = JournalHeader.decode(bytes)!;
        expect(header.checkpointSeqNum, 65535);
      });
    });

    group('Chapter P', () {
      test('encodes program change', () {
        var state = MidiState.empty;
        state =
            updateState(state, const ProgramChange(channel: 0, program: 42));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterP, isNotNull);
        expect(decoded.chapterP!.program, 42);
        expect(decoded.chapterP!.s, isTrue);
      });

      test('encodes program with bank select', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 0, controller: 0, value: 5));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 32, value: 3));
        state =
            updateState(state, const ProgramChange(channel: 0, program: 42));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterP!.b, isTrue);
        expect(decoded.chapterP!.bankMsb, 5);
        expect(decoded.chapterP!.x, isTrue);
        expect(decoded.chapterP!.bankLsb, 3);
      });

      test('no Chapter P when no program change', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterP, isNull);
      });
    });

    group('Chapter C', () {
      test('encodes single controller', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 100));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterC, isNotNull);
        expect(decoded.chapterC!.logs.length, 1);
        expect(decoded.chapterC!.logs[0].number, 7);
        expect(decoded.chapterC!.logs[0].value, 100);
        expect(decoded.chapterC!.logs[0].s, isTrue);
      });

      test('encodes multiple controllers', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 100));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 11, value: 80));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterC!.logs.length, 2);
      });

      test('no Chapter C when no controllers', () {
        var state = MidiState.empty;
        state = updateState(state, const ProgramChange(channel: 0, program: 1));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterC, isNull);
      });
    });

    group('Chapter N', () {
      test('encodes active notes', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterN, isNotNull);
        expect(decoded.chapterN!.logs.length, 1);
        expect(decoded.chapterN!.logs[0].noteNum, 60);
        expect(decoded.chapterN!.logs[0].velocity, 100);
        expect(decoded.chapterN!.logs[0].y, isTrue);
        expect(decoded.chapterN!.logs[0].s, isTrue);
      });

      test('NoteOff produces offbit bitmap instead of note log', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        // Channel 0 has a released note — Chapter N with offbits.
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterN, isNotNull);
        expect(decoded.chapterN!.logs, isEmpty);
        expect(decoded.chapterN!.b, isTrue);
        expect(decoded.chapterN!.offBits, isNotNull);
        // Note 60 is in octet 7 (60 ~/ 8 = 7), bit 4 (60 % 8 = 4).
        // Bit 4 MSB-first = 0x80 >> 4 = 0x08.
        expect(decoded.chapterN!.low, 7);
        expect(decoded.chapterN!.high, 7);
        expect(decoded.chapterN!.offBits![0], 0x08);
      });

      test('multiple active notes', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 64, velocity: 80));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterN!.logs.length, 2);
      });

      test('no offbits (LOW=15, HIGH=0)', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterN!.low, 15);
        expect(decoded.chapterN!.high, 0);
        expect(decoded.chapterN!.offBits, isNull);
      });
    });

    group('Chapter W', () {
      test('encodes pitch bend', () {
        var state = MidiState.empty;
        state = updateState(state, const PitchBend(channel: 0, value: 8192));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterW, isNotNull);
        expect(decoded.chapterW!.first, 0); // LSB of 8192
        expect(decoded.chapterW!.second, 64); // MSB of 8192
        expect(decoded.chapterW!.s, isTrue);
      });

      test('no Chapter W when no pitch bend', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterW, isNull);
      });
    });

    group('Chapter T', () {
      test('encodes channel aftertouch', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ChannelAftertouch(channel: 0, pressure: 100));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterT, isNotNull);
        expect(decoded.chapterT!.pressure, 100);
        expect(decoded.chapterT!.s, isTrue);
      });
    });

    group('Chapter A', () {
      test('encodes poly aftertouch', () {
        var state = MidiState.empty;
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 60, pressure: 80));
        final bytes = buildJournal(state, 0)!;
        final decoded = _decodeFirstChannel(bytes);
        expect(decoded.chapterA, isNotNull);
        expect(decoded.chapterA!.logs.length, 1);
        expect(decoded.chapterA!.logs[0].noteNum, 60);
        expect(decoded.chapterA!.logs[0].pressure, 80);
        expect(decoded.chapterA!.logs[0].s, isTrue);
      });
    });

    group('roundtrip', () {
      test('complex state roundtrips through encode/decode', () {
        var state = MidiState.empty;
        // Channel 0: note + CC + program + bank + pitch + pressure
        state = updateState(
            state, const ControlChange(channel: 0, controller: 0, value: 1));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 32, value: 2));
        state =
            updateState(state, const ProgramChange(channel: 0, program: 42));
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 80));
        state = updateState(state, const PitchBend(channel: 0, value: 10000));
        state = updateState(
            state, const ChannelAftertouch(channel: 0, pressure: 50));
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 60, pressure: 40));
        // Channel 9: note only
        state = updateState(
            state, const NoteOn(channel: 9, note: 36, velocity: 127));

        final bytes = buildJournal(state, 1000)!;

        // Decode header
        final header = JournalHeader.decode(bytes)!;
        expect(header.channelJournalsPresent, isTrue);
        expect(header.totalChannels, 1); // 2 channels - 1

        // Decode channel journals
        var offset = JournalHeader.size;
        final ch0result = ChannelJournal.decode(bytes, offset);
        expect(ch0result, isNotNull);
        final (ch0, ch0Size) = ch0result!;
        expect(ch0.channel, 0);
        expect(ch0.chapterP!.program, 42);
        expect(ch0.chapterP!.b, isTrue);
        expect(ch0.chapterP!.bankMsb, 1);
        expect(ch0.chapterP!.x, isTrue);
        expect(ch0.chapterP!.bankLsb, 2);
        expect(ch0.chapterC, isNotNull);
        expect(ch0.chapterN!.logs.length, 1);
        expect(ch0.chapterW, isNotNull);
        expect(ch0.chapterT!.pressure, 50);
        expect(ch0.chapterA!.logs.length, 1);

        offset += ch0Size;
        final ch9result = ChannelJournal.decode(bytes, offset);
        expect(ch9result, isNotNull);
        final (ch9, _) = ch9result!;
        expect(ch9.channel, 9);
        expect(ch9.chapterN!.logs.length, 1);
        expect(ch9.chapterN!.logs[0].noteNum, 36);
        expect(ch9.chapterP, isNull);
      });

      test('single controller roundtrips', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 3, controller: 64, value: 127));
        final bytes = buildJournal(state, 500)!;

        final header = JournalHeader.decode(bytes)!;
        expect(header.checkpointSeqNum, 500);
        expect(header.totalChannels, 0);

        final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
        expect(ch.channel, 3);
        expect(ch.chapterC!.logs.length, 1);
        expect(ch.chapterC!.logs[0].number, 64);
        expect(ch.chapterC!.logs[0].value, 127);
      });
    });

    group('channel ordering', () {
      test('channels appear in ascending order', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 9, note: 36, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 5, note: 48, velocity: 100));

        final bytes = buildJournal(state, 0)!;
        var offset = JournalHeader.size;

        final (ch0, ch0Size) = ChannelJournal.decode(bytes, offset)!;
        expect(ch0.channel, 0);
        offset += ch0Size;

        final (ch5, ch5Size) = ChannelJournal.decode(bytes, offset)!;
        expect(ch5.channel, 5);
        offset += ch5Size;

        final (ch9, _) = ChannelJournal.decode(bytes, offset)!;
        expect(ch9.channel, 9);
      });
    });

    group('offbit field', () {
      test('released note produces offbit bitmap', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        final bytes = buildJournal(state, 0)!;
        final ch = _decodeFirstChannel(bytes);
        expect(ch.chapterN, isNotNull);
        expect(ch.chapterN!.b, isTrue);
        expect(ch.chapterN!.logs, isEmpty);
        expect(ch.chapterN!.offBits, isNotNull);
      });

      test('offbit bitmap bit position is correct (MSB-first)', () {
        var state = MidiState.empty;
        // Note 0: octet 0, bit 0 → 0x80
        state = updateState(
            state, const NoteOn(channel: 0, note: 0, velocity: 100));
        state =
            updateState(state, const NoteOff(channel: 0, note: 0, velocity: 0));
        final bytes = buildJournal(state, 0)!;
        final ch = _decodeFirstChannel(bytes);
        expect(ch.chapterN!.low, 0);
        expect(ch.chapterN!.high, 0);
        expect(ch.chapterN!.offBits![0], 0x80); // MSB = note 0
      });

      test('offbit bitmap spans multiple octets', () {
        var state = MidiState.empty;
        // Note 8 (octet 1) and note 23 (octet 2)
        state = updateState(
            state, const NoteOn(channel: 0, note: 8, velocity: 100));
        state =
            updateState(state, const NoteOff(channel: 0, note: 8, velocity: 0));
        state = updateState(
            state, const NoteOn(channel: 0, note: 23, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 23, velocity: 0));
        final bytes = buildJournal(state, 0)!;
        final ch = _decodeFirstChannel(bytes);
        expect(ch.chapterN!.low, 1); // 8 ~/ 8 = 1
        expect(ch.chapterN!.high, 2); // 23 ~/ 8 = 2
        expect(ch.chapterN!.offBits!.length, 2);
        // Note 8: octet index 1-1=0, bit 0 → 0x80
        expect(ch.chapterN!.offBits![0], 0x80);
        // Note 23: octet index 2-1=1, bit 7 → 0x01
        expect(ch.chapterN!.offBits![1], 0x01);
      });

      test('active notes and offbits coexist', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 64, velocity: 80));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        // Note 64 is active, note 60 is released.
        final bytes = buildJournal(state, 0)!;
        final ch = _decodeFirstChannel(bytes);
        expect(ch.chapterN!.b, isTrue);
        expect(ch.chapterN!.logs.length, 1);
        expect(ch.chapterN!.logs[0].noteNum, 64);
        expect(ch.chapterN!.offBits, isNotNull);
      });

      test('re-triggered note removed from offbits', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 80));
        // Note 60 is active again — no offbits needed.
        final bytes = buildJournal(state, 0)!;
        final ch = _decodeFirstChannel(bytes);
        expect(ch.chapterN!.logs.length, 1);
        expect(ch.chapterN!.logs[0].noteNum, 60);
        expect(ch.chapterN!.b, isFalse);
      });

      test('channel with only released notes creates a journal', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 3, note: 48, velocity: 100));
        state = updateState(
            state, const NoteOff(channel: 3, note: 48, velocity: 0));
        // Channel 3 has only a released note — should still get a journal.
        final bytes = buildJournal(state, 0);
        expect(bytes, isNotNull);
        final ch = _decodeFirstChannel(bytes!);
        expect(ch.channel, 3);
        expect(ch.chapterN, isNotNull);
        expect(ch.chapterN!.b, isTrue);
        expect(ch.chapterN!.logs, isEmpty);
      });

      test('offbit roundtrips through encode/decode', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 36, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 80));
        state = updateState(
            state, const NoteOff(channel: 0, note: 36, velocity: 0));
        // Note 60 active, note 36 released.
        final bytes = buildJournal(state, 0)!;
        final ch = _decodeFirstChannel(bytes);
        expect(ch.chapterN!.logs.length, 1);
        expect(ch.chapterN!.logs[0].noteNum, 60);
        expect(ch.chapterN!.b, isTrue);
        // Note 36: octet 4 (36~/8=4), bit 4 (36%8=4) → 0x80>>4 = 0x08
        expect(ch.chapterN!.low, 4);
        expect(ch.chapterN!.high, 4);
        expect(ch.chapterN!.offBits![0], 0x08);
      });
    });

    group('Wireshark dissector cross-validation', () {
      test('builder output matches Wireshark decode_cj_chapter_n parsing', () {
        // Scenario: note 64 active, note 60 released, CC7=100, checkpoint=1000
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        state = updateState(
            state, const NoteOn(channel: 0, note: 64, velocity: 80));
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 100));
        state = updateState(
            state, const NoteOff(channel: 0, note: 60, velocity: 0));

        final bytes = buildJournal(state, 1000)!;

        // Trace through Wireshark's decode logic byte-by-byte.

        // --- Journal Header (3 bytes) ---
        // Byte 0: S=1, Y=0, A=1, H=0, TOTCHAN=0
        expect(bytes[0], 0xa0);
        // Bytes 1-2: checkpoint seqnum = 1000 (0x03E8)
        expect(bytes[1], 0x03);
        expect(bytes[2], 0xe8);

        // --- Channel Journal Header (3 bytes) ---
        // S=1, CHAN=0, H=0
        expect((bytes[3] >> 7) & 1, 1); // S
        expect((bytes[3] >> 3) & 0x0F, 0); // CHAN
        // Chapter flags: C=1, N=1
        expect(bytes[5] & 0x40, 0x40); // C flag
        expect(bytes[5] & 0x08, 0x08); // N flag

        // --- Chapter C (after channel header) ---
        // S=1, LEN=0 (1 log)
        expect(bytes[6], 0x80);
        // Log 0: S=1, NUMBER=7, A=0, VALUE=100
        expect(bytes[7], 0x87); // S=1 | 7
        expect(bytes[8], 100); // A=0 | 100

        // --- Chapter N ---
        // Wireshark: header = tvb_get_ntohs(tvb, offset) → big-endian uint16
        final nHeader = (bytes[9] << 8) | bytes[10];
        // log_count = (header & 0x7f00) >> 8
        final logCount = (nHeader & 0x7f00) >> 8;
        expect(logCount, 1);
        // low = (header & 0x00f0) >> 4
        final low = (nHeader & 0x00f0) >> 4;
        expect(low, 7);
        // high = header & 0x000f
        final high = nHeader & 0x000f;
        expect(high, 7);
        // B flag
        expect((nHeader >> 15) & 1, 1);
        // octet_count = high - low + 1 = 1 (since low <= high)
        final octetCount = high - low + 1;
        expect(octetCount, 1);

        // Note log 0: S=1, NOTENUM=64, Y=1, VELOCITY=80
        expect(bytes[11] & 0x7f, 64); // NOTENUM
        expect((bytes[11] >> 7) & 1, 1); // S
        expect(bytes[12] & 0x7f, 80); // VELOCITY
        expect((bytes[12] >> 7) & 1, 1); // Y

        // Offbit octet: note 60 is in octet 7 (60~/8=7), bit 4 (60%8=4)
        // MSB-first: 0x80 >> 4 = 0x08 = binary 00001000
        expect(bytes[13], 0x08);
        // Wireshark would display: Octet 7, bit 4 → note 60 NoteOff

        // Verify total size: 3 (journal hdr) + 3 (chan hdr) + 3 (ch C) +
        //                    2 (ch N hdr) + 2 (1 note log) + 1 (offbit) = 14
        expect(bytes.length, 14);
      });
    });

    group('S-bit compliance', () {
      test('journal header S=1', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 0)!;
        final header = JournalHeader.decode(bytes)!;
        expect(header.singlePacketLoss, isTrue);
      });

      test('channel journal S=1', () {
        var state = MidiState.empty;
        state = updateState(
            state, const NoteOn(channel: 0, note: 60, velocity: 100));
        final bytes = buildJournal(state, 0)!;
        final ch = ChannelJournal.decode(bytes, JournalHeader.size)!.$1;
        expect(ch.s, isTrue);
      });
    });
  });
}

/// Decode the first channel journal from journal bytes.
ChannelJournal _decodeFirstChannel(Uint8List bytes) {
  final result = ChannelJournal.decode(bytes, JournalHeader.size);
  expect(result, isNotNull, reason: 'Failed to decode first channel journal');
  return result!.$1;
}
