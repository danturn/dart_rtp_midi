import 'dart:typed_data';

/// A single parameter log entry in Chapter M.
///
/// Log header format depends on chapter-level Z, U, W flags:
/// - Short format (Z=1 AND (U=1 OR W=1)): 2-byte header
/// - Long format (otherwise): 3-byte header (adds Q|PNUM-MSB)
///
/// After the header comes a flags byte:
/// ```
/// Byte: J(1) K(1) L(1) M(1) N(1) T(1) V(1) R(1)
/// ```
/// J → +1 byte, K → +1 byte, L → +2 bytes, M → +2 bytes, N → +1 byte.
class ParamLog {
  /// History trimmed flag for this log.
  final bool s;

  /// 7-bit PNUM-LSB (always present).
  final int pnumLsb;

  /// Q flag (long format only).
  final bool? q;

  /// 7-bit PNUM-MSB (long format only, null in short format).
  final int? pnumMsb;

  // Flags byte
  final bool j;
  final bool k;
  final bool l;
  final bool m;
  final bool n;
  final bool t;
  final bool v;
  final bool r;

  /// J field: 1 byte.
  final int? jValue;

  /// K field: 1 byte.
  final int? kValue;

  /// L field: 2 bytes (big-endian uint16).
  final int? lValue;

  /// M field: 2 bytes (big-endian uint16).
  final int? mValue;

  /// N field: 1 byte.
  final int? nValue;

  const ParamLog({
    this.s = false,
    required this.pnumLsb,
    this.q,
    this.pnumMsb,
    this.j = false,
    this.k = false,
    this.l = false,
    this.m = false,
    this.n = false,
    this.t = false,
    this.v = false,
    this.r = false,
    this.jValue,
    this.kValue,
    this.lValue,
    this.mValue,
    this.nValue,
  });

  /// Whether this log uses short format (2-byte header) vs long (3-byte).
  bool get isShort => pnumMsb == null;

  /// Size of the trailing fields after the flags byte.
  int get _trailingSize =>
      (j ? 1 : 0) + (k ? 1 : 0) + (l ? 2 : 0) + (m ? 2 : 0) + (n ? 1 : 0);

  /// Total encoded size of this log entry.
  /// Short: S|PNUM-LSB + FLAGS = 2 bytes. Long: + Q|PNUM-MSB = 3 bytes.
  int get size => (isShort ? 2 : 3) + _trailingSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParamLog &&
          s == other.s &&
          pnumLsb == other.pnumLsb &&
          q == other.q &&
          pnumMsb == other.pnumMsb &&
          j == other.j &&
          k == other.k &&
          l == other.l &&
          m == other.m &&
          n == other.n &&
          t == other.t &&
          v == other.v &&
          r == other.r &&
          jValue == other.jValue &&
          kValue == other.kValue &&
          lValue == other.lValue &&
          mValue == other.mValue &&
          nValue == other.nValue;

  @override
  int get hashCode => Object.hash(
        s,
        pnumLsb,
        q,
        pnumMsb,
        j,
        k,
        l,
        m,
        n,
        t,
        v,
        r,
        jValue,
        kValue,
        lValue,
        mValue,
        nValue,
      );

  @override
  String toString() => 'ParamLog(S=$s, PNUM-LSB=$pnumLsb'
      '${pnumMsb != null ? ', Q=$q, PNUM-MSB=$pnumMsb' : ''}'
      ', flags=${j ? 'J' : ''}${k ? 'K' : ''}${l ? 'L' : ''}${m ? 'M' : ''}'
      '${n ? 'N' : ''}${t ? 'T' : ''}${v ? 'V' : ''}${r ? 'R' : ''})';
}

/// Channel Chapter M — Parameter System (variable length, self-sizing).
///
/// Wire format (RFC 6295, Figure C.3.1):
/// ```
/// Header (2 bytes): S(1) P(1) E(1) U(1) W(1) Z(1) LENGTH(10)
/// Optional PENDING (1 byte if P=1): Q(1) PENDING(7)
/// ```
/// Followed by parameter logs. Log header format determined by Z, U, W flags.
/// LENGTH is total chapter size including this 2-byte header.
class ChannelChapterM {
  /// History trimmed flag.
  final bool s;

