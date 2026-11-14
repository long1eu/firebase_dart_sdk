// Fuzz: the input checks of Decimal128Value.
//
// Random decimal strings (signs, leading and trailing zeros, fractions,
// exponents around the decimal128 limits, digit counts around 34, NaN and the
// infinities, and text that is not a number) are checked against an oracle
// written here with BigInt, independently of ExactNumber: a string that is not
// a number, or a number that IEEE 754 decimal128 can not hold exactly, throws
// a FormatException; every other one is accepted, keeps its string, equals
// (with the same hash code) the same number spelled differently, and
// round-trips through the serializers.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Decimal128Value;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:test/test.dart';

import '../../util/property.dart';
import '../../util/property_model.dart';

final RemoteSerializer remote = RemoteSerializer(modelDatabaseId);

/// The largest coefficient of decimal128: 34 nines.
final BigInt maxCoefficient = BigInt.from(10).pow(34) - BigInt.one;
const int minExponent = -6176;
const int maxExponent = 6111;

/// What the oracle says about a string.
sealed class Expected {}

/// Not a decimal number at all.
class NotANumber extends Expected {
  @override
  String toString() => 'not a number';
}

/// NaN or an infinity.
class Special extends Expected {
  Special(this.text);

  final String text;

  @override
  String toString() => text;
}

/// A finite number: [coefficient] × 10^[exponent], normalized (no trailing
/// zeros in the coefficient; zero is 0 × 10^0).
class Finite extends Expected {
  Finite(this.negative, this.coefficient, int exponent)
    : exponent = coefficient == BigInt.zero ? 0 : exponent;

  final bool negative;
  final BigInt coefficient;
  final int exponent;

  /// Whether decimal128 holds the number exactly: a coefficient of at most 34
  /// digits and an exponent in [minExponent, maxExponent], possibly after
  /// moving digits between the two.
  bool get exact {
    if (coefficient == BigInt.zero) {
      return true;
    }
    if (coefficient > maxCoefficient || exponent < minExponent) {
      return false;
    }
    // A large exponent can be lowered by adding zeros to the coefficient.
    final int lower = exponent - maxExponent;
    if (lower <= 0) {
      return true;
    }
    // More than 34 digits after adding the zeros.
    return lower <= 34 &&
        coefficient * BigInt.from(10).pow(lower) <= maxCoefficient;
  }

  /// The same number spelled as `coefficientE exponent`.
  String get canonical => '${negative ? '-' : ''}${coefficient}E$exponent';

  @override
  String toString() =>
      '${negative ? '-' : ''}$coefficient e$exponent (${exact ? 'exact' : 'inexact'})';
}

final RegExp _grammar = RegExp(
  r'^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$',
);

/// The oracle: what [text] is.
Expected oracle(String text) {
  if (text == 'NaN' ||
      text == 'Infinity' ||
      text == '+Infinity' ||
      text == '-Infinity') {
    return Special(text);
  }
  final RegExpMatch? match = _grammar.firstMatch(text);
  if (match == null) {
    return NotANumber();
  }
  final String integer = match[2]!;
  final String fraction = match[3] ?? '';
  if (integer.isEmpty && fraction.isEmpty) {
    return NotANumber();
  }
  final String exponentText = match[4] ?? '0';
  // Exponents with many digits: only their value matters.
  final BigInt exponentValue = BigInt.parse(exponentText);
  BigInt coefficient = BigInt.parse('0$integer$fraction');
  BigInt exponent = exponentValue - BigInt.from(fraction.length);
  if (coefficient == BigInt.zero) {
    return Finite(match[1] == '-', BigInt.zero, 0);
  }
  while (coefficient % BigInt.from(10) == BigInt.zero) {
    coefficient = coefficient ~/ BigInt.from(10);
    exponent += BigInt.one;
  }
  // Far outside of the range: any int beyond it gives the same answer.
  final int clamped = exponent > BigInt.from(1 << 40)
      ? 1 << 40
      : exponent < BigInt.from(-(1 << 40))
      ? -(1 << 40)
      : exponent.toInt();
  return Finite(match[1] == '-', coefficient, clamped);
}

