// Decimal arithmetic for the 128-bit decimal values of Enterprise edition
// databases, as far as local pipeline evaluation needs it.

import 'dart:math' as math;
import 'dart:typed_data';

/// A decimal floating point number with the precision of IEEE 754
/// decimal128: 34 significant digits, rounded half to even.
///
/// The value is `(negative ? -1 : 1) * coefficient * 10^exponent`. This is not
/// a complete decimal128 implementation: exponents are not clamped to the
/// range of the format (results far outside of it can not be told apart from
/// what the backend would return as infinity or zero).
///
/// Exponents may still be huge (a parsed value may carry a nine-digit one),
/// so no operation scales a coefficient by more than [_maxShift] digits:
/// when the exponents of two operands differ by more, the smaller operand
/// only matters for rounding, comparison or a remainder, and is handled
/// without aligning the two (see [operator +], [compareTo], [remainder]).
/// Below that difference results are computed exactly as before.
class Decimal {
  Decimal._(this._kind, this.negative, this.coefficient, this.exponent);

  factory Decimal.finite(BigInt coefficient, int exponent, {bool? negative}) {
    final bool isNegative = negative ?? coefficient.isNegative;
    return Decimal._(
      _DecimalKind.finite,
      isNegative,
      coefficient.abs(),
      exponent,
    )._rounded();
  }

  factory Decimal.fromInt(int value) => Decimal.finite(BigInt.from(value), 0);

  /// The exact value of [value], rounded to 34 digits.
  factory Decimal.fromDouble(double value) {
    if (value.isNaN) {
      return nan;
    } else if (value.isInfinite) {
      return value.isNegative ? negativeInfinity : infinity;
    } else if (value == 0) {
      return Decimal._(_DecimalKind.finite, value.isNegative, BigInt.zero, 0);
    }
    // The exact value of the double (every double is a finite decimal
    // fraction), which is then rounded to 34 digits.
    final ByteData data = ByteData(8)..setFloat64(0, value);
    final int high = data.getUint32(0);
    final int low = data.getUint32(4);
    final int biasedExponent = (high >> 20) & 0x7ff;
    BigInt mantissa = (BigInt.from(high & 0xfffff) << 32) | BigInt.from(low);
    int exp2;
    if (biasedExponent == 0) {
      exp2 = -1074;
    } else {
      mantissa |= BigInt.one << 52;
      exp2 = biasedExponent - 1075;
    }
    if (exp2 >= 0) {
      return Decimal.finite(mantissa << exp2, 0, negative: value.isNegative);
    }
    // 2^-k is 5^k / 10^k.
    return Decimal.finite(
      mantissa * BigInt.from(5).pow(-exp2),
      exp2,
      negative: value.isNegative,
    );
  }

  /// Parses `[+-]digits[.digits][e[+-]digits]`, `NaN` and `[+-]Infinity`.
  factory Decimal.parse(String source) {
    final String text = source.trim();
    final String lower = text.toLowerCase();
    if (lower == 'nan' || lower == '+nan' || lower == '-nan') {
      return nan;
    } else if (lower == 'infinity' || lower == '+infinity' || lower == 'inf') {
      return infinity;
    } else if (lower == '-infinity' || lower == '-inf') {
      return negativeInfinity;
    }
    final RegExpMatch? match = _number.firstMatch(text);
    if (match == null) {
      throw FormatException('Not a decimal number', source);
    }
    final String integer = match.group(2) ?? '';
    final String fraction = match.group(3) ?? '';
    if (integer.isEmpty && fraction.isEmpty) {
      throw FormatException('Not a decimal number', source);
    }
    final int exponent = int.parse(match.group(4) ?? '0') - fraction.length;
    return Decimal._(
      _DecimalKind.finite,
      match.group(1) == '-',
      BigInt.parse('$integer$fraction'),
      exponent,
    )._rounded();
  }

  static final RegExp _number = RegExp(
    r'^([+-])?(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
  );

  static final Decimal nan = Decimal._(_DecimalKind.nan, false, BigInt.zero, 0);
  static final Decimal infinity = Decimal._(
    _DecimalKind.infinity,
    false,
    BigInt.zero,
    0,
  );
  static final Decimal negativeInfinity = Decimal._(
    _DecimalKind.infinity,
    true,
    BigInt.zero,
    0,
  );

  /// The number of significant digits of decimal128.
  static const int precision = 34;

  static final BigInt _ten = BigInt.from(10);
  static final BigInt _limit = _ten.pow(precision);

  final _DecimalKind _kind;
  final bool negative;
  final BigInt coefficient;
  final int exponent;

