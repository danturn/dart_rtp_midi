import 'dart:typed_data';

import '../api/midi_message.dart';
import 'delta_time_codec.dart';

/// A MIDI command with an associated delta timestamp.
class TimestampedMidiCommand {
  /// Delta time in RTP timestamp ticks relative to the previous command.
  final int deltaTime;

  /// The MIDI message.
  final MidiMessage message;

  const TimestampedMidiCommand(this.deltaTime, this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimestampedMidiCommand &&
          deltaTime == other.deltaTime &&
          message == other.message;

  @override
  int get hashCode => Object.hash(deltaTime, message);

  @override
  String toString() => 'TimestampedMidiCommand(dt: $deltaTime, $message)';
}

/// Decode the MIDI command list from the command section of an RTP-MIDI payload.
///
/// [bytes] contains only the MIDI command data (after the command section
/// header byte(s)). [zFlag] indicates whether the first command has a delta
/// time (false = no delta time for first command). [pFlag] indicates phantom
/// status (running status from a previous packet).
List<TimestampedMidiCommand> decodeMidiCommands(
  Uint8List bytes, {
  bool zFlag = false,
  bool pFlag = false,
}) {
  if (bytes.isEmpty) return const [];

  final commands = <TimestampedMidiCommand>[];
  int offset = 0;
  int? runningStatus;

  while (offset < bytes.length) {
    // Parse delta time (all commands have one except possibly the first).
    int deltaTime = 0;
    if (zFlag || commands.isNotEmpty) {
      final dt = decodeDeltaTime(bytes, offset);
      if (dt == null) break;
      deltaTime = dt.value;
      offset += dt.bytesConsumed;
      if (offset >= bytes.length) break;
    }

    // Determine the status byte.
    int status;
    if (bytes[offset] & 0x80 != 0) {
      // Explicit status byte.
      status = bytes[offset];
      offset++;
      // Update running status for channel messages only.
      if (status < 0xF0) {
        runningStatus = status;
      } else if (status >= 0xF0 && status <= 0xF7) {
        // System common messages cancel running status.
        runningStatus = null;
      }
      // System real-time (0xF8-0xFF) do NOT affect running status.
    } else {
      // Running status.
      if (runningStatus == null && !pFlag) break;
      status = runningStatus ?? 0;
    }

    // Handle SysEx.
    if (status == 0xF0) {
      // Find the terminating F7.
      final start = offset;
      while (offset < bytes.length && bytes[offset] != 0xF7) {
        offset++;
      }
      if (offset < bytes.length) {
        offset++; // consume F7
      }
      final sysexData =
          bytes.sublist(start, offset > start ? offset - 1 : offset);
      final message = SysEx(sysexData.toList());
      commands.add(TimestampedMidiCommand(deltaTime, message));
      continue;
    }

    // Handle SysEx end without start (segment continuation — skip).
    if (status == 0xF7) {
      continue;
    }

    // Determine data length for this status.
    final dataLen = midiDataLength(status);
    if (dataLen == null) break;

    if (dataLen == 0) {
      // Single-byte message (system real-time or tune request).
      final statusBytes = Uint8List.fromList([status]);
      final message = MidiMessage.fromBytes(statusBytes);
      if (message != null) {
        commands.add(TimestampedMidiCommand(deltaTime, message));
      }
      continue;
    }

    // Read data bytes.
    if (offset + dataLen > bytes.length) break;
    final msgBytes = Uint8List(1 + dataLen);
    msgBytes[0] = status;
    for (int i = 0; i < dataLen; i++) {
      msgBytes[1 + i] = bytes[offset + i];
    }
    offset += dataLen;

    final message = MidiMessage.fromBytes(msgBytes);
    if (message != null) {
      commands.add(TimestampedMidiCommand(deltaTime, message));
    }
  }

  return commands;
}

/// Encode a list of timestamped MIDI commands into the command section body.
///
/// If [omitFirstDeltaTime] is true, the first command's delta time is not
/// written (the Z flag will be 0 in the header).
Uint8List encodeMidiCommands(
  List<TimestampedMidiCommand> commands, {
  bool omitFirstDeltaTime = true,
}) {
  if (commands.isEmpty) return Uint8List(0);

  final buffer = BytesBuilder(copy: false);

  for (int i = 0; i < commands.length; i++) {
    final cmd = commands[i];

    // Delta time.
    if (i == 0 && omitFirstDeltaTime) {
      // Skip delta time for first command.
    } else {
      buffer.add(encodeDeltaTime(cmd.deltaTime));
    }

    // MIDI bytes — always include status byte (no running status on encode).
    final midiBytes = cmd.message.toBytes();
    buffer.add(midiBytes);
  }

  return buffer.toBytes();
}
