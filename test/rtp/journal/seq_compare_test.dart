import 'package:rtp_midi/src/rtp/journal/seq_compare.dart';
import 'package:test/test.dart';

void main() {
  group('seqAfter', () {
    test('a > b returns true', () {
      expect(seqAfter(10, 5), isTrue);
    });

    test('a == b returns false', () {
      expect(seqAfter(5, 5), isFalse);
    });

    test('a < b returns false', () {
      expect(seqAfter(3, 5), isFalse);
    });

    test('wrapping: 0 is after 65535', () {
      expect(seqAfter(0, 65535), isTrue);
    });

    test('wrapping: 1 is after 65535', () {
      expect(seqAfter(1, 65535), isTrue);
    });

    test('wrapping: 65535 is NOT after 0 (it is before)', () {
      expect(seqAfter(65535, 0), isFalse);
    });

    test('half-range: 32767 is after 0', () {
      expect(seqAfter(32767, 0), isTrue);
    });

    test('half-range: 32768 is NOT after 0 (too far ahead = behind)', () {
      expect(seqAfter(32768, 0), isFalse);
    });

    test('wrapping near boundary: 100 is after 65500', () {
      expect(seqAfter(100, 65500), isTrue);
    });

    test('wrapping near boundary: 65500 is NOT after 100', () {
      expect(seqAfter(65500, 100), isFalse);
    });

    test('consecutive: 1 is after 0', () {
      expect(seqAfter(1, 0), isTrue);
    });

    test('consecutive wrapping: 0 is after 65535', () {
      expect(seqAfter(0, 65535), isTrue);
    });

    test('large gap within half: 30000 is after 1', () {
      expect(seqAfter(30000, 1), isTrue);
    });

    test('large gap beyond half: 40000 is NOT after 1', () {
      expect(seqAfter(40000, 1), isFalse);
    });
  });

  group('seqAtOrAfter', () {
    test('a == b returns true', () {
      expect(seqAtOrAfter(5, 5), isTrue);
    });

    test('a > b returns true', () {
      expect(seqAtOrAfter(10, 5), isTrue);
    });

    test('a < b returns false', () {
      expect(seqAtOrAfter(3, 5), isFalse);
    });

    test('wrapping: 0 is at or after 65535', () {
      expect(seqAtOrAfter(0, 65535), isTrue);
    });
  });
}
