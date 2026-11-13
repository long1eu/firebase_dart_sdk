part of 'expression_evaluator.dart';

// ---- comparison ----

bool _isNaN(FieldValue value) =>
    (value is DoubleValue && value.value.isNaN) ||
    (value is Decimal128FieldValue && value.isNaN);

/// Whether two values are equal for `equal`: values of one type that compare
/// as equal. Numbers of different representations are equal when they have
/// the same numeric value, NaN is equal to NaN and null to null.
bool _valuesEqual(FieldValue left, FieldValue right) =>
    left.typeOrder == right.typeOrder && left.compareTo(right) == 0;

/// Equality of two results: a missing value only equals a missing value.
bool _resultsEqual(EvaluateResult left, EvaluateResult right) {
  final FieldValue? l = left.value;
  final FieldValue? r = right.value;
  if (l == null || r == null) {
    return l == null && r == null;
  }
  return _valuesEqual(l, r);
}

/// The order of two results for the inequality functions, or null when they
/// can not be ordered: values of different types, a value and a missing
/// value, NaN and another number.
int? _strictCompare(EvaluateResult left, EvaluateResult right) {
  final FieldValue? l = left.value;
  final FieldValue? r = right.value;
  if (l == null || r == null) {
    return l == null && r == null ? 0 : null;
  }
  if (l.typeOrder != r.typeOrder) {
    return null;
  }
  if (_isNaN(l) != _isNaN(r)) {
    return null;
  }
  return l.compareTo(r);
}

_Function _comparison(bool Function(EvaluateResult, EvaluateResult) test) {
  return (_Call call) {
    if (call.length != 2) {
      return _error;
    }
    final EvaluateResult left = call.arg(0);
    final EvaluateResult right = call.arg(1);
    if (left.isError || right.isError) {
      return _error;
    }
    return _bool(test(left, right));
  };
}

_Function _inequality(bool Function(int order) test) =>
    _comparison((EvaluateResult left, EvaluateResult right) {
      final int? order = _strictCompare(left, right);
      return order != null && test(order);
    });

/// `equal_any(value, list)` and its negation.
_Function _equalAny({required bool negate}) {
  return (_Call call) {
    if (call.length != 2) {
      return _error;
    }
    final EvaluateResult value = call.arg(0);
    final EvaluateResult list = call.arg(1);
    if (value.isError || list.isError) {
      return _error;
    }
    final FieldValue? listValue = list.value;
    if (_isNull(listValue)) {
      return _null;
    } else if (listValue is! ArrayValue) {
      return _error;
    }
    final FieldValue? search = value.value;
    final bool found =
        search != null &&
        listValue.internalValue.any((FieldValue e) => _valuesEqual(search, e));
    return _bool(found != negate);
  };
}

// ---- logic ----

/// `and` and `or`: the arguments are evaluated from left to right until one
/// decides the result ([decisive]); an error or a value that is not a
/// boolean before that is an error; a null among the others makes the result
/// null.
_Function _logical({required bool decisive, bool negate = false}) {
  return (_Call call) {
    bool hasNull = false;
    for (int i = 0; i < call.length; i++) {
      final EvaluateResult result = call.arg(i);
      if (result.isError) {
        return _error;
      }
      final FieldValue? value = result.value;
      if (_isNull(value)) {
        hasNull = true;
      } else if (value is BoolValue) {
        if (value.value == decisive) {
          return _bool(decisive != negate);
        }
      } else {
        return _error;
      }
    }
    return hasNull ? _null : _bool(!decisive != negate);
  };
}

EvaluateResult _xor(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isBoolean],
  min: 1,
  (List<FieldValue> values) => _bool(
    values.fold<bool>(
      false,
      (bool acc, FieldValue v) => acc != (v as BoolValue).value,
    ),
  ),
);

EvaluateResult _not(_Call call) => _strict(call, <bool Function(FieldValue)?>[
  _isBoolean,
], (List<FieldValue> values) => _bool(!(values[0] as BoolValue).value));

EvaluateResult _conditional(_Call call) {
  if (call.length != 3) {
    return _error;
  }
  final EvaluateResult condition = call.arg(0);
  if (condition.isError) {
    return _error;
  }
  final FieldValue? value = condition.value;
  if (_isNull(value)) {
    return call.arg(2);
  } else if (value is BoolValue) {
    return call.arg(value.value ? 1 : 2);
  }
  return _error;
}

/// `switch_on(condition1, result1, condition2, result2, ..., [default])`:
/// the result of the first condition that is true. Without a match and
/// without a default it is an error.
EvaluateResult _switchOn(_Call call) {
  final int pairs = call.length ~/ 2;
  for (int i = 0; i < pairs; i++) {
    final EvaluateResult condition = call.arg(2 * i);
    if (condition.isError) {
      return _error;
    }
    final FieldValue? value = condition.value;
    if (value is BoolValue && value.value) {
      return call.arg(2 * i + 1);
    }
  }
  return call.length.isOdd ? call.arg(call.length - 1) : _error;
}

// ---- maximum and minimum ----

/// The order `maximum` and `minimum` use: the order of the values across all
/// types (NaN is the smallest number).
int _order(FieldValue left, FieldValue right) => left.compareTo(right);

/// `maximum(a, b, ...)` and `minimum(a, b, ...)`: the largest or smallest
/// argument that is not null or missing. With a single argument they are the
/// array functions: the largest or smallest element of the array.
_Function _extremum({required bool maximum}) {
  FieldValue? pick(Iterable<FieldValue?> values) {
    FieldValue? best;
    for (final FieldValue? value in values) {
      if (_isNull(value)) {
        continue;
      }
      if (best == null) {
        best = value;
      } else {
        final int order = _order(value!, best);
        if (maximum ? order > 0 : order < 0) {
          best = value;
        }
      }
    }
    return best;
  }

  return (_Call call) {
    if (call.length == 0) {
      return _error;
    }
    final List<EvaluateResult> results = call.evalAll();
    if (results.any((EvaluateResult r) => r.isError)) {
      return _error;
    }
    if (results.length == 1) {
      final FieldValue? array = results[0].value;
      if (_isNull(array)) {
        return _null;
      } else if (array is! ArrayValue) {
        return _error;
      }
      final FieldValue? best = pick(array.internalValue);
      return best == null ? _null : EvaluateValue(best);
    }
    final FieldValue? best = pick(results.map((EvaluateResult r) => r.value));
    return best == null ? _null : EvaluateValue(best);
  };
}

final Map<String, _Function> _comparisonFunctions = <String, _Function>{
  'equal': _comparison(_resultsEqual),
  'not_equal': _comparison(
    (EvaluateResult l, EvaluateResult r) => !_resultsEqual(l, r),
  ),
  'less_than': _inequality((int order) => order < 0),
  'less_than_or_equal': _inequality((int order) => order <= 0),
  'greater_than': _inequality((int order) => order > 0),
  'greater_than_or_equal': _inequality((int order) => order >= 0),
  'equal_any': _equalAny(negate: false),
  'not_equal_any': _equalAny(negate: true),
  'and': _logical(decisive: false),
  'or': _logical(decisive: true),
  'nor': _logical(decisive: true, negate: true),
  'xor': _xor,
  'not': _not,
  'conditional': _conditional,
  'switch_on': _switchOn,
  'maximum': _extremum(maximum: true),
  'minimum': _extremum(maximum: false),
};