  /// PENDING field present.
  final bool p;

  /// E flag (controller logs use enhanced encoding).
  final bool e;

  /// U flag (affects log format).
  final bool u;

  /// W flag (affects log format).
  final bool w;

  /// Z flag (affects log format: short vs long headers).
  final bool z;

  /// 7-bit PENDING value (present when [p] is true).
  final int? pending;

  /// Q flag on PENDING byte (present when [p] is true).
  final bool? pendingQ;

  /// Parameter log entries.
  final List<ParamLog> logs;

  const ChannelChapterM({
    this.s = false,
    this.p = false,
    this.e = false,
    this.u = false,
    this.w = false,
    this.z = false,
    this.pending,
    this.pendingQ,
    this.logs = const [],
  });

  /// Minimum size in bytes (header only).
  static const int headerSize = 2;

  /// Whether logs use short format (2-byte log header).
  bool get shortFormat => z && (u || w);

  /// Encode this chapter to a [Uint8List].
  Uint8List encode() {
    int totalLength = headerSize;
    if (p) totalLength += 1;
    for (final log in logs) {
      totalLength += log.size;
    }

    final data = Uint8List(totalLength);

    data[0] = (s ? 0x80 : 0) |
        (p ? 0x40 : 0) |
        (e ? 0x20 : 0) |
        (u ? 0x10 : 0) |
        (w ? 0x08 : 0) |
        (z ? 0x04 : 0) |
        ((totalLength >> 8) & 0x03);
    data[1] = totalLength & 0xFF;

    int pos = headerSize;

    if (p) {
      data[pos] = ((pendingQ ?? false) ? 0x80 : 0) | ((pending ?? 0) & 0x7F);
      pos += 1;
    }

    final short = shortFormat;
    for (final log in logs) {
      // Log header
      data[pos] = (log.s ? 0x80 : 0) | (log.pnumLsb & 0x7F);
      pos += 1;

      if (!short) {
        data[pos] = ((log.q ?? false) ? 0x80 : 0) | ((log.pnumMsb ?? 0) & 0x7F);
        pos += 1;
      }

      // Flags byte
      data[pos] = (log.j ? 0x80 : 0) |
          (log.k ? 0x40 : 0) |
          (log.l ? 0x20 : 0) |
          (log.m ? 0x10 : 0) |
          (log.n ? 0x08 : 0) |
          (log.t ? 0x04 : 0) |
          (log.v ? 0x02 : 0) |
          (log.r ? 0x01 : 0);
      pos += 1;

      // Trailing fields
      if (log.j) {
        data[pos] = (log.jValue ?? 0) & 0xFF;
        pos += 1;
      }
      if (log.k) {
        data[pos] = (log.kValue ?? 0) & 0xFF;
        pos += 1;
      }
      if (log.l) {
        final lv = log.lValue ?? 0;
        data[pos] = (lv >> 8) & 0xFF;
        data[pos + 1] = lv & 0xFF;
        pos += 2;
      }
      if (log.m) {
        final mv = log.mValue ?? 0;
        data[pos] = (mv >> 8) & 0xFF;
        data[pos + 1] = mv & 0xFF;
        pos += 2;
      }
      if (log.n) {
        data[pos] = (log.nValue ?? 0) & 0xFF;
        pos += 1;
      }
    }

    return data;
  }

