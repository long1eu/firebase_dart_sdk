part of 'expression_evaluator.dart';

// ---- numbers ----
//
// There are four number types. Two operands are promoted to the widest of
// the two, in the order int32 < int64 < float64 < decimal128. Integer
// overflow is an error (of the 32-bit range when both operands are int32).

final BigInt _minInt64 = -(BigInt.one << 63);
final BigInt _maxInt64 = (BigInt.one << 63) - BigInt.one;

/// A 64-bit integer from [value], or an error if it does not fit.
int _checkedInt64(BigInt value) {
  if (value < _minInt64 || value > _maxInt64) {
    throw const _EvaluationError();
  }
  return value.toInt();
}

int _checkedInt32(BigInt value) {
  if (value < BigInt.from(Int32Value.minValue) ||
      value > BigInt.from(Int32Value.maxValue)) {
    throw const _EvaluationError();
  }
  return value.toInt();
}

Decimal _decimal(FieldValue value) {
  return switch (value) {
    Decimal128FieldValue() => Decimal.parse(value.value.stringValue),
    DoubleValue() => Decimal.fromDouble(value.value),
    _ => Decimal.fromInt(_integer(value)),
  };
}

double _toDouble(FieldValue value) {
  return switch (value) {
    DoubleValue() => value.value,
    Decimal128FieldValue() => value.doubleValue,
    _ => _integer(value).toDouble(),
  };
}

EvaluateResult _decimalResult(Decimal value) => EvaluateValue(
  Decimal128FieldValue.valueOf(Decimal128Value(value.toString())),
);

EvaluateResult _int32(int value) =>
    EvaluateValue(Int32FieldValue.valueOf(Int32Value(value)));

/// An integer result with the type of the operands: int32 when all of them
/// are, int64 otherwise.
EvaluateResult _integerResult(BigInt value, {required bool int32}) =>
    int32 ? _int32(_checkedInt32(value)) : _int(_checkedInt64(value));

/// A function of two numbers with the usual promotion.
_Function _binaryArithmetic({
  required BigInt Function(BigInt a, BigInt b) integer,
  required double Function(double a, double b) float,
  required Decimal Function(Decimal a, Decimal b) decimal,
}) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isNumber, _isNumber],
    (List<FieldValue> v) {
      final FieldValue a = v[0];
      final FieldValue b = v[1];
      if (a is Decimal128FieldValue || b is Decimal128FieldValue) {
        return _decimalResult(decimal(_decimal(a), _decimal(b)));
      } else if (a is DoubleValue || b is DoubleValue) {
        return _double(float(_toDouble(a), _toDouble(b)));
      }
      return _integerResult(
        integer(BigInt.from(_integer(a)), BigInt.from(_integer(b))),
        int32: a is Int32FieldValue && b is Int32FieldValue,
      );
    },
  );
}

BigInt _integerDivide(BigInt a, BigInt b) {
  if (b == BigInt.zero) {
    throw const _EvaluationError();
  }
  // The one quotient that does not fit wraps around, as in two's complement
  // arithmetic: the smallest integer divided by -1 is itself.
  final BigInt quotient = a ~/ b;
  return quotient > _maxInt64 ? _minInt64 : quotient;
}

BigInt _integerRemainder(BigInt a, BigInt b) {
  if (b == BigInt.zero) {
    throw const _EvaluationError();
  }
  return a.remainder(b);
}

/// A function of one number that keeps the type of an integer.
_Function _unaryArithmetic({
  required BigInt Function(BigInt a) integer,
  required double Function(double a) float,
  required Decimal Function(Decimal a) decimal,
}) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isNumber],
    (List<FieldValue> v) {
      final FieldValue a = v[0];
      if (a is Decimal128FieldValue) {
        return _decimalResult(decimal(_decimal(a)));
      } else if (a is DoubleValue) {
        return _double(float(a.value));
      }
      return _integerResult(
        integer(BigInt.from(_integer(a))),
        int32: a is Int32FieldValue,
      );
    },
  );
}

