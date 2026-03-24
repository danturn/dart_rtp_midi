import 'dart:typed_data';

import '../../api/midi_message.dart';
import 'channel_journal.dart';
import 'journal_header.dart';
import 'midi_state.dart';

/// Pure function: compute corrective MIDI messages from a recovery journal.
///
/// Compares the journal state (what the sender believes we should have)
/// against [localState] (what we actually have). Returns messages to
/// bring the receiver in sync with the sender.
List<MidiMessage> recoverFromJournal(
    Uint8List journalData, MidiState localState) {
  final header = JournalHeader.decode(journalData);
  if (header == null) return const [];
  if (!header.channelJournalsPresent) return const [];

  final messages = <MidiMessage>[];
  var offset = JournalHeader.size;
  final channelCount = header.totalChannels + 1;

  for (int i = 0; i < channelCount; i++) {
    final result = ChannelJournal.decode(journalData, offset);
    if (result == null) break;
    final (journal, consumed) = result;

    _recoverChannel(journal, localState.channels[journal.channel], messages);
    offset += consumed;
  }

  return messages;
}

void _recoverChannel(
    ChannelJournal journal, ChannelState localCh, List<MidiMessage> messages) {
  final ch = journal.channel;

  _recoverChapterP(journal, ch, localCh, messages);
  _recoverChapterC(journal, ch, localCh, messages);
  _recoverChapterW(journal, ch, localCh, messages);
  _recoverChapterN(journal, ch, localCh, messages);
  _recoverChapterT(journal, ch, localCh, messages);
  _recoverChapterA(journal, ch, localCh, messages);
}

void _recoverChapterP(ChannelJournal journal, int ch, ChannelState localCh,
    List<MidiMessage> messages) {
  final p = journal.chapterP;
  if (p == null) return;

  // Emit bank select if needed before program change.
  if (p.b && p.bankMsb != (localCh.bankMsb?.value ?? -1)) {
    messages.add(ControlChange(channel: ch, controller: 0, value: p.bankMsb));
  }
  if (p.x && p.bankLsb != (localCh.bankLsb?.value ?? -1)) {
    messages.add(ControlChange(channel: ch, controller: 32, value: p.bankLsb));
  }

  if (p.program != localCh.program?.value) {
    messages.add(ProgramChange(channel: ch, program: p.program));
  }
}

/// MIDI CC numbers that are on/off switches (values ≥64 = on, <64 = off).
/// RFC 6295 Appendix C.2 — these use the toggle tool when A=1, T=0.
const _toggleControllers = {64, 65, 66, 67, 68, 69};

void _recoverChapterC(ChannelJournal journal, int ch, ChannelState localCh,
    List<MidiMessage> messages) {
  final c = journal.chapterC;
  if (c == null) return;

  // Skip CC#0 and CC#32 if Chapter P already handles bank select,
  // to avoid emitting duplicate bank select messages.
  final skipBankSelect = journal.chapterP != null;

  for (final log in c.logs) {
    if (skipBankSelect && (log.number == 0 || log.number == 32)) continue;

    if (log.a) {
      // A=1: alternate encoding. Extract T flag and ALT field.
      final tFlag = (log.value >> 6) & 1;
      final alt = log.value & 0x3F;

      if (tFlag == 0 && _toggleControllers.contains(log.number)) {
        // Toggle tool: ALT = toggle count mod 64.
        // Odd count → "on" (127), even count → "off" (0).
        _recoverToggle(ch, log.number, alt, localCh, messages);
      }
      // T=1 (count tool) or non-toggle controller with T=0:
      // skip — we can't meaningfully recover without more context.
      continue;
    }

    // A=0: value encoding — use the value directly.
    final localValue = localCh.controllers[log.number]?.value;
    if (localValue != log.value) {
      messages.add(
          ControlChange(channel: ch, controller: log.number, value: log.value));
    }
  }
}

void _recoverToggle(int ch, int controller, int toggleCount,
    ChannelState localCh, List<MidiMessage> messages) {
  // Odd toggle count → controller should be "on", even → "off".
  // Default state at session start is "off" (0).
  final shouldBeOn = (toggleCount % 2) == 1;
  final targetValue = shouldBeOn ? 127 : 0;
  // Treat absent controller as "off" (0) — the MIDI default.
  final localValue = localCh.controllers[controller]?.value ?? 0;

  if (localValue != targetValue) {
    messages.add(
        ControlChange(channel: ch, controller: controller, value: targetValue));
  }
}

void _recoverChapterW(ChannelJournal journal, int ch, ChannelState localCh,
    List<MidiMessage> messages) {
  final w = journal.chapterW;
  if (w == null) return;

  if (w.first != (localCh.pitchBendFirst?.value ?? -1) ||
      w.second != (localCh.pitchBendSecond?.value ?? -1)) {
    final value = (w.second & 0x7F) << 7 | (w.first & 0x7F);
    messages.add(PitchBend(channel: ch, value: value));
  }
}

void _recoverChapterN(ChannelJournal journal, int ch, ChannelState localCh,
    List<MidiMessage> messages) {
  final n = journal.chapterN;

  // Collect journal's active notes (Y=1 logs).
  final journalNotes = <int, int>{};
  if (n != null) {
    for (final log in n.logs) {
      if (log.y) {
        journalNotes[log.noteNum] = log.velocity;
      }
    }
  }
  // If Chapter N is absent, journalNotes stays empty — the sender has no
  // active notes on this channel. Any locally active notes are orphans.

  // Notes in journal but not locally active → emit NoteOn.
  for (final entry in journalNotes.entries) {
    final localVel = localCh.activeNotes[entry.key]?.value;
    if (localVel == null || localVel != entry.value) {
      messages.add(NoteOn(channel: ch, note: entry.key, velocity: entry.value));
    }
  }

  // Notes locally active but not in journal → emit NoteOff.
  for (final noteNum in localCh.activeNotes.keys) {
    if (!journalNotes.containsKey(noteNum)) {
      messages.add(NoteOff(channel: ch, note: noteNum, velocity: 0));
    }
  }
}

void _recoverChapterT(ChannelJournal journal, int ch, ChannelState localCh,
    List<MidiMessage> messages) {
  final t = journal.chapterT;
  if (t == null) return;

  if (t.pressure != (localCh.channelPressure?.value ?? -1)) {
    messages.add(ChannelAftertouch(channel: ch, pressure: t.pressure));
  }
}

void _recoverChapterA(ChannelJournal journal, int ch, ChannelState localCh,
    List<MidiMessage> messages) {
  final a = journal.chapterA;
  if (a == null) return;

  for (final log in a.logs) {
    final localPressure = localCh.polyPressure[log.noteNum]?.value;
    if (localPressure != log.pressure) {
      messages.add(PolyAftertouch(
          channel: ch, note: log.noteNum, pressure: log.pressure));
    }
  }
}
