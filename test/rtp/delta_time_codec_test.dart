import 'dart:typed_data';

import 'package:dart_rtp_midi/src/rtp/delta_time_codec.dart';
import 'package:test/test.dart';

void main() {
  group('encodeDeltaTime', () {
    test('zero encodes to single byte', () {
      expect(encodeDeltaTime(0), equals([0x00]));
    });

    test('values 0-127 encode to 1 byte', () {
      expect(encodeDeltaTime(0), equals([0x00]));
      expect(encodeDeltaTime(1), equals([0x01]));
      expect(encodeDeltaTime(127), equals([0x7F]));
    });

    test('128 encodes to 2 bytes', () {
      expect(encodeDeltaTime(128), equals([0x81, 0x00]));
    });

    test('values 128-16383 encode to 2 bytes', () {
      expect(encodeDeltaTime(128), equals([0x81, 0x00]));
      expect(encodeDeltaTime(255), equals([0x81, 0x7F]));
      expect(encodeDeltaTime(16383), equals([0xFF, 0x7F]));
    });

    test('16384 encodes to 3 bytes', () {
      expect(encodeDeltaTime(16384), equals([0x81, 0x80, 0x00]));
    });

    test('values 16384-2097151 encode to 3 bytes', () {
      expect(encodeDeltaTime(16384), equals([0x81, 0x80, 0x00]));
      expect(encodeDeltaTime(2097151), equals([0xFF, 0xFF, 0x7F]));
    });

    test('2097152 encodes to 4 bytes', () {
      expect(encodeDeltaTime(2097152), equals([0x81, 0x80, 0x80, 0x00]));
    });

    test('max 28-bit value encodes to 4 bytes', () {
      expect(
        encodeDeltaTime(0x0FFFFFFF),
        equals([0xFF, 0xFF, 0xFF, 0x7F]),
      );
    });
  });

  group('decodeDeltaTime', () {
    test('single byte value', () {
      final result = decodeDeltaTime(Uint8List.fromList([0x00]), 0)!;
      expect(result.value, equals(0));
      expect(result.bytesConsumed, equals(1));
    });

    test('single byte max (127)', () {
      final result = decodeDeltaTime(Uint8List.fromList([0x7F]), 0)!;
      expect(result.value, equals(127));
      expect(result.bytesConsumed, equals(1));
    });

    test('two byte value (128)', () {
      final result = decodeDeltaTime(Uint8List.fromList([0x81, 0x00]), 0)!;
      expect(result.value, equals(128));
      expect(result.bytesConsumed, equals(2));
    });

    test('two byte max (16383)', () {
      final result = decodeDeltaTime(Uint8List.fromList([0xFF, 0x7F]), 0)!;
      expect(result.value, equals(16383));
      expect(result.bytesConsumed, equals(2));
    });

    test('three byte value (16384)', () {
      final result =
          decodeDeltaTime(Uint8List.fromList([0x81, 0x80, 0x00]), 0)!;
      expect(result.value, equals(16384));
      expect(result.bytesConsumed, equals(3));
    });

    test('four byte value (2097152)', () {
      final result =
          decodeDeltaTime(Uint8List.fromList([0x81, 0x80, 0x80, 0x00]), 0)!;
      expect(result.value, equals(2097152));
      expect(result.bytesConsumed, equals(4));
    });

    test('four byte max', () {
      final result =
          decodeDeltaTime(Uint8List.fromList([0xFF, 0xFF, 0xFF, 0x7F]), 0)!;
      expect(result.value, equals(0x0FFFFFFF));
      expect(result.bytesConsumed, equals(4));
    });

    test('offset parameter', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0x81, 0x00, 0x00]);
      final result = decodeDeltaTime(bytes, 2)!;
      expect(result.value, equals(128));
      expect(result.bytesConsumed, equals(2));
    });

    test('returns null for empty data', () {
      expect(decodeDeltaTime(Uint8List(0), 0), isNull);
    });

    test('returns null for offset past end', () {
      expect(decodeDeltaTime(Uint8List.fromList([0x00]), 1), isNull);
    });

    test('returns null for truncated continuation', () {
      // Continuation bit set but no next byte
      expect(decodeDeltaTime(Uint8List.fromList([0x80]), 0), isNull);
    });
  });

  group('encode/decode roundtrip', () {
    test('boundary values', () {
      for (final value in [
        0,
        1,
        127,
        128,
        16383,
        16384,
        2097151,
        2097152,
        0x0FFFFFFF
      ]) {
        final encoded = encodeDeltaTime(value);
        final decoded = decodeDeltaTime(encoded, 0)!;
        expect(decoded.value, equals(value),
            reason: 'Failed roundtrip for $value');
        expect(decoded.bytesConsumed, equals(encoded.length));
      }
    });
  });
}
