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
/// PORTING NOTE: the Android and JS SDKs convert every operand to a `Quadruple`
/// (a binary float with a 128-bit mantissa) for this. This class keeps the
/// exact value `mantissa * 2^exp2 * 10^exp10` instead, which orders every valid
/// 34-digit decimal128 the same way and needs no rounding.
class ExactNumber implements Comparable<ExactNumber> {
  ExactNumber._(
      this._kind, this._negative, this._mantissa, this._exp2, this._exp10);

  /// Creates the exact value of the integer [value].
  factory ExactNumber.fromInt(int value) {
    final BigInt big = BigInt.from(value);
    return ExactNumber._(_Kind.finite, value < 0, big.abs(), 0, 0);
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
    return ExactNumber._(_Kind.finite, negative, mantissa, exp2, 0);
  }

  /// Parses a decimal number. The supported format (no whitespace allowed) is:
  ///
  ///   * `NaN`
  ///   * `Infinity`, `+Infinity` or `-Infinity`
  ///   * `[+-]?[0-9]*(.[0-9]*)?([eE][+-]?[0-9]+)?` with at least one digit and
  ///     an exponent of at most 9 digits
  ///
  /// Throws a [FormatException] if [source] does not have this format.
  factory ExactNumber.parse(String source) {
    if (source == 'NaN') {
      return nan;
    } else if (source == '-Infinity') {
      return negativeInfinity;
    } else if (source == 'Infinity' || source == '+Infinity') {
      return positiveInfinity;
    }

    final int length = source.length;
    final StringBuffer digits = StringBuffer();
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
    while (i < length && _isDigit(source.codeUnitAt(i))) {
      digits.writeCharCode(source.codeUnitAt(i++));
    }
    if (i < length && source[i] == '.') {
      final int decimal = ++i;
      while (i < length && _isDigit(source.codeUnitAt(i))) {
        digits.writeCharCode(source.codeUnitAt(i++));
      }
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
    if (digits.isEmpty || i != length) {
      throw FormatException('Invalid number', source);
    }

    BigInt mantissa = BigInt.parse(digits.toString());
    // Normalize, so that equal values have the same representation.
    if (mantissa == BigInt.zero) {
      exponent = 0;
    } else {
      final BigInt ten = BigInt.from(10);
      while (mantissa.remainder(ten) == BigInt.zero) {
        mantissa = mantissa ~/ ten;
        exponent++;
      }
    }
    return ExactNumber._(_Kind.finite, negative, mantissa, 0, exponent);
  }

  static final ExactNumber nan =
      ExactNumber._(_Kind.nan, false, BigInt.zero, 0, 0);
  static final ExactNumber positiveInfinity =
      ExactNumber._(_Kind.positiveInfinity, false, BigInt.zero, 0, 0);
  static final ExactNumber negativeInfinity =
      ExactNumber._(_Kind.negativeInfinity, true, BigInt.zero, 0, 0);

  final _Kind _kind;
  final bool _negative;

  /// The absolute value is `_mantissa * 2^_exp2 * 10^_exp10`.
  final BigInt _mantissa;
  final int _exp2;
  final int _exp10;

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  bool get isNaN => _kind == _Kind.nan;

  bool get isInfinite =>
      _kind == _Kind.positiveInfinity || _kind == _Kind.negativeInfinity;

  /// Whether this is `0` or `-0`.
  bool get isZero => _kind == _Kind.finite && _mantissa == BigInt.zero;

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

  /// An estimate of the base 10 logarithm that is off by less than one.
  double get _approximateLog10 =>
      (_mantissa.bitLength + _exp2) * _log10Of2 + _exp10;

  /// Compares the absolute values of two finite numbers that are not zero.
  int _compareMagnitude(ExactNumber other) {
    // Numbers that are orders of magnitude apart are compared by their
    // magnitude, which keeps the powers below small.
    final double difference = _approximateLog10 - other._approximateLog10;
    if (difference > 2) {
      return 1;
    } else if (difference < -2) {
      return -1;
    }

    BigInt left = _mantissa;
    BigInt right = other._mantissa;
    final int exp2 = _exp2 - other._exp2;
    if (exp2 > 0) {
      left = left << exp2;
    } else {
      right = right << -exp2;
    }
    final int exp10 = _exp10 - other._exp10;
    if (exp10 > 0) {
      left = left * BigInt.from(10).pow(exp10);
    } else {
      right = right * BigInt.from(10).pow(-exp10);
    }
    return left.compareTo(right);
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
        return double.parse('${_negative ? '-' : ''}${_mantissa}e$_exp10');
    }
  }

  /// A hash that is the same for all the numbers [ExactNumber.parse] returns
  /// that compare as equal.
  int get decimalHashCode {
    if (_kind != _Kind.finite) {
      return _kind.hashCode;
    } else if (isZero) {
      return 0;
    }
    return Object.hash(_negative, _mantissa, _exp10);
  }
}
