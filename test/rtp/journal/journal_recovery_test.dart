import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_builder.dart';
import 'package:dart_rtp_midi/src/rtp/journal/journal_recovery.dart';
import 'package:dart_rtp_midi/src/rtp/journal/midi_state.dart';
import 'package:dart_rtp_midi/src/rtp/journal/state_update.dart';
import 'package:test/test.dart';

void main() {
  group('recoverFromJournal', () {
    group('no-op when states match', () {
      test('identical note state produces no messages', () {
        // Sender has note 60 on ch0.
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 60, velocity: 100));

        // Receiver also has note 60 on ch0.
        final receiverState = senderState;

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(messages, isEmpty);
      });

      test('identical CC state produces no messages', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ControlChange(channel: 0, controller: 7, value: 100));
        final journal = buildJournal(state, 0)!;
        expect(recoverFromJournal(journal, state), isEmpty);
      });

      test('identical program state produces no messages', () {
        var state = MidiState.empty;
        state =
            updateState(state, const ProgramChange(channel: 0, program: 42));
        final journal = buildJournal(state, 0)!;
        expect(recoverFromJournal(journal, state), isEmpty);
      });

      test('identical pitch bend state produces no messages', () {
        var state = MidiState.empty;
        state = updateState(state, const PitchBend(channel: 0, value: 8192));
        final journal = buildJournal(state, 0)!;
        expect(recoverFromJournal(journal, state), isEmpty);
      });

      test('identical channel pressure produces no messages', () {
        var state = MidiState.empty;
        state = updateState(
            state, const ChannelAftertouch(channel: 0, pressure: 100));
        final journal = buildJournal(state, 0)!;
        expect(recoverFromJournal(journal, state), isEmpty);
      });

      test('identical poly pressure produces no messages', () {
        var state = MidiState.empty;
        state = updateState(
            state, const PolyAftertouch(channel: 0, note: 60, pressure: 80));
        final journal = buildJournal(state, 0)!;
        expect(recoverFromJournal(journal, state), isEmpty);
      });
    });

    group('Chapter N recovery', () {
      test('stuck note: journal has note, receiver does not → NoteOn', () {
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 60, velocity: 100));

        final journal = buildJournal(senderState, 0)!;
        // Receiver is empty (missed the NoteOn)
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(messages,
            contains(const NoteOn(channel: 0, note: 60, velocity: 100)));
      });

      test(
          'orphan note: receiver has note, journal has different note → NoteOff',
          () {
        // Sender has note 64 active (but not 60).
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 64, velocity: 80));

        // Receiver thinks note 60 is on (missed NoteOff) and doesn't have 64.
        var receiverState = MidiState.empty;
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 60, velocity: 100));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        // Should emit NoteOff for 60 and NoteOn for 64
        expect(messages,
            contains(const NoteOff(channel: 0, note: 60, velocity: 0)));
        expect(messages,
            contains(const NoteOn(channel: 0, note: 64, velocity: 80)));
      });

      test('note velocity mismatch → NoteOn with correct velocity', () {
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 60, velocity: 127));

        var receiverState = MidiState.empty;
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 60, velocity: 50));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(messages,
            contains(const NoteOn(channel: 0, note: 60, velocity: 127)));
      });

      test('multiple stuck notes', () {
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 60, velocity: 100));
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 64, velocity: 80));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(messages.length, 2);
        expect(
            messages,
            containsAll([
              const NoteOn(channel: 0, note: 60, velocity: 100),
              const NoteOn(channel: 0, note: 64, velocity: 80),
            ]));
      });
    });

    group('Chapter C recovery', () {
      test('missed CC → ControlChange', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 7, value: 100));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 7, value: 100)));
      });

      test('CC value mismatch → ControlChange with correct value', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 7, value: 100));

        var receiverState = MidiState.empty;
        receiverState = updateState(receiverState,
            const ControlChange(channel: 0, controller: 7, value: 50));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 7, value: 100)));
      });

      test('multiple CCs with some matching', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 7, value: 100));
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 11, value: 80));

        // Receiver has CC7=100 (matches) but missed CC11
        var receiverState = MidiState.empty;
        receiverState = updateState(receiverState,
            const ControlChange(channel: 0, controller: 7, value: 100));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(messages.length, 1);
        expect(messages[0],
            const ControlChange(channel: 0, controller: 11, value: 80));
      });
    });

    group('Chapter P recovery', () {
      test('missed program change → ProgramChange', () {
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const ProgramChange(channel: 0, program: 42));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(
            messages, contains(const ProgramChange(channel: 0, program: 42)));
      });

      test('program with bank select recovery', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 0, value: 5));
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 32, value: 3));
        senderState = updateState(
            senderState, const ProgramChange(channel: 0, program: 42));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        // Should include bank MSB, bank LSB, and program change
        expect(
            messages,
            containsAll([
              const ControlChange(channel: 0, controller: 0, value: 5),
              const ControlChange(channel: 0, controller: 32, value: 3),
              const ProgramChange(channel: 0, program: 42),
            ]));
      });
    });

    group('Chapter W recovery', () {
      test('missed pitch bend → PitchBend', () {
        var senderState = MidiState.empty;
        senderState =
            updateState(senderState, const PitchBend(channel: 0, value: 10000));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(messages, contains(const PitchBend(channel: 0, value: 10000)));
      });
    });

    group('Chapter T recovery', () {
      test('missed channel aftertouch → ChannelAftertouch', () {
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const ChannelAftertouch(channel: 0, pressure: 100));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(messages,
            contains(const ChannelAftertouch(channel: 0, pressure: 100)));
      });
    });

    group('Chapter A recovery', () {
      test('missed poly aftertouch → PolyAftertouch', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const PolyAftertouch(channel: 0, note: 60, pressure: 80));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(messages,
            contains(const PolyAftertouch(channel: 0, note: 60, pressure: 80)));
      });
    });

    group('multi-channel recovery', () {
      test('recovers across multiple channels', () {
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 60, velocity: 100));
        senderState = updateState(senderState,
            const ControlChange(channel: 9, controller: 7, value: 80));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(messages.length, 2);
        expect(
            messages,
            containsAll([
              const NoteOn(channel: 0, note: 60, velocity: 100),
              const ControlChange(channel: 9, controller: 7, value: 80),
            ]));
      });
    });

    group('edge cases', () {
      test('empty journal data returns empty list', () {
        final messages = recoverFromJournal(Uint8List(0), MidiState.empty);
        expect(messages, isEmpty);
      });

      test('too-short journal data returns empty list', () {
        final messages =
            recoverFromJournal(Uint8List.fromList([0x00]), MidiState.empty);
        expect(messages, isEmpty);
      });
    });

    group('orphan note recovery (absent Chapter N)', () {
      test('channel journal without Chapter N emits NoteOff for local notes',
          () {
        // Sender has CC7=100 but no active notes on channel 0.
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 7, value: 100));

        // Receiver has note 60 stuck (missed the NoteOff).
        var receiverState = MidiState.empty;
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 60, velocity: 100));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(messages,
            contains(const NoteOff(channel: 0, note: 60, velocity: 0)));
      });

      test('multiple orphan notes all get NoteOff', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 7, value: 100));

        var receiverState = MidiState.empty;
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 60, velocity: 100));
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 64, velocity: 80));
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 67, velocity: 90));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(
            messages,
            containsAll([
              const NoteOff(channel: 0, note: 60, velocity: 0),
              const NoteOff(channel: 0, note: 64, velocity: 0),
              const NoteOff(channel: 0, note: 67, velocity: 0),
            ]));
      });

      test('no spurious NoteOff when receiver also has no notes', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 7, value: 100));

        // Receiver has CC but no notes — should only get CC recovery.
        var receiverState = MidiState.empty;
        receiverState = updateState(receiverState,
            const ControlChange(channel: 0, controller: 7, value: 50));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        expect(messages.whereType<NoteOff>(), isEmpty);
      });

      test(
          'Chapter N present with notes takes precedence over absent-chapter logic',
          () {
        // Sender has note 64 active.
        var senderState = MidiState.empty;
        senderState = updateState(
            senderState, const NoteOn(channel: 0, note: 64, velocity: 80));

        // Receiver has note 60 active.
        var receiverState = MidiState.empty;
        receiverState = updateState(
            receiverState, const NoteOn(channel: 0, note: 60, velocity: 100));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, receiverState);
        // NoteOff for 60 (orphan) + NoteOn for 64 (stuck).
        expect(messages,
            contains(const NoteOff(channel: 0, note: 60, velocity: 0)));
        expect(messages,
            contains(const NoteOn(channel: 0, note: 64, velocity: 80)));
      });
    });

    group('bank select deduplication', () {
      test('no duplicate CC#0/CC#32 when Chapter P has bank select', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 0, value: 5));
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 32, value: 3));
        senderState = updateState(
            senderState, const ProgramChange(channel: 0, program: 42));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);

        // Should have exactly one CC#0 (from Chapter P) and one CC#32 (from Chapter P).
        final cc0s =
            messages.where((m) => m is ControlChange && m.controller == 0);
        final cc32s =
            messages.where((m) => m is ControlChange && m.controller == 32);
        expect(cc0s.length, 1, reason: 'Should have exactly one CC#0');
        expect(cc32s.length, 1, reason: 'Should have exactly one CC#32');
      });

      test('CC#0/CC#32 still emitted from Chapter C when no Chapter P', () {
        // Set bank select but no program change — Chapter P won't exist.
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 0, value: 5));
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 32, value: 3));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);

        expect(
            messages,
            containsAll([
              const ControlChange(channel: 0, controller: 0, value: 5),
              const ControlChange(channel: 0, controller: 32, value: 3),
            ]));
      });
    });

    group('Chapter C A-bit handling', () {
      test('A=0 uses value field directly', () {
        var senderState = MidiState.empty;
        senderState = updateState(senderState,
            const ControlChange(channel: 0, controller: 64, value: 127));

        final journal = buildJournal(senderState, 0)!;
        final messages = recoverFromJournal(journal, MidiState.empty);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 64, value: 127)));
      });

      test('A=1 T=0 toggle tool: odd count → on (127)', () {
        // CC#64 sustain, A=1, T=0, ALT=1 (one toggle → "on")
        // Byte: [A=1][T=0][ALT=000001] = 0x81
        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 64, value: 0x01, aFlag: true)], // T=0, ALT=1
        );

        final messages = recoverFromJournal(journalBytes, MidiState.empty);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 64, value: 127)));
      });

      test('A=1 T=0 toggle tool: even count → off (0)', () {
        // CC#64 sustain, A=1, T=0, ALT=2 (two toggles → back to "off")
        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 64, value: 0x02, aFlag: true)], // T=0, ALT=2
        );

        final messages = recoverFromJournal(journalBytes, MidiState.empty);
        // Local state is empty (default off=0), journal says off → no message
        expect(messages.where((m) => m is ControlChange && m.controller == 64),
            isEmpty);
      });

      test('A=1 T=0 toggle: corrects stuck sustain pedal', () {
        // Receiver thinks sustain is on (127), journal says 2 toggles (even=off)
        var receiverState = MidiState.empty;
        receiverState = updateState(receiverState,
            const ControlChange(channel: 0, controller: 64, value: 127));

        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 64, value: 0x02, aFlag: true)], // T=0, ALT=2
        );

        final messages = recoverFromJournal(journalBytes, receiverState);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 64, value: 0)));
      });

      test('A=1 T=0 toggle: high toggle count wraps mod 64', () {
        // ALT=63 (odd) → "on"
        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 64, value: 63, aFlag: true)], // T=0, ALT=63
        );

        final messages = recoverFromJournal(journalBytes, MidiState.empty);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 64, value: 127)));
      });

      test('A=1 T=0 toggle: works for all toggle CCs (64-69)', () {
        // CC#66 sostenuto, ALT=1 (odd → on)
        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 66, value: 0x01, aFlag: true)],
        );

        final messages = recoverFromJournal(journalBytes, MidiState.empty);
        expect(
            messages,
            contains(
                const ControlChange(channel: 0, controller: 66, value: 127)));
      });

      test('A=1 T=1 count tool: skipped (fire-and-forget)', () {
        // CC#123 All Notes Off, A=1, T=1, ALT=1
        // Byte: [A=1][T=1][ALT=000001] = 0xC1 → stored value = 0x41
        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 123, value: 0x41, aFlag: true)], // T=1, ALT=1
        );

        final messages = recoverFromJournal(journalBytes, MidiState.empty);
        // Count tool is skipped — no CC#123 emitted
        expect(messages.where((m) => m is ControlChange && m.controller == 123),
            isEmpty);
      });

      test('mixed A=0 and A=1 toggle logs', () {
        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [
            (number: 7, value: 100, aFlag: false), // A=0, value CC
            (number: 64, value: 0x01, aFlag: true), // A=1, T=0, toggle
          ],
        );

        final messages = recoverFromJournal(journalBytes, MidiState.empty);
        expect(
            messages,
            containsAll([
              const ControlChange(channel: 0, controller: 7, value: 100),
              const ControlChange(channel: 0, controller: 64, value: 127),
            ]));
      });

      test('A=1 T=0 toggle: no-op when local state already correct', () {
        // Receiver already has sustain on (127), journal says 1 toggle (odd=on)
        var receiverState = MidiState.empty;
        receiverState = updateState(receiverState,
            const ControlChange(channel: 0, controller: 64, value: 127));

        final journalBytes = _buildJournalWithChapterC(
          checkpointSeqNum: 0,
          channel: 0,
          logs: [(number: 64, value: 0x01, aFlag: true)],
        );

        final messages = recoverFromJournal(journalBytes, receiverState);
        expect(messages.where((m) => m is ControlChange && m.controller == 64),
            isEmpty);
      });
    });
  });
}

