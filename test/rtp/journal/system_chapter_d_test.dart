import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/journal/system_chapter_d.dart';
import 'package:test/test.dart';

void main() {
  group('SystemChapterD', () {
    test('encode produces 1 byte minimum (header only)', () {
      const chapter = SystemChapterD();
      expect(chapter.encode().length, equals(1));
    });

    test('roundtrip with flags only (no sub-logs)', () {
      const original = SystemChapterD(s: true);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded, equals(original));
      expect(consumed, equals(1));
    });

    test('S flag at bit 7', () {
      const chapter = SystemChapterD(s: true);
      expect(chapter.encode()[0] & 0x80, equals(0x80));
    });

    test('B flag at bit 6 (Reset)', () {
      final chapter = SystemChapterD(
        b: true,
        logData: Uint8List.fromList([0x03]), // S=0, COUNT=3
      );
      expect(chapter.encode()[0] & 0x40, equals(0x40));
    });

    test('G flag at bit 5 (Tune Request)', () {
      final chapter = SystemChapterD(
        g: true,
        logData: Uint8List.fromList([0x01]), // S=0, COUNT=1
      );
      expect(chapter.encode()[0] & 0x20, equals(0x20));
    });

    test('H flag at bit 4 (Song Select)', () {
      final chapter = SystemChapterD(
        h: true,
        logData: Uint8List.fromList([0x05]), // S=0, VALUE=5
      );
      expect(chapter.encode()[0] & 0x10, equals(0x10));
    });

    test('J flag at bit 3 (0xF4)', () {
      final chapter = SystemChapterD(
        j: true,
        logData: Uint8List.fromList([0x00, 0x02]), // 10-bit LENGTH=2 (min)
      );
      expect(chapter.encode()[0] & 0x08, equals(0x08));
    });

    test('K flag at bit 2 (0xF5)', () {
      final chapter = SystemChapterD(
        k: true,
        logData: Uint8List.fromList([0x00, 0x02]), // 10-bit LENGTH=2 (min)
      );
      expect(chapter.encode()[0] & 0x04, equals(0x04));
    });

    test('Y flag at bit 1 (0xF9)', () {
      final chapter = SystemChapterD(
        y: true,
        logData: Uint8List.fromList([0x01]), // 5-bit LENGTH=1 (min)
      );
      expect(chapter.encode()[0] & 0x02, equals(0x02));
    });

    test('Z flag at bit 0 (0xFD)', () {
      final chapter = SystemChapterD(
        z: true,
        logData: Uint8List.fromList([0x01]), // 5-bit LENGTH=1 (min)
      );
      expect(chapter.encode()[0] & 0x01, equals(0x01));
    });

    test('decode returns null for empty data', () {
      expect(SystemChapterD.decode(Uint8List(0)), isNull);
    });

    test('roundtrip with Reset log (B flag, 1 byte)', () {
      final logData = Uint8List.fromList([0x05]); // S=0, COUNT=5
      final original = SystemChapterD(b: true, logData: logData);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.b, isTrue);
      expect(consumed, equals(2)); // 1 header + 1 reset log
    });

    test('roundtrip with Tune Request log (G flag, 1 byte)', () {
      final logData = Uint8List.fromList([0x83]); // S=1, COUNT=3
      final original = SystemChapterD(g: true, logData: logData);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.g, isTrue);
      expect(consumed, equals(2)); // 1 header + 1 tune request log
    });

    test('roundtrip with Song Select log (H flag, 1 byte)', () {
      final logData = Uint8List.fromList([0x42]); // S=0, VALUE=66
      final original = SystemChapterD(h: true, logData: logData);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.h, isTrue);
      expect(consumed, equals(2)); // 1 header + 1 song select log
    });

    test('roundtrip with 0xF4 undefined syscom (J flag, 2+ bytes)', () {
      // Syscom header: S=0, C=0, V=0, L=0, DSZ=0, LENGTH=2 (minimum)
      final logData = Uint8List.fromList([0x00, 0x02]);
      final original = SystemChapterD(j: true, logData: logData);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.j, isTrue);
      expect(consumed, equals(3)); // 1 header + 2 syscom log
    });

    test('roundtrip with 0xF9 undefined sysreal (Y flag, 1+ bytes)', () {
      // Sysreal header: S=0, C=0, L=0, LENGTH=1 (minimum)
      final logData = Uint8List.fromList([0x01]);
      final original = SystemChapterD(y: true, logData: logData);
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.y, isTrue);
      expect(consumed, equals(2)); // 1 header + 1 sysreal log
    });

    test('roundtrip with B, G, H together (all 1-byte logs)', () {
      // B: S=0, COUNT=1; G: S=0, COUNT=2; H: S=0, VALUE=10
      final logData = Uint8List.fromList([0x01, 0x02, 0x0A]);
      final original = SystemChapterD(
        b: true,
        g: true,
        h: true,
        logData: logData,
      );
      final bytes = original.encode();
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.b, isTrue);
      expect(decoded.g, isTrue);
      expect(decoded.h, isTrue);
      expect(consumed, equals(4)); // 1 header + 3 one-byte logs
    });

    test('decode with offset', () {
      final bytes = Uint8List.fromList([
        0xFF, // padding
        0x80, // S=1, no sub-logs
      ]);
      final (decoded, consumed) = SystemChapterD.decode(bytes, 1)!;
      expect(decoded.s, isTrue);
      expect(consumed, equals(1));
    });

    test('decode returns null when B set but no log data', () {
      final bytes = Uint8List.fromList([0x40]); // B=1, no log bytes
      expect(SystemChapterD.decode(bytes), isNull);
    });

    test('decode returns null when J set but only 1 log byte', () {
      // J needs 2-byte syscom header
      final bytes = Uint8List.fromList([0x08, 0x00]); // J=1, only 1 log byte
      expect(SystemChapterD.decode(bytes), isNull);
    });

    test('known binary vector: Reset only', () {
      // B=1, Reset log: S=0, COUNT=7
      final bytes = Uint8List.fromList([0x40, 0x07]);
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.b, isTrue);
      expect(decoded.g, isFalse);
      expect(consumed, equals(2));
      // Log data is the reset byte
      expect(decoded.logData![0], equals(0x07));
    });

    test('known binary vector: B, G, and H together', () {
      // B=1, G=1, H=1 → 0x70
      // Reset: COUNT=1, Tune Request: COUNT=3, Song Select: VALUE=42
      final bytes = Uint8List.fromList([
        0x70, // B=1, G=1, H=1
        0x01, // Reset: S=0, COUNT=1
        0x03, // Tune Request: S=0, COUNT=3
        0x2A, // Song Select: S=0, VALUE=42
      ]);
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.b, isTrue);
      expect(decoded.g, isTrue);
      expect(decoded.h, isTrue);
      expect(consumed, equals(4));
    });

    test('syscom log with LENGTH > 2', () {
      // J=1, syscom header: S=0, C=1, V=0, L=0, DSZ=0, LENGTH=3
      // Then 1 byte COUNT
      final bytes = Uint8List.fromList([
        0x08, // J=1
        0x40, 0x03, // S=0, C=1, LENGTH=3
        0x05, // COUNT=5
      ]);
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.j, isTrue);
      expect(consumed, equals(4)); // 1 header + 3 syscom log
    });

    test('sysreal log with LENGTH > 1', () {
      // Y=1, sysreal header: S=0, C=1, L=0, LENGTH=2
      // Then 1 byte COUNT
      final bytes = Uint8List.fromList([
        0x02, // Y=1
        0x42, // S=0, C=1, L=0, LENGTH=2
        0x0A, // COUNT=10
      ]);
      final (decoded, consumed) = SystemChapterD.decode(bytes)!;
      expect(decoded.y, isTrue);
      expect(consumed, equals(3)); // 1 header + 2 sysreal log
    });

    test('equality', () {
      const a = SystemChapterD(s: true, b: true);
      const b = SystemChapterD(s: true, b: true);
      const c = SystemChapterD(s: true, g: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('equality includes logData', () {
      final a = SystemChapterD(
        b: true,
        logData: Uint8List.fromList([1]),
      );
      final b = SystemChapterD(
        b: true,
        logData: Uint8List.fromList([2]),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
