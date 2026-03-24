/// Returns `true` if RTP seqnum [a] is strictly after [b],
/// handling uint16 wrapping via signed comparison modulo 2^16.
///
/// When [b] is the checkpoint seqnum, `seqAfter(a, b)` means
/// "the state at [a] has not been confirmed by the receiver."
bool seqAfter(int a, int b) => ((a - b) & 0xFFFF) < 0x8000 && a != b;

/// Returns `true` if RTP seqnum [a] is at or after [b].
///
/// Used by the journal builder to include entries at the checkpoint
/// (i.e., the first unconfirmed packet).
bool seqAtOrAfter(int a, int b) => a == b || seqAfter(a, b);