  /// Decode Chapter M from [bytes] at [offset].
  ///
  /// Self-sizing via the 10-bit LENGTH field.
  /// Returns `(chapter, bytesConsumed)` or `null` if data is invalid.
  static (ChannelChapterM, int)? decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < headerSize) return null;

    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];

    final sFlag = (byte0 & 0x80) != 0;
    final pFlag = (byte0 & 0x40) != 0;
    final eFlag = (byte0 & 0x20) != 0;
    final uFlag = (byte0 & 0x10) != 0;
    final wFlag = (byte0 & 0x08) != 0;
    final zFlag = (byte0 & 0x04) != 0;
    final totalLength = ((byte0 & 0x03) << 8) | byte1;

    if (totalLength < headerSize) return null;
    if (bytes.length - offset < totalLength) return null;

    int pos = offset + headerSize;
    final end = offset + totalLength;

    bool? pendingQ;
    int? pending;
    if (pFlag) {
      if (pos >= end) return null;
      pendingQ = (bytes[pos] & 0x80) != 0;
      pending = bytes[pos] & 0x7F;
      pos += 1;
    }

    final short = zFlag && (uFlag || wFlag);
    final logs = <ParamLog>[];

    while (pos < end) {
      // Log header byte 1: S|PNUM-LSB
      if (pos >= end) return null;
      final logS = (bytes[pos] & 0x80) != 0;
      final pnumLsb = bytes[pos] & 0x7F;
      pos += 1;

      bool? logQ;
      int? pnumMsb;
      if (!short) {
        if (pos >= end) return null;
        logQ = (bytes[pos] & 0x80) != 0;
        pnumMsb = bytes[pos] & 0x7F;
        pos += 1;
      }

      // Flags byte
      if (pos >= end) return null;
      final flags = bytes[pos];
      pos += 1;

      final jFlag = (flags & 0x80) != 0;
      final kFlag = (flags & 0x40) != 0;
      final lFlag = (flags & 0x20) != 0;
      final mFlag = (flags & 0x10) != 0;
      final nFlag = (flags & 0x08) != 0;
      final tFlag = (flags & 0x04) != 0;
      final vFlag = (flags & 0x02) != 0;
      final rFlag = (flags & 0x01) != 0;

      int? jValue;
      if (jFlag) {
        if (pos >= end) return null;
        jValue = bytes[pos];
        pos += 1;
      }

      int? kValue;
      if (kFlag) {
        if (pos >= end) return null;
        kValue = bytes[pos];
        pos += 1;
      }

      int? lValue;
      if (lFlag) {
        if (pos + 1 >= end) return null;
        lValue = (bytes[pos] << 8) | bytes[pos + 1];
        pos += 2;
      }

      int? mValue;
      if (mFlag) {
        if (pos + 1 >= end) return null;
        mValue = (bytes[pos] << 8) | bytes[pos + 1];
        pos += 2;
      }

      int? nValue;
      if (nFlag) {
        if (pos >= end) return null;
        nValue = bytes[pos];
        pos += 1;
      }

      logs.add(ParamLog(
        s: logS,
        pnumLsb: pnumLsb,
        q: logQ,
        pnumMsb: pnumMsb,
        j: jFlag,
        k: kFlag,
        l: lFlag,
        m: mFlag,
        n: nFlag,
        t: tFlag,
        v: vFlag,
        r: rFlag,
        jValue: jValue,
        kValue: kValue,
        lValue: lValue,
        mValue: mValue,
        nValue: nValue,
      ));
    }

    return (
      ChannelChapterM(
        s: sFlag,
        p: pFlag,
        e: eFlag,
        u: uFlag,
        w: wFlag,
        z: zFlag,
        pendingQ: pendingQ,
        pending: pending,
        logs: logs,
      ),
      totalLength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelChapterM &&
          s == other.s &&
          p == other.p &&
          e == other.e &&
          u == other.u &&
          w == other.w &&
          z == other.z &&
          pendingQ == other.pendingQ &&
          pending == other.pending &&
          _logsEqual(logs, other.logs);

  static bool _logsEqual(List<ParamLog> a, List<ParamLog> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        s,
        p,
        e,
        u,
        w,
        z,
        pendingQ,
        pending,
        Object.hashAll(logs),
      );

  @override
  String toString() {
    final parts = <String>['S=$s'];
    if (p) parts.add('PENDING=$pending');
    parts.add('E=$e, U=$u, W=$w, Z=$z');
    parts.add('logs=${logs.length}');
    return 'ChannelChapterM(${parts.join(', ')})';
  }
}