  bool get isNaN => _kind == _DecimalKind.nan;
  bool get isInfinite => _kind == _DecimalKind.infinity;
  bool get isFinite => _kind == _DecimalKind.finite;
  bool get isZero => isFinite && coefficient == BigInt.zero;

  /// The signed coefficient.
  BigInt get _signed => negative ? -coefficient : coefficient;

  /// Rounds the coefficient to [precision] digits, half to even.
  Decimal _rounded() {
    if (!isFinite || coefficient < _limit) {
      return this;
    }
    final int excess = coefficient.toString().length - precision;
    final BigInt divisor = _ten.pow(excess);
    BigInt quotient = coefficient ~/ divisor;
    final BigInt remainder = coefficient % divisor;
    final int half = (remainder * BigInt.two).compareTo(divisor);
    if (half > 0 || (half == 0 && quotient.isOdd)) {
      quotient += BigInt.one;
    }
    // Rounding up may have added a digit (99...9 -> 100...0).
    return Decimal._(
      _DecimalKind.finite,
      negative,
      quotient,
      exponent + excess,
    )._rounded();
  }

  /// The most digits a coefficient is scaled by to align two operands: two
  /// full coefficients and the guard digits of rounding. Beyond it the
  /// operations take the shortcuts of [_farApart].
  static const int _maxShift = 2 * precision + 4;

  /// The number of digits of the coefficient.
  int get _digits => coefficient.toString().length;

  /// The exponent of the leading digit.
  int get _adjusted => exponent + _digits - 1;

  /// Whether aligning [a] and [b] would scale by more than [_maxShift] digits.
  static bool _farApart(Decimal a, Decimal b) =>
      (a.exponent - b.exponent).abs() > _maxShift;

  /// Both coefficients (signed) at the smaller of the two exponents. Only for
  /// operands that are not [_farApart].
  static (BigInt, BigInt, int) _aligned(Decimal a, Decimal b) {
    assert(!_farApart(a, b));
    final int exponent = a.exponent < b.exponent ? a.exponent : b.exponent;
    return (
      a._signed * _ten.pow(a.exponent - exponent),
      b._signed * _ten.pow(b.exponent - exponent),
      exponent,
    );
  }

  Decimal operator -() =>
      isNaN ? this : Decimal._(_kind, !negative, coefficient, exponent);

  Decimal abs() =>
      negative ? Decimal._(_kind, false, coefficient, exponent) : this;

  Decimal operator +(Decimal other) {
    if (isNaN || other.isNaN) {
      return nan;
    } else if (isInfinite) {
      return other.isInfinite && other.negative != negative ? nan : this;
    } else if (other.isInfinite) {
      return other;
    }
    if (_farApart(this, other)) {
      return _sumFarApart(this, other);
    }
    final (BigInt a, BigInt b, int exponent) = _aligned(this, other);
    final BigInt sum = a + b;
    if (sum == BigInt.zero) {
      return Decimal._(
        _DecimalKind.finite,
        negative && other.negative,
        BigInt.zero,
        exponent,
      );
    }
    return Decimal.finite(sum, exponent);
  }

  /// The sum of finite [a] and [b] whose exponents are [_farApart], as the
  /// exact sum rounded to [precision] digits would be.
  static Decimal _sumFarApart(Decimal a, Decimal b) {
    final Decimal high = a.exponent > b.exponent ? a : b;
    final Decimal low = identical(high, a) ? b : a;
    if (high.isZero && low.isZero) {
      return Decimal._(
        _DecimalKind.finite,
        a.negative && b.negative,
        BigInt.zero,
        low.exponent,
      );
    } else if (high.isZero) {
      // The zero only lowers the ideal exponent, which [low] already has.
      return low;
    } else if (low.isZero) {
      // [high] scaled down to the smaller exponent as far as the precision
      // allows: the exact sum has more than [precision] digits.
      final int shift = precision - high._digits;
      return Decimal._(
        _DecimalKind.finite,
        high.negative,
        high.coefficient * _ten.pow(shift),
        high.exponent - shift,
      );
    }
    // |low| is below one unit in the last of [precision] + 2 guard digits
    // under [high]: it only decides the rounding, as a sticky digit does.
    const int guard = precision + 2;
    final BigInt sticky = low.negative ? -BigInt.one : BigInt.one;
    return Decimal.finite(
      high._signed * _ten.pow(guard) + sticky,
      high.exponent - guard,
    );
  }

  Decimal operator -(Decimal other) => this + (-other);

