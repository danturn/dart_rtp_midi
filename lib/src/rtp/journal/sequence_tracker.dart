/// Tracks RTP sequence numbers and detects gaps.
///
/// Immutable — [process] returns a new tracker plus a gap flag.
/// Handles uint16 wrapping (65535 → 0 is not a gap).
class SequenceTracker {
  final int? _expectedNext;

  const SequenceTracker._(this._expectedNext);

  /// Initial state before any packets have been received.
  static const initial = SequenceTracker._(null);

  /// Process an incoming sequence number.
  ///
  /// Returns `(newTracker, gapDetected)`. The first packet never triggers
  /// a gap. Normal successor (with uint16 wrapping) is not a gap.
  static (SequenceTracker, bool) process(SequenceTracker tracker, int seqNum) {
    final expected = tracker._expectedNext;
    final next = (seqNum + 1) & 0xFFFF;

    if (expected == null) {
      // First packet — no gap.
      return (SequenceTracker._(next), false);
    }

    final gap = (seqNum & 0xFFFF) != expected;
    return (SequenceTracker._(next), gap);
  }
}
