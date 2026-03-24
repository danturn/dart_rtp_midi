/// Dumps the raw hex bytes of an RTP-MIDI packet for debugging.
///
/// Usage: dart run tool/dump_packet.dart
library;

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_header.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_midi_payload.dart';

void main() {
  final payload = RtpMidiPayload(
    header: const RtpHeader(
      sequenceNumber: 1,
      timestamp: 1000,
      ssrc: 0x12345678,
      marker: true,
      payloadType: 97,
    ),
    commands: const [
      TimestampedMidiCommand(0, NoteOn(channel: 0, note: 60, velocity: 100)),
    ],
  );

  final bytes = payload.encode();

  print('Total length: ${bytes.length} bytes');
  print('');

  // Hex dump
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  print('Hex: $hex');
  print('');

  // Annotated breakdown
  print('RTP Header (12 bytes):');
  print(
      '  Byte 0:  0x${bytes[0].toRadixString(16).padLeft(2, '0')}  V=${(bytes[0] >> 6) & 0x03}, P=${(bytes[0] >> 5) & 1}, X=${(bytes[0] >> 4) & 1}, CC=${bytes[0] & 0x0F}');
  print(
      '  Byte 1:  0x${bytes[1].toRadixString(16).padLeft(2, '0')}  M=${(bytes[1] >> 7) & 1}, PT=${bytes[1] & 0x7F}');
  print('  Bytes 2-3: Seq=${bytes[2] << 8 | bytes[3]}');
  print(
      '  Bytes 4-7: TS=${bytes[4] << 24 | bytes[5] << 16 | bytes[6] << 8 | bytes[7]}');
  print(
      '  Bytes 8-11: SSRC=0x${(bytes[8] << 24 | bytes[9] << 16 | bytes[10] << 8 | bytes[11]).toRadixString(16)}');

  print('');
  print('MIDI Command Section Header (byte 12):');
  final midiHdr = bytes[12];
  print(
      '  0x${midiHdr.toRadixString(16).padLeft(2, '0')}  B=${(midiHdr >> 7) & 1}, J=${(midiHdr >> 6) & 1}, Z=${(midiHdr >> 5) & 1}, P=${(midiHdr >> 4) & 1}, LEN=${midiHdr & 0x0F}');

  print('');
  print('MIDI Command Data (bytes 13+):');
  for (var i = 13; i < bytes.length; i++) {
    print('  Byte $i: 0x${bytes[i].toRadixString(16).padLeft(2, '0')}');
  }

  print('');
  print('Expected for Note On C4 vel=100:');
  print('  RTP: V=2, M=1, PT=97, Seq=1, TS=1000, SSRC=0x12345678');
  print('  MIDI hdr: B=0, J=0, Z=0, P=0, LEN=3');
  print('  MIDI data: 0x90 0x3c 0x64');
}
