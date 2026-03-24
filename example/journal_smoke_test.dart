/// Smoke test for recovery journal integration with Apple CoreMIDI.
///
/// Connects to a macOS Network MIDI session and sends a sequence of messages
/// covering all journal chapters (P, C, W, N, T, A). Use Wireshark to verify
/// each outgoing packet includes a well-formed recovery journal.
///
/// Setup:
///   1. Mac: Audio MIDI Setup > Window > Show MIDI Studio > Network
///      Create a session, enable it, note the port (usually 5004)
///   2. Start Wireshark on the network interface, filter: "udp.port == 5005"
///      (data port = control port + 1)
///   3. Run: dart run example/journal_smoke_test.dart [mac-ip] [port]
///
/// What to verify in Wireshark:
///   - Every data packet has J=1 (journal flag set)
///   - Right-click a packet > Decode As > RTP, then re-dissect
///   - Journal section shows: S=1, Y=0, A=1, TOTCHAN=0
///   - Channel journal has chapters matching the sent messages
///   - After the NoteOff sequence, Chapter N should show offbit bitmap
///   - No malformed packet warnings
///
/// What to verify on the Mac:
///   - MIDI messages arrive (use MIDI Monitor or a DAW)
///   - No disconnection or rejection from Apple's CoreMIDI
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_rtp_midi/rtp_midi.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/journal_smoke_test.dart <ip> [port]');
    exit(1);
  }

  final address = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  print('Connecting to $address:$port ...');
  final client = RtpMidiClient(
    config: const RtpMidiConfig(name: 'Journal Smoke Test'),
  );

  try {
    final session = await client.connectToAddress(address, port);
    print('Connected to "${session.remoteName}"');

    // Wait for session to be ready (clock sync complete).
    await session.onReady;
    print('Session ready. Starting test sequence...\n');

    // Send messages with delays so each packet is distinct in Wireshark.
    await _runTestSequence(session);

    print('\nTest sequence complete.');
    print('Check Wireshark for journal dissection.');
    print('Press Ctrl+C to disconnect.\n');

    ProcessSignal.sigint.watch().listen((_) async {
      print('Disconnecting...');
      await session.disconnect();
      await client.dispose();
      exit(0);
    });
  } catch (e) {
    print('Failed: $e');
    await client.dispose();
    exit(1);
  }
}

Future<void> _runTestSequence(RtpMidiSession session) async {
  const d = Duration(milliseconds: 200);

  // --- Step 1: NoteOn → Chapter N (note log, Y=1) ---
  print('1. NoteOn C4 (ch0, vel=100) → Chapter N with 1 note log');
  session.send(const NoteOn(channel: 0, note: 60, velocity: 100));
  await Future.delayed(d);

  // --- Step 2: ControlChange → Chapter C ---
  print('2. CC7=80 (volume, ch0) → Chapter C with 1 log');
  session.send(const ControlChange(channel: 0, controller: 7, value: 80));
  await Future.delayed(d);

  // --- Step 3: ProgramChange → Chapter P ---
  print('3. ProgramChange=42 (ch0) → Chapter P added');
  session.send(const ProgramChange(channel: 0, program: 42));
  await Future.delayed(d);

  // --- Step 4: PitchBend → Chapter W ---
  print('4. PitchBend=8192 center (ch0) → Chapter W added');
  session.send(const PitchBend(channel: 0, value: 8192));
  await Future.delayed(d);

  // --- Step 5: ChannelAftertouch → Chapter T ---
  print('5. ChannelAftertouch=64 (ch0) → Chapter T added');
  session.send(const ChannelAftertouch(channel: 0, pressure: 64));
  await Future.delayed(d);

  // --- Step 6: PolyAftertouch → Chapter A ---
  print('6. PolyAftertouch note=60, pressure=50 (ch0) → Chapter A added');
  session.send(const PolyAftertouch(channel: 0, note: 60, pressure: 50));
  await Future.delayed(d);

  // --- Step 7: Second note on different channel ---
  print('7. NoteOn E2 (ch9, vel=127) → TOTCHAN becomes 1 (2 channels)');
  session.send(const NoteOn(channel: 9, note: 40, velocity: 127));
  await Future.delayed(d);

  // --- Step 8: NoteOff → offbit bitmap ---
  print(
      '8. NoteOff C4 (ch0) → Chapter N: note log removed, offbit for note 60');
  session.send(const NoteOff(channel: 0, note: 60, velocity: 0));
  await Future.delayed(d);

  // --- Step 9: Sustain pedal (toggle controller) ---
  print('9. CC64=127 sustain on (ch0) → Chapter C adds sustain log');
  session.send(const ControlChange(channel: 0, controller: 64, value: 127));
  await Future.delayed(d);

  // --- Step 10: Release sustain ---
  print('10. CC64=0 sustain off (ch0) → Chapter C updates sustain log');
  session.send(const ControlChange(channel: 0, controller: 64, value: 0));
  await Future.delayed(d);

  // --- Step 11: Clean up notes ---
  print('11. NoteOff E2 (ch9) → cleanup');
  session.send(const NoteOff(channel: 9, note: 40, velocity: 0));
  await Future.delayed(d);

  // --- Step 12: Reset pitch bend ---
  print('12. PitchBend=8192 center (ch0) → Chapter W updated');
  session.send(const PitchBend(channel: 0, value: 8192));
  await Future.delayed(d);
}
