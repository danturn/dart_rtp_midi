import 'dart:typed_data';

import 'package:dart_rtp_midi/src/api/midi_message.dart';
import 'package:dart_rtp_midi/src/rtp/midi_command_codec.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_header.dart';
import 'package:dart_rtp_midi/src/rtp/rtp_midi_payload.dart';
import 'package:test/test.dart';

void main() {
  group('RtpMidiPayload', () {
    test('encode/decode roundtrip with single NoteOn', () {
      const original = RtpMidiPayload(
        header: RtpHeader(
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0x12345678,
        ),
        commands: [
          TimestampedMidiCommand(
              0, NoteOn(channel: 0, note: 60, velocity: 100)),
        ],
      );
      final bytes = original.encode();
      final decoded = RtpMidiPayload.decode(bytes)!;

      expect(decoded.header, equals(original.header));
      expect(decoded.commands.length, equals(1));
      expect(decoded.commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
      expect(decoded.hasJournal, isFalse);
    });

    test('encode/decode roundtrip with multiple commands', () {
      const original = RtpMidiPayload(
        header: RtpHeader(
          sequenceNumber: 42,
          timestamp: 5000,
          ssrc: 0xDEADBEEF,
        ),
        commands: [
          TimestampedMidiCommand(
              0, NoteOn(channel: 0, note: 60, velocity: 100)),
          TimestampedMidiCommand(
              50, NoteOff(channel: 0, note: 60, velocity: 0)),
        ],
      );
      final bytes = original.encode();
      final decoded = RtpMidiPayload.decode(bytes)!;

      expect(decoded.commands.length, equals(2));
      expect(decoded.commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
      expect(decoded.commands[1].message,
          equals(const NoteOff(channel: 0, note: 60, velocity: 0)));
    });

    test('short header when command data <= 15 bytes', () {
      const payload = RtpMidiPayload(
        header: RtpHeader(
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0,
        ),
        commands: [
          TimestampedMidiCommand(
              0, NoteOn(channel: 0, note: 60, velocity: 100)),
        ],
      );
      final bytes = payload.encode();
      // 12 (RTP) + 1 (short header) + 3 (NoteOn) = 16 bytes
      expect(bytes.length, equals(16));
      // B flag should be 0 (short header)
      expect(bytes[12] & 0x80, equals(0));
    });

    test('long header when command data > 15 bytes', () {
      // Create enough commands to exceed 15 bytes of command data.
      final commands = List.generate(
        6,
        (i) => TimestampedMidiCommand(
            i == 0 ? 0 : 1, NoteOn(channel: 0, note: 60 + i, velocity: 100)),
      );
      final payload = RtpMidiPayload(
        header: const RtpHeader(
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0,
        ),
        commands: commands,
      );
      final bytes = payload.encode();
      // B flag should be 1 (long header)
      expect(bytes[12] & 0x80, equals(0x80));

      // Verify roundtrip
      final decoded = RtpMidiPayload.decode(bytes)!;
      expect(decoded.commands.length, equals(6));
    });

    test('journal flag preserved', () {
      final journal = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final payload = RtpMidiPayload(
        header: const RtpHeader(
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0,
        ),
        commands: const [
          TimestampedMidiCommand(
              0, NoteOn(channel: 0, note: 60, velocity: 100)),
        ],
        hasJournal: true,
        journalData: journal,
      );
      final bytes = payload.encode();
      // J flag at bit 6 of first MIDI header byte
      expect(bytes[12] & 0x40, equals(0x40));

      final decoded = RtpMidiPayload.decode(bytes)!;
      expect(decoded.hasJournal, isTrue);
      expect(decoded.journalData, equals(journal));
    });

    test('Z flag is 0 when first delta time is omitted', () {
      const payload = RtpMidiPayload(
        header: RtpHeader(
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0,
        ),
        commands: [
          TimestampedMidiCommand(
              0, NoteOn(channel: 0, note: 60, velocity: 100)),
        ],
      );
      final bytes = payload.encode();
      // Z flag at bit 5
      expect(bytes[12] & 0x20, equals(0));
    });

    test('decode returns null for too-short data', () {
      expect(RtpMidiPayload.decode(Uint8List(12)), isNull);
      expect(RtpMidiPayload.decode(Uint8List(0)), isNull);
    });

    test('decode returns null for non-RTP version', () {
      final bytes = Uint8List(16);
      bytes[0] = 0x40; // version 1
      expect(RtpMidiPayload.decode(bytes), isNull);
    });

    test('empty command section', () {
      // RTP header + short command header with LEN=0
      final bytes = Uint8List(13);
      bytes[0] = 0x80; // V=2
      bytes[1] = 0x61; // PT=97
      bytes[12] = 0x00; // B=0, J=0, Z=0, P=0, LEN=0

      final decoded = RtpMidiPayload.decode(bytes)!;
      expect(decoded.commands, isEmpty);
      expect(decoded.hasJournal, isFalse);
    });

    test('decode with Z flag set (first command has delta time)', () {
      // Build a packet where Z=1 (first command has delta time)
      final rtpHeader = const RtpHeader(
        sequenceNumber: 5,
        timestamp: 2000,
        ssrc: 0xABCD1234,
      ).encode();

      // Command data: delta=10, NoteOn(ch0, note60, vel100)
      final cmdData = Uint8List.fromList([0x0A, 0x90, 60, 100]);

      final packet = Uint8List(12 + 1 + cmdData.length);
      packet.setRange(0, 12, rtpHeader);
      // Short header: B=0, J=0, Z=1, P=0, LEN=4
      packet[12] = 0x20 | cmdData.length;
      packet.setRange(13, 13 + cmdData.length, cmdData);

      final decoded = RtpMidiPayload.decode(packet)!;
      expect(decoded.commands.length, equals(1));
      expect(decoded.commands[0].deltaTime, equals(10));
      expect(decoded.commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
    });

    test('Apple-format vector: single Note On', () {
      // Construct a realistic Apple RTP-MIDI packet by hand.
      final bytes = Uint8List.fromList([
        // RTP Header (12 bytes)
        0x80, 0xE1, // V=2, M=1, PT=97
        0x00, 0x01, // Seq=1
        0x00, 0x00, 0x03, 0xE8, // TS=1000
        0xAA, 0xBB, 0xCC, 0xDD, // SSRC
        // MIDI Command Section Header (1 byte, short)
        0x03, // B=0, J=0, Z=0, P=0, LEN=3
        // MIDI Command Data (3 bytes)
        0x90, 0x3C, 0x64, // Note On ch0 note60 vel100
      ]);
      final decoded = RtpMidiPayload.decode(bytes)!;
      expect(decoded.header.marker, isTrue);
      expect(decoded.header.payloadType, equals(97));
      expect(decoded.header.sequenceNumber, equals(1));
      expect(decoded.header.timestamp, equals(1000));
      expect(decoded.header.ssrc, equals(0xAABBCCDD));
      expect(decoded.commands.length, equals(1));
      expect(decoded.commands[0].message,
          equals(const NoteOn(channel: 0, note: 60, velocity: 100)));
    });
  });
}
