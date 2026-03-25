/// Tracks RTP sequence numbers and detects gaps.
///
/// Immutable — [process] returns a new tracker plus a gap flag.
/// Handles uint16 wrapping (65535 → 0 is not a gap).
class SequenceTracker {
  final int? _expectedNext;
  final bool _hasProcessedJournal;

  const SequenceTracker._(this._expectedNext, this._hasProcessedJournal);

  /// Initial state before any packets have been received.
  static const initial = SequenceTracker._(null, false);

  /// Whether the first journal has been processed (for late-join recovery).
  bool get hasProcessedJournal => _hasProcessedJournal;

  /// Mark that a journal has been processed.
  SequenceTracker withJournalProcessed() =>
      SequenceTracker._(_expectedNext, true);

  /// Process an incoming sequence number.
  ///
  /// Returns `(newTracker, gapDetected)`. Detects gaps from sequence
  /// number discontinuities and from late-join (no journal processed yet).
  static (SequenceTracker, bool) process(SequenceTracker tracker, int seqNum) {
    final expected = tracker._expectedNext;
    final next = (seqNum + 1) & 0xFFFF;

    if (expected == null) {
      // First packet — signal gap for journal recovery per RFC 4695 §4.
      return (SequenceTracker._(next, false), true);
    }

    final seqGap = (seqNum & 0xFFFF) != expected;
    // Also signal gap if we haven't processed any journal yet (late join).
    final gap = seqGap || !tracker._hasProcessedJournal;
    return (SequenceTracker._(next, tracker._hasProcessedJournal), gap);
  }
}
