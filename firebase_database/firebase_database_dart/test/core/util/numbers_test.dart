// Number rules of lib/src/core/util/numbers.dart. Valid on the VM and the web: no expectation
// depends on `is int` / `is double`, which mean nothing on the web.
import 'package:firebase_database_dart/src/core/util/numbers.dart';
import 'package:test/test.dart';

void main() {
  group('isIntegral', () {
    test('integral values within 2^53 are integers', () {
      expect(isIntegral(0), isTrue);
      expect(isIntegral(1.0), isTrue);
      expect(isIntegral(-42), isTrue);
      expect(isIntegral(maxSafeInteger), isTrue);
      expect(isIntegral(-maxSafeInteger), isTrue);
      expect(isIntegral(-0.0), isTrue);
    });

    test('fractions, 2^53 and beyond, NaN and infinities are not', () {
      expect(isIntegral(1.5), isFalse);
      expect(isIntegral(9007199254740992.0), isFalse);
      expect(isIntegral(-9007199254740992.0), isFalse);
      expect(isIntegral(1e21), isFalse);
      expect(isIntegral(double.nan), isFalse);
      expect(isIntegral(double.infinity), isFalse);
      expect(isIntegral(double.negativeInfinity), isFalse);
    });
  });

  group('normalizeNumber', () {
    test('integral doubles become integers with the same value', () {
      final num n = normalizeNumber(3.0);
      expect(n, 3);
      expect(n.toString(), '3');
    });

    test('fractions and large values stay doubles', () {
      expect(normalizeNumber(1.5), 1.5);
      expect(normalizeNumber(1e21).toString(), '1e+21');
    });

    test('a negative zero from the server stays a negative zero', () {
      final num n = normalizeNumber(-0.0);
      expect(n, 0);
      expect(n.isNegative, isTrue);
      expect(doubleToIeee754String(n.toDouble()), '8000000000000000');
    });

    test('positive zero is zero', () {
      expect(normalizeNumber(0.0), 0);
      expect(normalizeNumber(0.0).isNegative, isFalse);
    });

    test('an int beyond 2^53 stays the same int on the VM', () {
      // The server stores 64-bit integers exactly (measured: 9007199254740993 and int64 max
      // round-trip). On the web the literal is already the nearest double.
      // Parsed at run time: dart2js refuses the literal.
      final int big = int.parse('9007199254740993');
      expect(identical(normalizeNumber(big), big), isTrue);
      expect(normalizeNumber(big).toString(), big.toString());
      expect(tryParseJsonNumber('9007199254740993'), big);
      // A double beyond the safe range stays a double.
      expect(
        normalizeNumber(9007199254740992.0).toString(),
        9007199254740992.0.toString(),
      );
    });

    test('a negative zero from the user becomes zero', () {
      final num n = normalizeUserNumber(-0.0);
      expect(n, 0);
      expect(n.isNegative, isFalse);
      expect(doubleToIeee754String(n.toDouble()), '0000000000000000');
      expect(normalizeUserNumber(2.0), 2);
      expect(normalizeUserNumber(2.5), 2.5);
    });
  });

  test('isInvalidJsonNumber', () {
    expect(isInvalidJsonNumber(double.nan), isTrue);
    expect(isInvalidJsonNumber(double.infinity), isTrue);
    expect(isInvalidJsonNumber(double.negativeInfinity), isTrue);
    expect(isInvalidJsonNumber(1.5), isFalse);
    expect(isInvalidJsonNumber(1), isFalse);
    expect(isInvalidJsonNumber('NaN'), isFalse);
    expect(isInvalidJsonNumber(null), isFalse);
  });

  test('doubleToIeee754String gives the big-endian bits', () {
    expect(doubleToIeee754String(1.0), '3ff0000000000000');
    expect(doubleToIeee754String(0.0), '0000000000000000');
    expect(doubleToIeee754String(-0.0), '8000000000000000');
    expect(doubleToIeee754String(0.1), '3fb999999999999a');
    expect(doubleToIeee754String(-2.5), 'c004000000000000');
    expect(doubleToIeee754String(1e21), '444b1ae4d6e2ef50');
    expect(doubleToIeee754String(5e-324), '0000000000000001');
  });

  group('tryParseIntKey', () {
    test('accepts integer-like keys within int32', () {
      expect(tryParseIntKey('0'), 0);
      expect(tryParseIntKey('7'), 7);
      expect(tryParseIntKey('-7'), -7);
      expect(tryParseIntKey('2147483647'), int32Max);
      expect(tryParseIntKey('-2147483648'), int32Min);
    });

    test('accepts leading zeros and -0, as JS tryParseInt', () {
      expect(tryParseIntKey('01'), 1);
      expect(tryParseIntKey('007'), 7);
      expect(tryParseIntKey('-0'), 0);
      expect(tryParseIntKey('-0')!.isNegative, isFalse);
      expect(tryParseIntKey('0000000000000000001'), 1);
      expect(tryParseIntKey('00403311635'), 403311635);
    });

    test('refuses everything else', () {
      expect(tryParseIntKey(''), isNull);
      expect(tryParseIntKey('-'), isNull);
      expect(tryParseIntKey('2147483648'), isNull);
      expect(tryParseIntKey('-2147483649'), isNull);
      expect(tryParseIntKey('12345678901'), isNull);
      expect(tryParseIntKey('1.0'), isNull);
      expect(tryParseIntKey('1e3'), isNull);
      expect(tryParseIntKey('+1'), isNull);
      expect(tryParseIntKey(' 1'), isNull);
      expect(tryParseIntKey('1 '), isNull);
      expect(tryParseIntKey('0x10'), isNull);
      expect(tryParseIntKey('--1'), isNull);
      expect(tryParseIntKey('a'), isNull);
      expect(tryParseIntKey('١'), isNull); // Arabic-Indic one.
    });
  });

  group('tryParseJsonNumber', () {
    test('accepts the Java forms the server sends', () {
      expect(tryParseJsonNumber('1.0E21'), 1e21);
      expect(isIntegral(tryParseJsonNumber('1.0E21')!), isFalse);
      expect(tryParseJsonNumber('4.9E-324'), 5e-324);
      expect(tryParseJsonNumber('1.0'), 1);
      expect(tryParseJsonNumber('1e3'), 1000);
      expect(tryParseJsonNumber('-2.5'), -2.5);
      expect(tryParseJsonNumber('12'), 12);
    });

    test('keeps a negative zero', () {
      expect(tryParseJsonNumber('-0')!.isNegative, isTrue);
      expect(tryParseJsonNumber('-0.0')!.isNegative, isTrue);
    });

    test('refuses non-JSON forms', () {
      expect(tryParseJsonNumber(''), isNull);
      expect(tryParseJsonNumber('NaN'), isNull);
      expect(tryParseJsonNumber('Infinity'), isNull);
      expect(tryParseJsonNumber('1e400'), isNull);
      expect(tryParseJsonNumber('0x10'), isNull);
      expect(tryParseJsonNumber('+1'), isNull);
      expect(tryParseJsonNumber('.5'), isNull);
      expect(tryParseJsonNumber(' 1'), isNull);
    });
  });
}