  Decimal operator *(Decimal other) {
    if (isNaN || other.isNaN) {
      return nan;
    }
    final bool sign = negative != other.negative;
    if (isInfinite || other.isInfinite) {
      if (isZero || other.isZero) {
        return nan;
      }
      return sign ? negativeInfinity : infinity;
    }
    return Decimal.finite(
      coefficient * other.coefficient,
      exponent + other.exponent,
      negative: sign,
    );
  }

  Decimal operator /(Decimal other) {
    if (isNaN || other.isNaN) {
      return nan;
    }
    final bool sign = negative != other.negative;
    if (isInfinite) {
      return other.isInfinite ? nan : (sign ? negativeInfinity : infinity);
    } else if (other.isInfinite) {
      return Decimal._(_DecimalKind.finite, sign, BigInt.zero, 0);
    } else if (other.isZero) {
      return isZero ? nan : (sign ? negativeInfinity : infinity);
    } else if (isZero) {
      return Decimal._(
        _DecimalKind.finite,
        sign,
        BigInt.zero,
        exponent - other.exponent,
      );
    }
    // Enough extra digits for a correctly rounded 34-digit quotient: the
    // sticky digit keeps an inexact tail from looking like an exact half.
    final int shift =
        precision +
        3 +
        other.coefficient.toString().length -
        coefficient.toString().length;
    final int scale = shift > 0 ? shift : 0;
    final BigInt dividend = coefficient * _ten.pow(scale);
    BigInt quotient = dividend ~/ other.coefficient;
    int resultExponent = exponent - other.exponent - scale;
    final bool exact = dividend % other.coefficient == BigInt.zero;
    if (!exact) {
      quotient = quotient * _ten + BigInt.one;
      resultExponent -= 1;
    }
    Decimal result = Decimal.finite(quotient, resultExponent, negative: sign);
    if (exact) {
      // An exact quotient has the ideal exponent: trailing zeros go away.
      final int ideal = exponent - other.exponent;
      BigInt c = result.coefficient;
      int e = result.exponent;
      while (e < ideal && c != BigInt.zero && c % _ten == BigInt.zero) {
        c ~/= _ten;
        e += 1;
      }
      result = Decimal._(_DecimalKind.finite, sign, c, e);
    }
    return result;
  }

  /// The remainder of the division truncated toward zero: it has the sign
  /// of this number.
  Decimal remainder(Decimal other) {
    if (isNaN || other.isNaN || isInfinite || other.isZero) {
      return nan;
    } else if (other.isInfinite) {
      return this;
    }
    if (_farApart(this, other)) {
      if (isZero) {
        // A zero remainder has the smaller exponent.
        return Decimal._(
          _DecimalKind.finite,
          negative,
          BigInt.zero,
          math.min(this.exponent, other.exponent),
        );
      } else if (this.exponent < other.exponent) {
        // |this| < |other|: the remainder is this number.
        return this;
      }
      // (c * 10^d) mod m without building 10^d.
      final BigInt m = other.coefficient;
      final BigInt rem =
          (coefficient *
              _ten.modPow(BigInt.from(this.exponent - other.exponent), m)) %
          m;
      if (rem == BigInt.zero) {
        return Decimal._(
          _DecimalKind.finite,
          negative,
          BigInt.zero,
          other.exponent,
        );
      }
      return Decimal.finite(rem, other.exponent, negative: negative);
    }
    final (BigInt a, BigInt b, int exponent) = _aligned(this, other);
    final BigInt rem = a.remainder(b);
    if (rem == BigInt.zero) {
      return Decimal._(_DecimalKind.finite, negative, BigInt.zero, exponent);
    }
    return Decimal.finite(rem, exponent);
  }

  /// This number with [digits] digits after the decimal point (a negative
  /// count rounds to the left of it), rounded with [mode].
  Decimal roundTo(int digits, DecimalRounding mode) {
    if (!isFinite || exponent >= -digits) {
      return this;
    }
    final int drop = -digits - exponent;
    if (drop > coefficient.toString().length + 1) {
      // Everything is rounded away.
      final bool up = switch (mode) {
        DecimalRounding.ceiling => !negative && !isZero,
        DecimalRounding.floor => negative && !isZero,
        _ => false,
      };
      return Decimal._(
        _DecimalKind.finite,
        negative,
        up ? BigInt.one : BigInt.zero,
        -digits,
      );
    }
    final BigInt divisor = _ten.pow(drop);
    BigInt quotient = coefficient ~/ divisor;
    final BigInt rem = coefficient % divisor;
    final bool inexact = rem != BigInt.zero;
    final bool up = switch (mode) {
      DecimalRounding.down => false,
      DecimalRounding.halfUp => (rem * BigInt.two).compareTo(divisor) >= 0,
      DecimalRounding.ceiling => inexact && !negative,
      DecimalRounding.floor => inexact && negative,
    };
    if (up) {
      quotient += BigInt.one;
    }
    return Decimal._(
      _DecimalKind.finite,
      negative,
      quotient,
      -digits,
    )._rounded();
  }