/// A function of doubles: integers are converted, a decimal128 is an error
/// (the backend has no such functions for it).
_Function _doubleFunction(int arity, double Function(List<double> x) body) {
  return (_Call call) => _strict(
    call,
    List<bool Function(FieldValue)?>.filled(arity, _isNumber),
    (List<FieldValue> v) {
      // Not a type mismatch: a null argument still makes the result null.
      if (v.any((FieldValue e) => e is Decimal128FieldValue)) {
        throw const _EvaluationError();
      }
      return _double(body(v.map(_toDouble).toList()));
    },
  );
}

/// The number of digits of [value] before the decimal point (zero or
/// negative for a value below one).
int _digitsBeforePoint(double value) =>
    (math.log(value.abs()) / math.ln10).floor() + 1;

double _roundHalfAwayFromZero(double value) {
  if (!value.isFinite) {
    return value;
  }
  // double.roundToDouble() rounds halves away from zero.
  return value.roundToDouble();
}

/// `round(x)`, `round(x, places)`, `trunc(x)` and `trunc(x, places)`.
_Function _rounding({required bool truncate}) {
  final DecimalRounding mode = truncate
      ? DecimalRounding.down
      : DecimalRounding.halfUp;
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isNumber, _isInteger],
    min: 1,
    max: 2,
    (List<FieldValue> v) {
      final FieldValue x = v[0];
      final int places = v.length > 1 ? _integer(v[1]) : 0;
      if (x is Decimal128FieldValue) {
        // The backend has no trunc(decimal128, places).
        if (truncate && v.length > 1) {
          throw const _EvaluationError();
        }
        final Decimal value = _decimal(x);
        return _decimalResult(
          value.isFinite ? value.roundTo(places, mode) : value,
        );
      } else if (x is DoubleValue) {
        final double value = x.value;
        if (!value.isFinite) {
          return _double(value);
        }
        if (v.length == 1) {
          // round(x) never returns a negative zero and trunc(x) only for
          // a negative zero (ceil and floor keep the sign).
          if (truncate) {
            final double result = value.truncateToDouble();
            return _double(result == 0 && value != 0 ? 0 : result);
          }
          final double result = _roundHalfAwayFromZero(value);
          return _double(result == 0 ? 0 : result);
        }
        if (value == 0 && !truncate) {
          return _double(0);
        }
        // A double has no more than 16 decimal places to round to.
        if (places >= 16) {
          return _double(value);
        }
        // As the Android SDK and the backend: a value with fewer digits
        // before the decimal point than are rounded away becomes zero, also
        // where rounding half up would give the next power of ten
        // (round(5.0, -1) is 0, not 10).
        if (value != 0 && -places >= _digitsBeforePoint(value)) {
          return _double(truncate && value.isNegative ? -0.0 : 0);
        }
        final double result = Decimal.parse(
          value.toString(),
        ).roundTo(places, mode).toDouble();
        if (!result.isFinite) {
          throw const _EvaluationError();
        }
        // Rounding everything away keeps the sign of the value.
        return _double(result == 0 && value.isNegative ? -0.0 : result);
      }
      final BigInt value = BigInt.from(_integer(x));
      if (places >= 0) {
        return EvaluateValue(x);
      }
      // See the same shortcut for doubles above: round(5, -1) is 0.
      // round() of the smallest integer of the type is always zero (its
      // absolute value does not fit, and the backend then sees no digits).
      final bool smallest =
          !truncate &&
          value ==
              (x is Int32FieldValue
                  ? BigInt.from(Int32Value.minValue)
                  : _minInt64);
      if (smallest ||
          (value != BigInt.zero && -places >= value.abs().toString().length)) {
        return _integerResult(BigInt.zero, int32: x is Int32FieldValue);
      }
      final Decimal rounded = Decimal.finite(value, 0).roundTo(places, mode);
      final BigInt result =
          (rounded.negative ? -rounded.coefficient : rounded.coefficient) *
          BigInt.from(10).pow(rounded.exponent);
      return _integerResult(result, int32: x is Int32FieldValue);
    },
  );
}

