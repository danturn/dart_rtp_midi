import 'dart:typed_data';

/// Result of decoding a variable-length delta time.
class DeltaTimeResult {
  /// The decoded delta time value.
  final int value;

  /// Number of bytes consumed from the input.
  final int bytesConsumed;

  const DeltaTimeResult(this.value, this.bytesConsumed);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeltaTimeResult &&
          value == other.value &&
          bytesConsumed == other.bytesConsumed;

  @override
  int get hashCode => Object.hash(value, bytesConsumed);

  @override
  String toString() => 'DeltaTimeResult($value, $bytesConsumed bytes)';
}

/// Decode a variable-length quantity (VLQ) delta time from [bytes] at [offset].
///
/// Uses the same encoding as standard MIDI: the high bit of each byte is a
/// continuation flag, with 7 data bits per byte, most significant bits first.
/// Maximum 4 bytes (28 data bits).
///
/// Returns `null` if the data is malformed (runs past end of buffer or
/// exceeds 4 bytes).
DeltaTimeResult? decodeDeltaTime(Uint8List bytes, int offset) {
  if (offset >= bytes.length) return null;

  int value = 0;
  int bytesConsumed = 0;

  for (int i = 0; i < 4; i++) {
    if (offset + i >= bytes.length) return null;
    final byte = bytes[offset + i];
    value = (value << 7) | (byte & 0x7F);
    bytesConsumed++;
    if ((byte & 0x80) == 0) {
      return DeltaTimeResult(value, bytesConsumed);
    }
  }

  // More than 4 continuation bytes — malformed.
  return null;
}

/// Encode a delta time value as a variable-length quantity (VLQ).
///
/// [value] must be non-negative and fit in 28 bits (0–268435455).
Uint8List encodeDeltaTime(int value) {
  assert(value >= 0 && value <= 0x0FFFFFFF, 'Delta time must be 0..268435455');

  if (value < 0x80) {
    return Uint8List.fromList([value]);
  }

  // Build bytes in reverse order.
  final temp = <int>[];
  temp.add(value & 0x7F);
  value >>= 7;
  while (value > 0) {
    temp.add(0x80 | (value & 0x7F));
    value >>= 7;
  }

  return Uint8List.fromList(temp.reversed.toList());
}
