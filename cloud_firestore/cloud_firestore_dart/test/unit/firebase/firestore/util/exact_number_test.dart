// ExactNumber on long inputs (a Decimal128 value in a hostile bundle or
// snapshot JSON) and against a rational reference implementation.

import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exact_number.dart';
import 'package:test/test.dart';

/// The exact value of a finite decimal or double as a fraction.
(BigInt, BigInt) _rational(String decimal) {
  final RegExpMatch match = RegExp(
    r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
  ).firstMatch(decimal)!;
  final String fraction = match.group(3) ?? '';
  final String digits = '${match.group(2)}$fraction';
  final int exponent = int.parse(match.group(4) ?? '0') - fraction.length;
  BigInt numerator = BigInt.parse(digits.isEmpty ? '0' : digits);
  if (match.group(1) == '-') {
    numerator = -numerator;
  }
  if (exponent >= 0) {
    return (numerator * BigInt.from(10).pow(exponent), BigInt.one);
  }
  return (numerator, BigInt.from(10).pow(-exponent));
}

int _referenceCompare(String a, String b) {
  final (BigInt an, BigInt ad) = _rational(a);
  final (BigInt bn, BigInt bd) = _rational(b);
  return (an * bd).compareTo(bn * ad).sign;
}

void main() {
  test('long decimals are parsed, compared and hashed in linear time', () {
    // Before: 5 s for "1" and 100 000 zeros, 10 s for a million digits, both
    // quadratic. The bound is generous; the work takes milliseconds.
    final Stopwatch watch = Stopwatch()..start();
    final String zeros = '1${'0' * 1000000}';
    final String digits = '1' * 1000000;
    final String digits2 = '${'1' * 999999}2';

    final Decimal128Value a = Decimal128Value(zeros);
    final Decimal128Value b = Decimal128Value('1e1000000');
    expect(a, b);
    expect(a.hashCode, b.hashCode);

    final ExactNumber c = ExactNumber.parse(digits);
    final ExactNumber d = ExactNumber.parse(digits2);
    expect(c.compareTo(d), -1);
    expect(d.compareTo(c), 1);
    expect(c.compareTo(ExactNumber.parse('0.${digits2}e1000000')), -1);
    expect(c.compareTo(ExactNumber.parse('$digits.000')), 0);
    expect(c.decimalHashCode, ExactNumber.parse('$digits.000').decimalHashCode);

    // Of about the magnitude of a double.
    // (1e300 is not exact as a double; 0.5 is.)
    final ExactNumber e = ExactNumber.parse('5.${'0' * 1000000}1e-1');
    expect(e.compareTo(ExactNumber.fromDouble(0.5)), 1);
    expect(ExactNumber.fromDouble(0.5).compareTo(e), -1);
    expect(
      ExactNumber.parse(
        '5.${'0' * 1000000}e-1',
      ).compareTo(ExactNumber.fromDouble(0.5)),
      0,
    );
    expect(
      ExactNumber.parse(
        '0.${'0' * 1000000}1',
      ).compareTo(ExactNumber.fromInt(0)),
      1,
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('accepts the same strings as before', () {
    for (final String valid in <String>[
      '0',
      '-0',
      '+0',
      '007',
      '1.',
      '.5',
      '-.5',
      '1e5',
      '1E-5',
      '1.5e+3',
      '000.000',
      '1e999999999',
      'NaN',
      'Infinity',
      '+Infinity',
      '-Infinity',
    ]) {
      expect(() => ExactNumber.parse(valid), returnsNormally, reason: valid);
    }
    for (final String invalid in <String>[
      '',
      '-',
      '.',
      'e5',
      '1e',
      '1e+',
      '1e1234567890',
      ' 1',
      '1 ',
      '0x10',
      'nan',
      'inf',
      '1.2.3',
      '--1',
    ]) {
      expect(
        () => ExactNumber.parse(invalid),
        throwsFormatException,
        reason: invalid,
      );
    }
  });

  test('orders random decimals, integers and doubles like exact fractions', () {
    final Random random = Random(7);
    String randomDecimal() {
      final StringBuffer buffer = StringBuffer();
      if (random.nextBool()) {
        buffer.write('-');
      }
      buffer.write('0' * random.nextInt(3));
      for (int i = random.nextInt(40); i >= 0; i--) {
        buffer.write(random.nextInt(10));
      }
      if (random.nextBool()) {
        buffer.write('.');
        for (int i = random.nextInt(40); i >= 0; i--) {
          buffer.write(random.nextInt(10));
        }
        buffer.write('0' * random.nextInt(3));
      }
      if (random.nextBool()) {
        buffer.write('e${random.nextInt(80) - 40}');
      }
      return buffer.toString();
    }

    for (int i = 0; i < 3000; i++) {
      final String a = randomDecimal();
      final String b = random.nextInt(4) == 0 ? a : randomDecimal();
      final ExactNumber x = ExactNumber.parse(a);
      expect(
        x.compareTo(ExactNumber.parse(b)),
        _referenceCompare(a, b),
        reason: '$a <=> $b',
      );

      // Against a double and an integer near the decimal.
      final double asDouble = double.parse(a);
      if (asDouble.isFinite) {
        // The shortest string of a double that parses back to it is its exact
        // value only in decimal with enough digits; use the decimal expansion.
        final ExactNumber y = ExactNumber.fromDouble(asDouble);
        final String exact = _exactDecimalOfDouble(asDouble);
        expect(
          x.compareTo(y),
          _referenceCompare(a, exact),
          reason: '$a <=> $asDouble',
        );
        expect(
          y.compareTo(x),
          -_referenceCompare(a, exact),
          reason: '$asDouble <=> $a',
        );
      }
      final int asInt = random.nextInt(1 << 32) - (1 << 31);
      expect(
        x.compareTo(ExactNumber.fromInt(asInt)),
        _referenceCompare(a, '$asInt'),
        reason: '$a <=> $asInt',
      );
      if (x.compareTo(ExactNumber.parse(b)) == 0) {
        expect(x.decimalHashCode, ExactNumber.parse(b).decimalHashCode);
      }
    }
  });
}

/// The exact decimal expansion of a finite double.
String _exactDecimalOfDouble(double value) {
  if (value == 0) {
    return '0';
  }
  // value = m * 2^e with an integer m.
  int e = 0;
  double m = value.abs();
  while (m != m.truncateToDouble()) {
    m *= 2;
    e--;
  }
  BigInt mantissa = BigInt.from(m);
  final String sign = value < 0 ? '-' : '';
  if (e == 0) {
    return '$sign$mantissa';
  }
  // m / 2^k = m * 5^k / 10^k.
  mantissa *= BigInt.from(5).pow(-e);
  return '$sign${mantissa}e$e';
}