  /// The square root, correctly rounded down to 34 digits. NaN for a
  /// negative number.
  Decimal sqrt() {
    if (isNaN || (negative && !isZero)) {
      return nan;
    } else if (isInfinite || isZero) {
      return this;
    }
    // Scale to an even exponent and enough digits for 34 digits of root.
    int e = exponent;
    BigInt c = coefficient;
    int scale = 2 * (precision + 2) - c.toString().length;
    if (scale < 0) {
      scale = 0;
    }
    if ((e - scale).isOdd) {
      scale += 1;
    }
    c *= _ten.pow(scale);
    e -= scale;
    final BigInt root = _isqrt(c);
    final bool exact = root * root == c;
    Decimal result = Decimal.finite(
      exact ? root : root * _ten + BigInt.one,
      exact ? e ~/ 2 : e ~/ 2 - 1,
    );
    if (exact) {
      BigInt rc = result.coefficient;
      int re = result.exponent;
      final int ideal = (exponent / 2).floor();
      while (re < ideal && rc % _ten == BigInt.zero && rc != BigInt.zero) {
        rc ~/= _ten;
        re += 1;
      }
      result = Decimal._(_DecimalKind.finite, false, rc, re);
    }
    return result;
  }

  static BigInt _isqrt(BigInt n) {
    if (n < BigInt.two) {
      return n;
    }
    BigInt x = BigInt.one << ((n.bitLength + 1) >> 1);
    while (true) {
      final BigInt y = (x + n ~/ x) >> 1;
      if (y >= x) {
        return x;
      }
      x = y;
    }
  }

  int compareTo(Decimal other) {
    // NaN is equal to itself and smaller than every other number.
    if (isNaN || other.isNaN) {
      return isNaN == other.isNaN ? 0 : (isNaN ? -1 : 1);
    }
    if (isInfinite || other.isInfinite) {
      final int a = isInfinite ? (negative ? -1 : 1) : 0;
      final int b = other.isInfinite ? (other.negative ? -1 : 1) : 0;
      return a.compareTo(b);
    }
    if (_farApart(this, other)) {
      final int signA = isZero ? 0 : (negative ? -1 : 1);
      final int signB = other.isZero ? 0 : (other.negative ? -1 : 1);
      if (signA != signB || signA == 0) {
        return signA.compareTo(signB);
      }
      // Far apart and both not zero: the leading digits differ in place.
      return signA * _adjusted.compareTo(other._adjusted);
    }
    final (BigInt a, BigInt b, _) = _aligned(this, other);
    return a.compareTo(b);
  }

  /// Whether this is a whole number.
  bool get isInteger {
    if (!isFinite) {
      return false;
    }
    if (exponent >= 0 || coefficient == BigInt.zero) {
      return true;
    } else if (-exponent > _digits) {
      // The coefficient has fewer digits than the fraction.
      return false;
    }
    return coefficient % _ten.pow(-exponent) == BigInt.zero;
  }

  double toDouble() {
    if (isNaN) {
      return double.nan;
    } else if (isInfinite) {
      return negative ? double.negativeInfinity : double.infinity;
    }
    return double.parse(toString());
  }

  /// The number in the notation of decimal128 strings: plain digits where
  /// that is short, scientific notation otherwise.
  @override
  String toString() {
    if (isNaN) {
      return 'NaN';
    } else if (isInfinite) {
      return negative ? '-Infinity' : 'Infinity';
    }
    final String digits = coefficient.toString();
    final String sign = negative ? '-' : '';
    final int adjusted = exponent + digits.length - 1;
    if (exponent <= 0 && adjusted >= -6) {
      if (exponent == 0) {
        return '$sign$digits';
      }
      final int point = digits.length + exponent;
      if (point > 0) {
        return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
      }
      return '${sign}0.${'0' * -point}$digits';
    }
    final String mantissa = digits.length == 1
        ? digits
        : '${digits[0]}.${digits.substring(1)}';
    return '$sign${mantissa}E${adjusted >= 0 ? '+' : ''}$adjusted';
  }
}

enum _DecimalKind { nan, infinity, finite }

/// How [Decimal.roundTo] rounds.
enum DecimalRounding {
  /// Toward zero.
  down,

  /// To the nearest, halves away from zero.
  halfUp,

  /// Toward positive infinity.
  ceiling,

  /// Toward negative infinity.
  floor,
}