EvaluateResult _sqrt(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isNumber],
  (List<FieldValue> v) {
    final FieldValue x = v[0];
    if (x is Decimal128FieldValue) {
      final Decimal value = _decimal(x);
      if (value.negative && !value.isZero && !value.isNaN) {
        throw const _EvaluationError();
      }
      return _decimalResult(value.sqrt());
    }
    final double value = _toDouble(x);
    if (value < 0) {
      throw const _EvaluationError();
    }
    return _double(math.sqrt(value));
  },
);

double _pow(double base, double exponent) {
  if (exponent == 0.0 || base == 1.0) {
    return 1;
  } else if (base == -1.0 && exponent.isInfinite) {
    return 1;
  } else if (exponent.isNaN || base.isNaN) {
    return double.nan;
  } else if (base < 0 &&
      base.isFinite &&
      !(exponent.isFinite && exponent == exponent.truncateToDouble())) {
    // A fractional power of a negative number has no real value.
    throw const _EvaluationError();
  } else if (base == 0.0 && exponent < 0) {
    throw const _EvaluationError();
  }
  return math.pow(base, exponent).toDouble();
}

double _exp(double value) {
  final double result = math.exp(value);
  if (result == double.infinity && value != double.infinity) {
    throw const _EvaluationError();
  }
  return result;
}

// What the logarithms do with NaN, zero, negative numbers and the
// infinities differs from function to function; this is what the Enterprise
// edition emulator returns.

double _ln(double value) {
  if (value.isNaN || value <= 0) {
    throw const _EvaluationError();
  }
  return math.log(value);
}

double _log(double value, double base) {
  if (value == double.negativeInfinity || base == double.infinity) {
    return double.nan;
  } else if (base <= 0 || value <= 0 || base == 1.0) {
    throw const _EvaluationError();
  }
  return math.log(value) / math.log(base);
}

double _log10(double value) {
  if (value == double.negativeInfinity) {
    return double.nan;
  } else if (value <= 0) {
    throw const _EvaluationError();
  }
  return math.log(value) / math.ln10;
}

final Map<String, _Function> _arithmeticFunctions = <String, _Function>{
  'add': _binaryArithmetic(
    integer: (BigInt a, BigInt b) => a + b,
    float: (double a, double b) => a + b,
    decimal: (Decimal a, Decimal b) => a + b,
  ),
  'subtract': _binaryArithmetic(
    integer: (BigInt a, BigInt b) => a - b,
    float: (double a, double b) => a - b,
    decimal: (Decimal a, Decimal b) => a - b,
  ),
  'multiply': _binaryArithmetic(
    integer: (BigInt a, BigInt b) => a * b,
    float: (double a, double b) => a * b,
    decimal: (Decimal a, Decimal b) => a * b,
  ),
  'divide': _binaryArithmetic(
    integer: _integerDivide,
    float: (double a, double b) => a / b,
    decimal: (Decimal a, Decimal b) => a / b,
  ),
  'mod': _binaryArithmetic(
    integer: _integerRemainder,
    float: (double a, double b) => a.remainder(b),
    decimal: (Decimal a, Decimal b) => a.remainder(b),
  ),
  'abs': _unaryArithmetic(
    integer: (BigInt a) => a.abs(),
    float: (double a) => a.abs(),
    decimal: (Decimal a) => a.abs(),
  ),
  'ceil': _unaryArithmetic(
    integer: (BigInt a) => a,
    float: (double a) => a.isFinite ? a.ceilToDouble() : a,
    decimal: (Decimal a) => a.roundTo(0, DecimalRounding.ceiling),
  ),
  'floor': _unaryArithmetic(
    integer: (BigInt a) => a,
    float: (double a) => a.isFinite ? a.floorToDouble() : a,
    decimal: (Decimal a) => a.roundTo(0, DecimalRounding.floor),
  ),
  'round': _rounding(truncate: false),
  'trunc': _rounding(truncate: true),
  'sqrt': _sqrt,
  'pow': _doubleFunction(2, (List<double> x) => _pow(x[0], x[1])),
  'exp': _doubleFunction(1, (List<double> x) => _exp(x[0])),
  'ln': _doubleFunction(1, (List<double> x) => _ln(x[0])),
  'log': _doubleFunction(2, (List<double> x) => _log(x[0], x[1])),
  'log10': _doubleFunction(1, (List<double> x) => _log10(x[0])),
};
