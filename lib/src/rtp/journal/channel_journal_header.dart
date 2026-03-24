import 'dart:typed_data';

/// Channel journal header (3 bytes).
///
/// Wire format (RFC 6295, Figure C.1):
/// ```
/// Byte 0: S(1) CHAN(4) H(1) LENGTH[9:8](2)
/// Byte 1: LENGTH[7:0](8)
/// Byte 2: P(1) C(1) M(1) W(1) N(1) E(1) T(1) A(1)
/// ```
/// LENGTH includes this 3-byte header. Chapters in wire order: P, C, M, W, N, E, T, A.
class ChannelJournalHeader {
  /// History trimmed flag.
  final bool s;

  /// 4-bit MIDI channel number (0–15).
  final int channel;

  /// Enhanced encoding flag.
  final bool h;

  /// 10-bit total length including this header.
  final int length;

  /// Chapter presence flags.
  final bool chapterP;
  final bool chapterC;
  final bool chapterM;
  final bool chapterW;
  final bool chapterN;
  final bool chapterE;
  final bool chapterT;
  final bool chapterA;

  const ChannelJournalHeader({
    this.s = false,
    required this.channel,
    this.h = false,
    required this.length,
    this.chapterP = false,
    this.chapterC = false,
    this.chapterM = false,
    this.chapterW = false,
    this.chapterN = false,
    this.chapterE = false,
    this.chapterT = false,
    this.chapterA = false,
  });

  /// Size of the channel journal header in bytes.
  static const int size = 3;

  /// Encode this header to a 3-byte [Uint8List].
  Uint8List encode() {
    final data = Uint8List(size);

    data[0] = (s ? 0x80 : 0) |
        ((channel & 0x0F) << 3) |
        (h ? 0x04 : 0) |
        ((length >> 8) & 0x03);
    data[1] = length & 0xFF;
    data[2] = (chapterP ? 0x80 : 0) |
        (chapterC ? 0x40 : 0) |
        (chapterM ? 0x20 : 0) |
        (chapterW ? 0x10 : 0) |
        (chapterN ? 0x08 : 0) |
        (chapterE ? 0x04 : 0) |
        (chapterT ? 0x02 : 0) |
        (chapterA ? 0x01 : 0);

    return data;
  }

  /// Decode a channel journal header from [bytes] at [offset].
  ///
  /// Returns `(header, bytesConsumed)` or `null` if data is truncated.
  static (ChannelJournalHeader, int)? decode(Uint8List bytes,
      [int offset = 0]) {
    if (bytes.length - offset < size) return null;

    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];
    final byte2 = bytes[offset + 2];

    return (
      ChannelJournalHeader(
        s: (byte0 & 0x80) != 0,
        channel: (byte0 >> 3) & 0x0F,
        h: (byte0 & 0x04) != 0,
        length: ((byte0 & 0x03) << 8) | byte1,
        chapterP: (byte2 & 0x80) != 0,
        chapterC: (byte2 & 0x40) != 0,
        chapterM: (byte2 & 0x20) != 0,
        chapterW: (byte2 & 0x10) != 0,
        chapterN: (byte2 & 0x08) != 0,
        chapterE: (byte2 & 0x04) != 0,
        chapterT: (byte2 & 0x02) != 0,
        chapterA: (byte2 & 0x01) != 0,
      ),
      size,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelJournalHeader &&
          s == other.s &&
          channel == other.channel &&
          h == other.h &&
          length == other.length &&
          chapterP == other.chapterP &&
          chapterC == other.chapterC &&
          chapterM == other.chapterM &&
          chapterW == other.chapterW &&
          chapterN == other.chapterN &&
          chapterE == other.chapterE &&
          chapterT == other.chapterT &&
          chapterA == other.chapterA;

  @override
  int get hashCode => Object.hash(
        s,
        channel,
        h,
        length,
        chapterP,
        chapterC,
        chapterM,
        chapterW,
        chapterN,
        chapterE,
        chapterT,
        chapterA,
      );

  @override
  String toString() {
    final chapters = <String>[];
    if (chapterP) chapters.add('P');
    if (chapterC) chapters.add('C');
    if (chapterM) chapters.add('M');
    if (chapterW) chapters.add('W');
    if (chapterN) chapters.add('N');
    if (chapterE) chapters.add('E');
    if (chapterT) chapters.add('T');
    if (chapterA) chapters.add('A');
    return 'ChannelJournalHeader(S=$s, CHAN=$channel, H=$h, '
        'LENGTH=$length, chapters=[${chapters.join(',')}])';
  }
}