extension on Gen {
  String digits(int count, {bool leadingZeros = false}) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < count; i++) {
      buffer.write(
        i == 0 && !leadingZeros && count > 1 ? between(1, 9) : below(10),
      );
    }
    return buffer.toString();
  }

  /// A coefficient of around 34 significant digits, or of any length.
  String significant() {
    final int count = chance(60)
        ? between(32, 36)
        : chance(50)
        ? between(1, 5)
        : between(0, 80);
    final String nines = '9' * count;
    return pick(<String>[
      digits(count),
      nines,
      '1${'0' * count}',
      '${digits(count)}${'0' * below(40)}',
      '${'0' * below(10)}${digits(count)}',
    ]);
  }

  int exponentNear() =>
      pick(<int>[
        minExponent, minExponent - 1, minExponent + 1, maxExponent,
        maxExponent + 1,
        maxExponent - 1,
        6144,
        6145,
        6143,
        -6143,
        -6176 - 34, //
        -6176 + 34, 0, 1, -1, 34, -34,
      ]) +
      between(-40, 40);

  String decimalText() {
    switch (below(12)) {
      case 0:
        return pick(const <String>[
          'NaN', 'Infinity', '-Infinity', '+Infinity', '-NaN', 'nan', //
          'inf', 'Inf', 'infinity', '+NaN', 'NaN1', ' NaN',
        ]);
      case 1:
        // Not a number, or nearly one.
        return pick(<String>[
          '',
          '.',
          '-',
          '+',
          'e5',
          '1e',
          '1e+',
          '--1',
          '+-1',
          ' 1',
          '1 ',
          '0x10',
          '1_0',
          '1.2.3',
          '1e5e5',
          '١',
          '1,5',
          '∞',
          '1e5.5',
          '.e1',
          '1..',
          '-.',
          'E',
          '1E-',
          '1d',
          '1f',
        ]);
      case 2:
        // Exponents with leading zeros, or with many digits.
        return '${significant()}e${pick(const <String>['', '+', '-'])}'
            '${'0' * between(0, 12)}${between(0, 7000)}';
      case 3:
        return '${pick(const <String>['', '-', '+'])}0'
            '${chance(50) ? '.${'0' * below(20)}' : ''}'
            'e${pick(const <String>['', '-', '+'])}'
            '${chance(50) ? between(0, 99999999) : '9' * between(9, 30)}';
      default:
        final String sign = pick(const <String>['', '', '-', '+']);
        final String coefficient = significant();
        final int point = below(coefficient.length + 1);
        final String withPoint = chance(50)
            ? '${coefficient.substring(0, point)}.${coefficient.substring(point)}'
            : coefficient;
        if (chance(30)) {
          return '$sign$withPoint';
        }
        final int exponent = chance(70) ? exponentNear() : integer() >> 40;
        return '$sign$withPoint${pick(const <String>['e', 'E'])}'
            '${exponent >= 0 && chance(30) ? '+' : ''}$exponent';
    }
  }
}

void main() {
  test('Decimal128Value accepts exactly the values decimal128 holds', () {
    int exact = 0;
    int inexact = 0;
    int invalid = 0;
    forAll<String>(
      'decimal128 strings',
      count: cases(5000),
      generate: (Gen gen) => gen.decimalText(),
      show: (String text) => '"$text" (${oracle(text)})',
      check: (String text) {
        final Expected expected = oracle(text);
        Decimal128Value? value;
        Object? error;
        try {
          value = Decimal128Value(text);
          // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          error = e;
        }
        switch (expected) {
          case NotANumber():
            invalid++;
            expect(error, isFormatException, reason: 'not a number');
          case Finite(exact: false):
            inexact++;
            expect(error, isFormatException, reason: '$expected');
          case Finite(exact: true):
            exact++;
            expect(error, isNull, reason: '$expected');
            expect(value!.stringValue, text);
            final Decimal128Value canonical = Decimal128Value(
              expected.canonical,
            );
            expect(value, canonical);
            expect(value.hashCode, canonical.hashCode);
            expectRoundTrip(value);
          case Special():
            expect(error, isNull, reason: 'special $text');
            expectRoundTrip(value!);
        }
      },
    );
    // The cases cover all three answers.
    expect(exact, greaterThan(cases(5000) ~/ 10));
    expect(inexact, greaterThan(cases(5000) ~/ 10));
    expect(invalid, greaterThan(cases(5000) ~/ 50));
  });

  test('the oracle agrees with the documented examples', () {
    expect(
      oracle('1.0000000000000000000000000000000001'),
      isA<Finite>().having((Finite f) => f.exact, 'exact', isFalse),
    );
    expect((oracle('1e6145') as Finite).exact, isFalse);
    expect((oracle('1e-6177') as Finite).exact, isFalse);
    expect(
      (oracle('9999999999999999999999999999999999e6111') as Finite).exact,
      isTrue,
    );
    expect((oracle('1${'0' * 40}') as Finite).exact, isTrue);
    expect((oracle('1e-6176') as Finite).exact, isTrue);
  });
}

/// [value] goes through the user data converter and the remote serializer
/// unchanged.
void expectRoundTrip(Decimal128Value value) {
  final FieldValue model = toModel(value);
  final FieldValue decoded = remote.decodeValue(remote.encodeValue(model));
  expect(decoded, model);
  expect(decoded.compareTo(model), 0);
  expect((decoded.value as Decimal128Value).stringValue, value.stringValue);
}