/// Build journal bytes with a hand-crafted Chapter C for testing A-bit handling.
Uint8List _buildJournalWithChapterC({
  required int checkpointSeqNum,
  required int channel,
  required List<({int number, int value, bool aFlag})> logs,
}) {
  // Encode Chapter C manually to control the A flag.
  final chapterCSize = 1 + logs.length * 2;
  final chapterC = Uint8List(chapterCSize);
  chapterC[0] = 0x80 | ((logs.length - 1) & 0x7F); // S=1, LEN
  for (int i = 0; i < logs.length; i++) {
    final log = logs[i];
    chapterC[1 + i * 2] = 0x80 | (log.number & 0x7F); // S=1, NUMBER
    chapterC[1 + i * 2 + 1] =
        (log.aFlag ? 0x80 : 0) | (log.value & 0x7F); // A, VALUE
  }

  // Channel journal header (3 bytes).
  final channelContentSize = 3 + chapterCSize;
  final channelHeader = Uint8List(3);
  channelHeader[0] = 0x80 | // S=1
      ((channel & 0x0F) << 3) |
      ((channelContentSize >> 8) & 0x03);
  channelHeader[1] = channelContentSize & 0xFF;
  channelHeader[2] = 0x40; // C flag only

  // Journal header.
  final header = Uint8List(3);
  final headerView = ByteData.sublistView(header);
  header[0] = 0x80 | 0x20; // S=1, A=1
  headerView.setUint16(1, checkpointSeqNum & 0xFFFF);

  // Assemble.
  final total = header.length + channelHeader.length + chapterC.length;
  final result = Uint8List(total);
  var offset = 0;
  result.setRange(offset, offset + header.length, header);
  offset += header.length;
  result.setRange(offset, offset + channelHeader.length, channelHeader);
  offset += channelHeader.length;
  result.setRange(offset, offset + chapterC.length, chapterC);
  return result;
}
