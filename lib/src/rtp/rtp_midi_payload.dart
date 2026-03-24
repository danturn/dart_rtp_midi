import 'dart:typed_data';

import 'midi_command_codec.dart';
import 'rtp_header.dart';

/// A fully decoded RTP-MIDI payload (RTP header + MIDI command section).
class RtpMidiPayload {
  /// The 12-byte RTP header.
  final RtpHeader header;

  /// Decoded MIDI commands from the command section.
  final List<TimestampedMidiCommand> commands;

  /// Whether a recovery journal is present (J flag).
  final bool hasJournal;

  /// Opaque journal data (parsed in Phase 3).
  final Uint8List? journalData;

  const RtpMidiPayload({
    required this.header,
    required this.commands,
    this.hasJournal = false,
    this.journalData,
  });

  /// Decode an RTP-MIDI payload from [bytes].
  ///
  /// Returns `null` if the packet is too short or malformed.
  ///
  /// Decode flow:
  /// 1. RTP header (12 bytes)
  /// 2. Command section header (1 or 2 bytes depending on B flag)
  /// 3. MIDI command data
  /// 4. Optional journal data
  static RtpMidiPayload? decode(Uint8List bytes) {
    // Minimum: 12 (RTP header) + 1 (short MIDI header).
    if (bytes.length < 13) return null;

    final header = RtpHeader.decode(bytes);
    if (header == null) return null;

    int offset = RtpHeader.size;

    // Parse the MIDI command section header.
    final firstByte = bytes[offset];
    final bFlag = (firstByte & 0x80) != 0; // Long header?
    final jFlag = (firstByte & 0x40) != 0; // Journal present?
    final zFlag = (firstByte & 0x20) != 0; // First cmd has delta time?
    final pFlag = (firstByte & 0x10) != 0; // Phantom (running) status?

    int commandLength;
    if (bFlag) {
      // Long header: 2 bytes, LEN is 12 bits.
      if (offset + 2 > bytes.length) return null;
      commandLength = ((firstByte & 0x0F) << 8) | bytes[offset + 1];
      offset += 2;
    } else {
      // Short header: 1 byte, LEN is 4 bits.
      commandLength = firstByte & 0x0F;
      offset += 1;
    }

    // Extract MIDI command data.
    if (offset + commandLength > bytes.length) return null;
    final commandData = bytes.sublist(offset, offset + commandLength);
    offset += commandLength;

    // Parse MIDI commands.
    final commands = decodeMidiCommands(
      commandData,
      zFlag: zFlag,
      pFlag: pFlag,
    );

    // Extract journal data if present.
    Uint8List? journalData;
    if (jFlag && offset < bytes.length) {
      journalData = bytes.sublist(offset);
    }

    return RtpMidiPayload(
      header: header,
      commands: commands,
      hasJournal: jFlag,
      journalData: journalData,
    );
  }

  /// Encode this payload to bytes suitable for transmission.
  ///
  /// The command section uses a short header (1 byte) if the command data
  /// length fits in 4 bits (0–15), otherwise a long header (2 bytes, up to
  /// 4095 bytes).
  Uint8List encode() {
    // Encode MIDI commands.
    final commandData = encodeMidiCommands(commands);
    final cmdLen = commandData.length;

    // Determine short vs long header.
    final useLongHeader = cmdLen > 15;

    // Build the MIDI command section header flags.
    // Z flag = 0 (first command has no delta time), P flag = 0 (no phantom).
    final jBit = hasJournal ? 0x40 : 0;

    final journal = journalData ?? Uint8List(0);

    // Total size: RTP header + command section header + command data + journal.
    final headerSize = useLongHeader ? 2 : 1;
    final totalSize = RtpHeader.size + headerSize + cmdLen + journal.length;
    final result = Uint8List(totalSize);

    // Write RTP header.
    final rtpBytes = header.encode();
    result.setRange(0, RtpHeader.size, rtpBytes);

    // Write command section header.
    int offset = RtpHeader.size;
    if (useLongHeader) {
      result[offset] = 0x80 | jBit | ((cmdLen >> 8) & 0x0F);
      result[offset + 1] = cmdLen & 0xFF;
      offset += 2;
    } else {
      result[offset] = jBit | (cmdLen & 0x0F);
      offset += 1;
    }

    // Write command data.
    result.setRange(offset, offset + cmdLen, commandData);
    offset += cmdLen;

    // Write journal data.
    if (journal.isNotEmpty) {
      result.setRange(offset, offset + journal.length, journal);
    }

    return result;
  }

  @override
  String toString() => 'RtpMidiPayload(commands: ${commands.length}, '
      'journal: $hasJournal, seq: ${header.sequenceNumber})';
}
