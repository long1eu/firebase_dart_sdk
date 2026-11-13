// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:math' as math;
import 'dart:typed_data';

enum _Kind { nan, negativeInfinity, finite, positiveInfinity }

/// A number that is compared exactly, whichever of a 64-bit integer, a double
/// or a decimal string it was created from.
///
/// Firestore sorts all the number types together (64-bit integers, doubles,
/// 32-bit integers and 128-bit decimals). A decimal such as `0.1` has no exact
/// double representation, so the comparison can not go through `double`.
///
/// It keeps the exact value: a parsed decimal as its significant digits and a
/// power of ten, an integer or a double as `mantissa * 2^exp2` (turned into
/// decimal digits when two numbers of about the same magnitude are compared).
///
/// PORTING NOTE: the Android, iOS and JS SDKs convert decimal128 strings to a
/// `Quadruple` (a binary float with a 128-bit mantissa, rounded from at most
/// 59 significant digits, with an exponent range of about ±6.5e8 in base ten)
/// and accept any such string. The port accepts, in `Decimal128Value`, only
/// the strings that decimal128 holds exactly ([isDecimal128]), as the backend
/// does (it rejects the others with `invalid-argument`, verified on the
/// Enterprise emulator), and compares them exactly; for those values the
/// order is the same as upstream's.
///
/// The digits of a decimal are kept as a string: parsing, comparing and
/// hashing are linear in the length of the input. A [BigInt] of the digits
/// would make a long input (a hostile bundle) cost quadratic time.
class ExactNumber implements Comparable<ExactNumber> {
  ExactNumber._decimal(this._kind, this._negative, String digits, int exp10)
    : _binaryMantissa = null,
      _exp2 = 0,
      _decimalCache = (digits, exp10);

  ExactNumber._binary(this._negative, BigInt mantissa, this._exp2)
    : _kind = _Kind.finite,
      _binaryMantissa = mantissa,
      _decimalCache = null;

  /// Creates the exact value of the integer [value].
  factory ExactNumber.fromInt(int value) {
    final BigInt big = BigInt.from(value);
    return ExactNumber._binary(value < 0, big.abs(), 0);
  }

  /// Creates the exact value of the double [value].
  factory ExactNumber.fromDouble(double value) {
    if (value.isNaN) {
      return nan;
    } else if (value == double.infinity) {
      return positiveInfinity;
    } else if (value == double.negativeInfinity) {
      return negativeInfinity;
    }

    final ByteData data = ByteData(8)..setFloat64(0, value);
    final int high = data.getUint32(0);
    final int low = data.getUint32(4);
    final bool negative = (high & 0x80000000) != 0;
    final int biasedExponent = (high >> 20) & 0x7ff;
    BigInt mantissa = (BigInt.from(high & 0xfffff) << 32) | BigInt.from(low);
    int exp2;
    if (biasedExponent == 0) {
      // Subnormal numbers (and zero) have no implicit leading one.
      exp2 = -1074;
    } else {
      mantissa |= BigInt.one << 52;
      exp2 = biasedExponent - 1075;
    }
    return ExactNumber._binary(negative, mantissa, exp2);
  }

  /// Parses a decimal number. The supported format (no whitespace allowed) is:
  ///
  ///   * `NaN`
  ///   * `Infinity`, `+Infinity` or `-Infinity`
  ///   * `[+-]?[0-9]*(.[0-9]*)?([eE][+-]?[0-9]+)?` with at least one digit and
  ///     an exponent of at most 9 digits
  ///
  /// Throws a [FormatException] if [source] does not have this format.
  ///
  /// Linear in the length of [source].
  factory ExactNumber.parse(String source) {
    if (source == 'NaN') {
      return nan;
    } else if (source == '-Infinity') {
      return negativeInfinity;
    } else if (source == 'Infinity' || source == '+Infinity') {
      return positiveInfinity;
    }

    final int length = source.length;
    int i = 0;
    int exponent = 0;
    bool negative = false;
    if (i < length) {
      if (source[i] == '-') {
        negative = true;
        i++;
      } else if (source[i] == '+') {
        i++;
      }
    }
    final int integerStart = i;
    while (i < length && _isDigit(source.codeUnitAt(i))) {
      i++;
    }
    final String integer = source.substring(integerStart, i);
    String fraction = '';
    if (i < length && source[i] == '.') {
      final int decimal = ++i;
      while (i < length && _isDigit(source.codeUnitAt(i))) {
        i++;
      }
      fraction = source.substring(decimal, i);
      exponent = decimal - i;
    }
    if (i < length && (source[i] == 'e' || source[i] == 'E')) {
      int exponentValue = 0;
      i++;
      int exponentSign = 1;
      if (i < length) {
        if (source[i] == '-') {
          exponentSign = -1;
          i++;
        } else if (source[i] == '+') {
          i++;
        }
      }
      final int firstExponent = i;
      while (i < length && _isDigit(source.codeUnitAt(i))) {
        exponentValue = exponentValue * 10 + source.codeUnitAt(i++) - 0x30;
        if (i - firstExponent > 9) {
          throw FormatException('Exponent too large', source);
        }
      }
      if (i == firstExponent) {
        throw FormatException('Invalid number', source);
      }
      exponent += exponentValue * exponentSign;
    }
    if ((integer.isEmpty && fraction.isEmpty) || i != length) {
      throw FormatException('Invalid number', source);
    }

    final (String digits, int exp10) = _normalize(
      '$integer$fraction',
      exponent,
    );
    return ExactNumber._decimal(_Kind.finite, negative, digits, exp10);
  }

