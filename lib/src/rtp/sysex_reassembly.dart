import 'dart:typed_data';

import '../api/midi_message.dart';

/// Reassembles segmented SysEx messages from RTP-MIDI packets.
///
/// RTP-MIDI may split large SysEx messages across multiple packets.
/// This class accumulates segments and emits complete [SysEx] messages.
///
/// Segment types:
/// - Complete: F0 ... F7 in a single packet
/// - Start: F0 ... (no F7) — begins accumulation
/// - Continue: ... (no F0 or F7) — appends to buffer
/// - End: ... F7 — completes the message
class SysExReassembler {
  List<int>? _buffer;

  /// Process a SysEx segment.
  ///
  /// [data] should be the raw MIDI bytes including F0 and/or F7 framing
  /// as appropriate for the segment type.
  ///
  /// Returns a complete [SysEx] message when the final segment is received,
  /// or `null` if more segments are expected.
  SysEx? process(Uint8List data) {
    if (data.isEmpty) return null;

    final startsWithF0 = data[0] == 0xF0;
    final endsWithF7 = data.isNotEmpty && data[data.length - 1] == 0xF7;

    if (startsWithF0 && endsWithF7) {
      // Complete SysEx in one packet.
      _buffer = null;
      return SysEx(data.sublist(1, data.length - 1).toList());
    }

    if (startsWithF0) {
      // Start segment — begin accumulation.
      _buffer = data.sublist(1).toList();
      return null;
    }

    if (endsWithF7) {
      // End segment — complete the message.
      if (_buffer == null) return null; // No start received.
      _buffer!.addAll(data.sublist(0, data.length - 1));
      final result = SysEx(List<int>.from(_buffer!));
      _buffer = null;
      return result;
    }

    // Continue segment — append to buffer.
    if (_buffer == null) return null; // No start received.
    _buffer!.addAll(data);
    return null;
  }

  /// Cancel any in-progress SysEx reassembly.
  void cancel() {
    _buffer = null;
  }

  /// Reset the reassembler, discarding any partial data.
  void reset() {
    _buffer = null;
  }

  /// Whether a SysEx message is currently being assembled.
  bool get isAccumulating => _buffer != null;
}
