/// Systematic MIDI message test against a real macOS Network MIDI session.
///
/// Sends every MIDI 1.0 message type in sequence and prints all incoming
/// messages. Use with MIDI Monitor on the Mac to verify both directions.
///
/// Usage:
///   dart run example/midi_message_test.dart [ip] [port]
///
/// Setup on the remote Mac:
///   1. Open Audio MIDI Setup > Window > Show MIDI Studio > double-click Network
///   2. Create a session, tick the checkbox to enable it
///   3. Open MIDI Monitor to see incoming messages
///   4. Optionally open a DAW or MIDI keyboard to send messages back
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_rtp_midi/rtp_midi.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/midi_message_test.dart <ip> [port]');
    print('');
    print('Sends every MIDI message type and prints incoming MIDI.');
    exit(1);
  }

  final address = args[0];
  final port = args.length > 1 ? int.parse(args[1]) : 5004;

  print('Connecting to $address:$port ...');

  final client = RtpMidiClient(
    config: const RtpMidiConfig(name: 'Dart MIDI Test'),
  );

  try {
    final session = await client.connectToAddress(address, port);
    print('Connected to "${session.remoteName}"');

    // Print all incoming MIDI.
    session.onMidiMessage.listen((msg) {
      print('  << RECV: $msg');
    });

    // Wait for ready state.
    if (session.state != SessionState.ready) {
      await session.onStateChanged.firstWhere((s) => s == SessionState.ready);
    }
    print('Session ready. Starting message test...\n');

    await _runMessageTest(session);

    print(
        '\n--- Test complete. Listening for incoming MIDI. Ctrl+C to quit. ---\n');

    ProcessSignal.sigint.watch().listen((_) async {
      print('\nDisconnecting...');
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

Future<void> _runMessageTest(RtpMidiSession session) async {
  const d = Duration(milliseconds: 300);

  // --- Channel Voice Messages ---
  _section('Channel Voice Messages');

  _send(session, 'Note On C4 vel=100',
      const NoteOn(channel: 0, note: 60, velocity: 100));
  await Future.delayed(d);

  _send(
      session, 'Note Off C4', const NoteOff(channel: 0, note: 60, velocity: 0));
  await Future.delayed(d);

  _send(session, 'Note On E4 vel=80 (ch 1)',
      const NoteOn(channel: 1, note: 64, velocity: 80));
  await Future.delayed(d);

  _send(session, 'Note Off E4 (ch 1)',
      const NoteOff(channel: 1, note: 64, velocity: 0));
  await Future.delayed(d);

  _send(session, 'CC#7 (Volume) = 100',
      const ControlChange(channel: 0, controller: 7, value: 100));
  await Future.delayed(d);

  _send(session, 'CC#64 (Sustain) = 127',
      const ControlChange(channel: 0, controller: 64, value: 127));
  await Future.delayed(d);

  _send(session, 'CC#64 (Sustain) = 0',
      const ControlChange(channel: 0, controller: 64, value: 0));
  await Future.delayed(d);

  _send(session, 'CC#1 (Mod Wheel) = 64',
      const ControlChange(channel: 0, controller: 1, value: 64));
  await Future.delayed(d);

  _send(session, 'Program Change #0',
      const ProgramChange(channel: 0, program: 0));
  await Future.delayed(d);

  _send(session, 'Program Change #42',
      const ProgramChange(channel: 0, program: 42));
  await Future.delayed(d);

  _send(session, 'Pitch Bend center (8192)',
      const PitchBend(channel: 0, value: 8192));
  await Future.delayed(d);

  _send(session, 'Pitch Bend max (16383)',
      const PitchBend(channel: 0, value: 16383));
  await Future.delayed(d);

  _send(session, 'Pitch Bend min (0)', const PitchBend(channel: 0, value: 0));
  await Future.delayed(d);

  _send(session, 'Pitch Bend back to center',
      const PitchBend(channel: 0, value: 8192));
  await Future.delayed(d);

  _send(session, 'Channel Aftertouch = 80',
      const ChannelAftertouch(channel: 0, pressure: 80));
  await Future.delayed(d);

  _send(session, 'Channel Aftertouch = 0',
      const ChannelAftertouch(channel: 0, pressure: 0));
  await Future.delayed(d);

  _send(session, 'Poly Aftertouch C4 = 90',
      const PolyAftertouch(channel: 0, note: 60, pressure: 90));
  await Future.delayed(d);

  _send(session, 'Poly Aftertouch C4 = 0',
      const PolyAftertouch(channel: 0, note: 60, pressure: 0));
  await Future.delayed(d);

  // --- Channel 10 (drums) ---
  _section('Channel 10 (Drums)');

  _send(session, 'Note On Bass Drum (ch9 note 36)',
      const NoteOn(channel: 9, note: 36, velocity: 100));
  await Future.delayed(d);

  _send(session, 'Note Off Bass Drum',
      const NoteOff(channel: 9, note: 36, velocity: 0));
  await Future.delayed(d);

  _send(session, 'Note On Snare (ch9 note 38)',
      const NoteOn(channel: 9, note: 38, velocity: 110));
  await Future.delayed(d);

  _send(session, 'Note Off Snare',
      const NoteOff(channel: 9, note: 38, velocity: 0));
  await Future.delayed(d);

  // --- System Common ---
  _section('System Common Messages');

  _send(session, 'MTC Quarter Frame', const MtcQuarterFrame(0x51));
  await Future.delayed(d);

  _send(session, 'Song Position = 0', const SongPosition(0));
  await Future.delayed(d);

  _send(session, 'Song Position = 1000', const SongPosition(1000));
  await Future.delayed(d);

  _send(session, 'Song Select #3', const SongSelect(3));
  await Future.delayed(d);

  _send(session, 'Tune Request', const TuneRequest());
  await Future.delayed(d);

  // --- System Real-Time ---
  _section('System Real-Time Messages');

  _send(session, 'Start', const Start());
  await Future.delayed(d);

  // Send a few timing clocks.
  for (var i = 0; i < 6; i++) {
    _send(session, 'Timing Clock ($i)', const TimingClock());
    await Future.delayed(const Duration(milliseconds: 50));
  }

  _send(session, 'Continue', const Continue());
  await Future.delayed(d);

  for (var i = 0; i < 3; i++) {
    _send(session, 'Timing Clock', const TimingClock());
    await Future.delayed(const Duration(milliseconds: 50));
  }

  _send(session, 'Stop', const Stop());
  await Future.delayed(d);

  _send(session, 'Active Sensing', const ActiveSensing());
  await Future.delayed(d);

  // SystemReset is potentially disruptive — send last.
  _send(session, 'System Reset', const SystemReset());
  await Future.delayed(d);

  // --- SysEx ---
  _section('System Exclusive');

  _send(session, 'SysEx: GM System On', const SysEx([0x7E, 0x7F, 0x09, 0x01]));
  await Future.delayed(d);

  _send(session, 'SysEx: Identity Request',
      const SysEx([0x7E, 0x7F, 0x06, 0x01]));
  await Future.delayed(d);

  // --- Edge cases ---
  _section('Edge Cases');

  _send(session, 'Note On vel=0 (implicit Note Off)',
      const NoteOn(channel: 0, note: 60, velocity: 0));
  await Future.delayed(d);

  _send(session, 'Note On max values (ch15 note127 vel127)',
      const NoteOn(channel: 15, note: 127, velocity: 127));
  await Future.delayed(d);

  _send(session, 'Note Off max values',
      const NoteOff(channel: 15, note: 127, velocity: 127));
  await Future.delayed(d);

  _send(session, 'CC#0 (Bank Select MSB) = 0',
      const ControlChange(channel: 0, controller: 0, value: 0));
  await Future.delayed(d);

  _send(session, 'CC#127 = 127',
      const ControlChange(channel: 0, controller: 127, value: 127));
  await Future.delayed(d);

  _send(session, 'Program Change #127',
      const ProgramChange(channel: 0, program: 127));
  await Future.delayed(d);
}

void _section(String name) {
  print('--- $name ---');
}

void _send(RtpMidiSession session, String description, MidiMessage message) {
  print('  >> SEND: $description');
  session.send(message);
}
