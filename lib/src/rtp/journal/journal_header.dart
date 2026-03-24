import 'dart:typed_data';

/// The 3-byte recovery journal header.
///
/// Wire format (big-endian):
/// ```
/// Byte 0: S(1) Y(1) A(1) H(1) TOTCHAN(4)
/// Bytes 1-2: Checkpoint Packet Seqnum (uint16)
/// ```
class JournalHeader {
  /// Single packet loss hint.
  final bool singlePacketLoss;

  /// System journal present.
  final bool systemJournalPresent;

  /// Channel journals present.
  final bool channelJournalsPresent;

  /// Enhanced Chapter C encoding.
  final bool enhancedChapterC;

  /// Number of channel journals minus 1 (0–15).
  final int totalChannels;

  /// Checkpoint packet sequence number.
  final int checkpointSeqNum;

  const JournalHeader({
    this.singlePacketLoss = false,
    this.systemJournalPresent = false,
    this.channelJournalsPresent = false,
    this.enhancedChapterC = false,
    this.totalChannels = 0,
    required this.checkpointSeqNum,
  });

  /// Size of the journal header in bytes.
  static const int size = 3;

  /// Encode this header to a 3-byte [Uint8List].
  Uint8List encode() {
    final data = Uint8List(size);
    final view = ByteData.sublistView(data);

    data[0] = (singlePacketLoss ? 0x80 : 0) |
        (systemJournalPresent ? 0x40 : 0) |
        (channelJournalsPresent ? 0x20 : 0) |
        (enhancedChapterC ? 0x10 : 0) |
        (totalChannels & 0x0F);
    view.setUint16(1, checkpointSeqNum & 0xFFFF);

    return data;
  }

  /// Decode a journal header from [bytes] at [offset].
  ///
  /// Returns `null` if there are fewer than 3 bytes available.
  static JournalHeader? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) return null;

    final view = ByteData.sublistView(bytes, offset);
    final byte0 = bytes[offset];

    return JournalHeader(
      singlePacketLoss: (byte0 & 0x80) != 0,
      systemJournalPresent: (byte0 & 0x40) != 0,
      channelJournalsPresent: (byte0 & 0x20) != 0,
      enhancedChapterC: (byte0 & 0x10) != 0,
      totalChannels: byte0 & 0x0F,
      checkpointSeqNum: view.getUint16(1),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JournalHeader &&
          singlePacketLoss == other.singlePacketLoss &&
          systemJournalPresent == other.systemJournalPresent &&
          channelJournalsPresent == other.channelJournalsPresent &&
          enhancedChapterC == other.enhancedChapterC &&
          totalChannels == other.totalChannels &&
          checkpointSeqNum == other.checkpointSeqNum;

  @override
  int get hashCode => Object.hash(
        singlePacketLoss,
        systemJournalPresent,
        channelJournalsPresent,
        enhancedChapterC,
        totalChannels,
        checkpointSeqNum,
      );

  @override
  String toString() =>
      'JournalHeader(S=$singlePacketLoss, Y=$systemJournalPresent, '
      'A=$channelJournalsPresent, H=$enhancedChapterC, '
      'TOTCHAN=$totalChannels, seq=$checkpointSeqNum)';
}