  /// The significant digits of `digits * 10^exponent`, without leading and
  /// trailing zeros, and the matching power of ten, so that equal values have
  /// the same representation. Zero is `('', 0)`.
  static (String, int) _normalize(String digits, int exponent) {
    int start = 0;
    while (start < digits.length && digits.codeUnitAt(start) == 0x30) {
      start++;
    }
    int end = digits.length;
    while (end > start && digits.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    if (start == end) {
      return ('', 0);
    }
    return (digits.substring(start, end), exponent + digits.length - end);
  }

  static final ExactNumber nan = ExactNumber._decimal(_Kind.nan, false, '', 0);
  static final ExactNumber positiveInfinity = ExactNumber._decimal(
    _Kind.positiveInfinity,
    false,
    '',
    0,
  );
  static final ExactNumber negativeInfinity = ExactNumber._decimal(
    _Kind.negativeInfinity,
    true,
    '',
    0,
  );

  final _Kind _kind;
  final bool _negative;

  /// The absolute value is `_binaryMantissa * 2^_exp2`, for numbers created
  /// from an integer or a double; null for parsed decimals.
  final BigInt? _binaryMantissa;
  final int _exp2;

  /// The absolute value as significant digits (no leading or trailing zeros,
  /// empty for zero) times a power of ten. Set by the parser, computed on
  /// demand for the others: a double has at most 767 significant digits.
  (String, int)? _decimalCache;

  (String, int) get _decimalForm => _decimalCache ??= _binaryToDecimal();

  (String, int) _binaryToDecimal() {
    final BigInt mantissa = _binaryMantissa!;
    if (_exp2 >= 0) {
      return _normalize((mantissa << _exp2).toString(), 0);
    }
    // 2^-k is 5^k / 10^k.
    return _normalize(
      (mantissa * BigInt.from(5).pow(-_exp2)).toString(),
      _exp2,
    );
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  bool get isNaN => _kind == _Kind.nan;

  bool get isInfinite =>
      _kind == _Kind.positiveInfinity || _kind == _Kind.negativeInfinity;

  /// Whether this is `0` or `-0`.
  bool get isZero {
    if (_kind != _Kind.finite) {
      return false;
    }
    final BigInt? mantissa = _binaryMantissa;
    return mantissa != null ? mantissa == BigInt.zero : _decimalForm.$1.isEmpty;
  }

  /// Whether the sign is negative, which is also true for `-0`.
  bool get isNegative => _negative;

  /// Orders the numbers the way Firestore does: NaN is equal to itself and
  /// smaller than every other number, and `-0` is equal to `0`.
  @override
  int compareTo(ExactNumber other) {
    if (isNaN || other.isNaN) {
      return isNaN ? (other.isNaN ? 0 : -1) : 1;
    }
    if (_kind != other._kind) {
      return _kind.index.compareTo(other._kind.index);
    }
    if (_kind != _Kind.finite) {
      return 0;
    }

    if (isZero || other.isZero) {
      if (isZero && other.isZero) {
        return 0;
      } else if (isZero) {
        return other._negative ? 1 : -1;
      } else {
        return _negative ? -1 : 1;
      }
    }
    if (_negative != other._negative) {
      return _negative ? -1 : 1;
    }
    final int magnitude = _compareMagnitude(other);
    return _negative ? -magnitude : magnitude;
  }

  static const double _log10Of2 = math.ln2 / math.ln10;

  /// An estimate of the base 10 logarithm of a number that is not zero, at
  /// most one above the true value.
  double get _approximateLog10 {
    final BigInt? mantissa = _binaryMantissa;
    if (mantissa != null) {
      return (mantissa.bitLength + _exp2) * _log10Of2;
    }
    final (String digits, int exp10) = _decimalForm;
    return (digits.length + exp10).toDouble();
  }

  /// Compares the absolute values of two finite numbers that are not zero.
  int _compareMagnitude(ExactNumber other) {
    // Numbers that are orders of magnitude apart are compared by their
    // magnitude, which keeps the conversions below small.
    final double difference = _approximateLog10 - other._approximateLog10;
    if (difference > 2) {
      return 1;
    } else if (difference < -2) {
      return -1;
    }

    // Both as `0.d1d2d3... * 10^point`: the larger point is the larger number,
    // otherwise the digits decide. With no trailing zeros, a longer string
    // whose start equals the shorter one is the larger number.
    final (String left, int leftExp10) = _decimalForm;
    final (String right, int rightExp10) = other._decimalForm;
    final int leftPoint = left.length + leftExp10;
    final int rightPoint = right.length + rightExp10;
    if (leftPoint != rightPoint) {
      return leftPoint.compareTo(rightPoint);
    }
    final int common = math.min(left.length, right.length);
    for (int i = 0; i < common; i++) {
      final int c = left.codeUnitAt(i) - right.codeUnitAt(i);
      if (c != 0) {
        return c.sign;
      }
    }
    return left.length.compareTo(right.length);
  }

  /// The closest double. Only meant for numbers created by [ExactNumber.parse].
  double toDouble() {
    switch (_kind) {
      case _Kind.nan:
        return double.nan;
      case _Kind.positiveInfinity:
        return double.infinity;
      case _Kind.negativeInfinity:
        return double.negativeInfinity;
      case _Kind.finite:
        if (isZero) {
          return _negative ? -0.0 : 0.0;
        }
        // The decimal exponent has at most 9 digits, anything beyond the range
        // of a double is an overflow or an underflow.
        if (_approximateLog10 > 400) {
          return _negative ? double.negativeInfinity : double.infinity;
        } else if (_approximateLog10 < -400) {
          return _negative ? -0.0 : 0.0;
        }
        final (String digits, int exp10) = _decimalForm;
        return double.parse('${_negative ? '-' : ''}${digits}e$exp10');
    }
  }

  /// The number of significant digits of decimal128.
  static const int decimal128Digits = 34;

  /// The smallest exponent of the last digit of a decimal128: the quantum of
  /// its smallest subnormal, `1e-6176`.
  static const int decimal128MinExponent = -6176;

  /// The largest exponent of the last digit of a decimal128: its largest
  /// finite value is `9.99...9e6144` (34 nines times `10^6111`).
  static const int decimal128MaxExponent = 6111;

  /// Whether IEEE 754 decimal128 holds this number exactly: NaN, an infinity,
  /// a zero (of any exponent), or a finite number of at most
  /// [decimal128Digits] significant digits (leading and trailing zeros do not
  /// count) whose last digit is not below `10^decimal128MinExponent` and that
  /// is not above `9.99...9e6144`.
  ///
  /// Matches what the backend accepts: `1.` with 40 zeros, `100e-6178`,
  /// `0.1e6145` and `0e7000` are exact, `1.` with 33 zeros and a `1`,
  /// `10e6144`, `1e-6177` and `1.234e-6174` are not.
  bool get isDecimal128 {
    if (_kind != _Kind.finite) {
      return true;
    }
    final (String digits, int exp10) = _decimalForm;
    if (digits.isEmpty) {
      return true;
    }
    return digits.length <= decimal128Digits &&
        exp10 >= decimal128MinExponent &&
        digits.length + exp10 <= decimal128Digits + decimal128MaxExponent;
  }

  /// A hash that is the same for all the numbers [ExactNumber.parse] returns
  /// that compare as equal.
  int get decimalHashCode {
    if (_kind != _Kind.finite) {
      return _kind.hashCode;
    } else if (isZero) {
      return 0;
    }
    final (String digits, int exp10) = _decimalForm;
    return Object.hash(_negative, digits, exp10);
  }
}
