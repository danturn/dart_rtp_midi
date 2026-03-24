import 'exchange_packet.dart';

/// The result of a completed clock synchronization exchange.
///
/// After the CK0/CK1/CK2 three-way handshake, these values describe the
/// estimated clock relationship between the two peers.
class ClockSyncResult {
  /// Estimated offset between local and remote clocks, in microseconds.
  ///
  /// A positive value means the remote clock is ahead of the local clock.
  /// Add this offset to local timestamps to approximate remote time.
  final int offsetMicroseconds;

  /// Estimated one-way network latency, in microseconds.
  final int latencyMicroseconds;

  const ClockSyncResult({
    required this.offsetMicroseconds,
    required this.latencyMicroseconds,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClockSyncResult &&
          offsetMicroseconds == other.offsetMicroseconds &&
          latencyMicroseconds == other.latencyMicroseconds;

  @override
  int get hashCode => Object.hash(offsetMicroseconds, latencyMicroseconds);

  @override
  String toString() =>
      'ClockSyncResult(offset: ${offsetMicroseconds}us, '
      'latency: ${latencyMicroseconds}us)';
}

/// Create a CK0 (clock sync initiation) packet.
///
/// The initiator sets [timestamp1] to its current clock value.
/// [ssrc] identifies the sender.
ClockSyncPacket createCk0({
  required int ssrc,
  required int timestamp1,
}) {
  return ClockSyncPacket(
    ssrc: ssrc,
    count: 0,
    timestamp1: timestamp1,
  );
}

/// Create a CK1 (clock sync response) packet.
///
/// The responder copies [timestamp1] from the received CK0 and sets
/// [timestamp2] to its own current clock value.
ClockSyncPacket createCk1({
  required int ssrc,
  required int timestamp1,
  required int timestamp2,
}) {
  return ClockSyncPacket(
    ssrc: ssrc,
    count: 1,
    timestamp1: timestamp1,
    timestamp2: timestamp2,
  );
}

/// Create a CK2 (clock sync completion) packet.
///
/// The initiator copies [timestamp1] and [timestamp2] from the received CK1,
/// and sets [timestamp3] to its own current clock value.
ClockSyncPacket createCk2({
  required int ssrc,
  required int timestamp1,
  required int timestamp2,
  required int timestamp3,
}) {
  return ClockSyncPacket(
    ssrc: ssrc,
    count: 2,
    timestamp1: timestamp1,
    timestamp2: timestamp2,
    timestamp3: timestamp3,
  );
}

/// Compute the clock offset and network latency from a completed CK2 packet.
///
/// The three timestamps represent:
/// - t1: initiator's clock when CK0 was sent
/// - t2: responder's clock when CK1 was sent
/// - t3: initiator's clock when CK2 was sent
///
/// Timestamps are 64-bit values in 100-microsecond ticks (10 kHz clock).
///
/// The offset is computed as:
///   offset = ((t1 + t3) / 2) - t2
///
/// This is the estimated difference between the initiator's clock and the
/// responder's clock (positive means the responder is ahead).
///
/// The round-trip time is (t3 - t1), so the estimated one-way latency
/// is (t3 - t1) / 2.
///
/// Both values are converted from 100-microsecond ticks to microseconds.
ClockSyncResult computeOffset(ClockSyncPacket ck2Packet) {
  assert(ck2Packet.count == 2, 'Expected a CK2 packet (count == 2)');

  final t1 = ck2Packet.timestamp1;
  final t2 = ck2Packet.timestamp2;
  final t3 = ck2Packet.timestamp3;

  // Offset in ticks: ((t1 + t3) / 2) - t2
  // Use integer arithmetic to avoid floating-point: ((t1 + t3) - 2 * t2) / 2
  final offsetTicks = ((t1 + t3) - 2 * t2) ~/ 2;

  // Round-trip time in ticks.
  final rttTicks = t3 - t1;

  // One-way latency estimate in ticks.
  final latencyTicks = rttTicks ~/ 2;

  // Convert from 100-microsecond ticks to microseconds.
  const tickMicroseconds = 100;

  return ClockSyncResult(
    offsetMicroseconds: offsetTicks * tickMicroseconds,
    latencyMicroseconds: latencyTicks * tickMicroseconds,
  );
}
