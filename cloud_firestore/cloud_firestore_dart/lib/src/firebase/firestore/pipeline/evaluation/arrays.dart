part of 'expression_evaluator.dart';

// ---- arrays ----

/// Evaluates the arguments of a function whose first argument is an array
/// and whose other arguments may be anything, also missing: an error in an
/// argument is an error, a first argument that is not an array is an error,
/// a null (or missing) array makes the result null.
EvaluateResult _onArray(
  _Call call,
  int arity,
  EvaluateResult Function(List<FieldValue> array, List<EvaluateResult> others)
  body, {
  bool nullArrayFirst = false,
}) {
  if (call.length != arity) {
    return _error;
  }
  if (nullArrayFirst) {
    // A null array is the result before the other arguments are looked at.
    final EvaluateResult first = call.arg(0);
    if (!first.isError && first.isNullOrUnset) {
      return _null;
    }
  }
  final List<EvaluateResult> results = call.evalAll();
  if (results.any((EvaluateResult r) => r.isError)) {
    return _error;
  }
  final FieldValue? array = results[0].value;
  if (array != null && array is! NullValue && array is! ArrayValue) {
    return _error;
  }
  if (_isNull(array)) {
    return _null;
  }
  try {
    return body(_elements(array!), results.sublist(1));
  } on _EvaluationError {
    return _error;
  }
}

EvaluateResult _arrayLength(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isArray],
  (List<FieldValue> v) => _int(_elements(v[0]).length),
);

EvaluateResult _arrayContains(_Call call) =>
    _onArray(call, 2, (List<FieldValue> array, List<EvaluateResult> others) {
      final FieldValue? search = others[0].value;
      return _bool(
        search != null && array.any((FieldValue e) => _valuesEqual(e, search)),
      );
    });

/// `array_contains_any` and `array_contains_all`.
_Function _arrayContainsList({required bool all}) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isArray, _isArray],
    (List<FieldValue> v) {
      final List<FieldValue> array = _elements(v[0]);
      bool contains(FieldValue search) =>
          array.any((FieldValue e) => _valuesEqual(e, search));
      final List<FieldValue> search = _elements(v[1]);
      return _bool(all ? search.every(contains) : search.any(contains));
    },
  );
}

EvaluateResult _arrayReverse(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isArray],
  (List<FieldValue> v) => _list(_elements(v[0]).reversed.toList()),
);

/// `array_get(array, index)`: the element, counting from the end for a
/// negative index. An index outside the array has no value.
EvaluateResult _arrayGet(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isArray, _isInteger],
  (List<FieldValue> v) {
    final List<FieldValue> array = _elements(v[0]);
    int index = _integer(v[1]);
    if (index >= array.length || index < -array.length) {
      return _unset;
    }
    if (index < 0) {
      index += array.length;
    }
    return EvaluateValue(array[index]);
  },
);

/// `array_slice(array, offset, [length])`.
EvaluateResult _arraySlice(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isArray, _isInteger, _isInteger],
  min: 2,
  max: 3,
  (List<FieldValue> v) {
    final List<FieldValue> array = _elements(v[0]);
    int start = _integer(v[1]);
    final int? length = v.length > 2 ? _integer(v[2]) : null;
    if (length != null && length < 0) {
      throw const _EvaluationError();
    }
    if (start < 0) {
      start = math.max(0, array.length + start);
    }
    if (start >= array.length) {
      return _list(const <FieldValue>[]);
    }
    final int end = length == null || length > array.length - start
        ? array.length
        : start + length;
    return _list(array.sublist(start, end));
  },
);

/// `array_first` and `array_last`: an empty array has no first element.
_Function _arrayEnd({required bool first}) {
  return (_Call call) => _strict(call, <bool Function(FieldValue)?>[_isArray], (
    List<FieldValue> v,
  ) {
    final List<FieldValue> array = _elements(v[0]);
    if (array.isEmpty) {
      return _unset;
    }
    return EvaluateValue(first ? array.first : array.last);
  });
}

/// `array_first_n` and `array_last_n`.
_Function _arrayEndN({required bool first}) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isArray, _isInteger],
    (List<FieldValue> v) {
      final List<FieldValue> array = _elements(v[0]);
      final int n = _integer(v[1]);
      if (n < 0) {
        throw const _EvaluationError();
      }
      final int count = math.min(n, array.length);
      return _list(
        first ? array.sublist(0, count) : array.sublist(array.length - count),
      );
    },
  );
}

/// `array_index_of(array, value, 'first' | 'last')`.
EvaluateResult _arrayIndexOf(_Call call) {
  if (call.length != 3) {
    return _error;
  }
  final String? direction = call.literal(2);
  if (direction != 'first' && direction != 'last') {
    return _error;
  }
  return _onArray(call, 3, (
    List<FieldValue> array,
    List<EvaluateResult> others,
  ) {
    final FieldValue? search = others[0].value;
    if (search == null) {
      return _int(-1);
    }
    bool matches(FieldValue e) => _valuesEqual(e, search);
    return _int(
      direction == 'first'
          ? array.indexWhere(matches)
          : array.lastIndexWhere(matches),
    );
  }, nullArrayFirst: true);
}

EvaluateResult _arrayIndexOfAll(_Call call) =>
    _onArray(call, 2, (List<FieldValue> array, List<EvaluateResult> others) {
      final FieldValue? search = others[0].value;
      return _list(<FieldValue>[
        if (search != null)
          for (int i = 0; i < array.length; i++)
            if (_valuesEqual(array[i], search)) IntegerValue.valueOf(i),
      ]);
    }, nullArrayFirst: true);

/// `maximum_n(array, n)` and `minimum_n(array, n)`: the n largest or
/// smallest elements that are not null, in that order.
_Function _arrayExtremumN({required bool maximum}) {
  return (_Call call) => _strict(
    call,
    <bool Function(FieldValue)?>[_isArray, _isInteger],
    (List<FieldValue> v) {
      final int n = _integer(v[1]);
      if (n < 0) {
        throw const _EvaluationError();
      }
      final List<FieldValue> sorted =
          _elements(v[0]).where((FieldValue e) => e is! NullValue).toList()
            ..sort(
              maximum ? (FieldValue a, FieldValue b) => _order(b, a) : _order,
            );
      return _list(sorted.sublist(0, math.min(n, sorted.length)));
    },
  );
}

EvaluateResult _arrayConcat(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isArray],
  min: 1,
  (List<FieldValue> v) =>
      _list(<FieldValue>[for (final FieldValue e in v) ..._elements(e)]),
);

/// `array_filter(array, alias, condition)`: the elements for which the
/// condition, evaluated with the element as the variable `alias`, is true.
EvaluateResult _arrayFilter(_Call call) {
  if (call.length != 3) {
    return _error;
  }
  final String? alias = call.literal(1);
  if (alias == null) {
    return _error;
  }
  final EvaluateResult arrayResult = call.arg(0);
  if (arrayResult.isError) {
    return _error;
  }
  final FieldValue? array = arrayResult.value;
  if (_isNull(array)) {
    return _null;
  } else if (array is! ArrayValue) {
    return _error;
  }
  final List<FieldValue> kept = <FieldValue>[];
  for (final FieldValue element in array.internalValue) {
    final EvaluateResult keep = call.scope
        .withVariables(<String, EvaluateResult>{alias: EvaluateValue(element)})
        .eval(call.args[2]);
    if (keep.isError) {
      return _error;
    }
    final FieldValue? value = keep.value;
    if (value is BoolValue) {
      if (value.value) {
        kept.add(element);
      }
    } else if (!_isNull(value)) {
      return _error;
    }
  }
  return _list(kept);
}

/// `array_transform(array, alias, [indexAlias], expression)`.
EvaluateResult _arrayTransform(_Call call) {
  if (call.length != 3 && call.length != 4) {
    return _error;
  }
  final String? alias = call.literal(1);
  final String? indexAlias = call.length == 4 ? call.literal(2) : null;
  if (alias == null || (call.length == 4 && indexAlias == null)) {
    return _error;
  }
  final EvaluateResult arrayResult = call.arg(0);
  if (arrayResult.isError) {
    return _error;
  }
  final FieldValue? array = arrayResult.value;
  if (_isNull(array)) {
    return _null;
  } else if (array is! ArrayValue) {
    return _error;
  }
  final List<FieldValue> result = <FieldValue>[];
  for (int i = 0; i < array.internalValue.length; i++) {
    final EvaluateResult element = call.scope
        .withVariables(<String, EvaluateResult>{
          alias: EvaluateValue(array.internalValue[i]),
          if (indexAlias != null) indexAlias: _int(i),
        })
        .eval(call.args.last);
    if (element.isError) {
      return _error;
    }
    result.add(element.value ?? NullValue.nullValue());
  }
  return _list(result);
}

/// `sum(array)` (`Expression.arraySum`): the sum of the numbers of the
/// array, as the aggregate `sum` adds them (the emulator agrees on every
/// recorded case): elements that are not numbers are skipped, an array
/// without numbers gives null, an int64 overflow of the running total is an
/// error, integers and doubles give a double, a Decimal128 gives a
/// Decimal128. Null or a missing value gives null; any other value is an
/// error. Neither Android nor JS evaluates this locally.
EvaluateResult _arraySum(_Call call) {
  if (call.length != 1) {
    return _error;
  }
  final EvaluateResult result = call.arg(0);
  if (result.isError) {
    return _error;
  }
  final FieldValue? array = result.value;
  if (_isNull(array)) {
    return _null;
  } else if (array is! ArrayValue) {
    return _error;
  }
  final SumAccumulator sum = SumAccumulator();
  for (final FieldValue element in array.internalValue) {
    sum.add(EvaluateValue(element));
  }
  return sum.result;
}

final Map<String, _Function> _arrayFunctions = <String, _Function>{
  'sum': _arraySum,
  'array_length': _arrayLength,
  'array_contains': _arrayContains,
  'array_contains_any': _arrayContainsList(all: false),
  'array_contains_all': _arrayContainsList(all: true),
  'array_reverse': _arrayReverse,
  'array_get': _arrayGet,
  'array_slice': _arraySlice,
  'array_first': _arrayEnd(first: true),
  'array_last': _arrayEnd(first: false),
  'array_first_n': _arrayEndN(first: true),
  'array_last_n': _arrayEndN(first: false),
  'array_index_of': _arrayIndexOf,
  'array_index_of_all': _arrayIndexOfAll,
  'maximum_n': _arrayExtremumN(maximum: true),
  'minimum_n': _arrayExtremumN(maximum: false),
  'array_concat': _arrayConcat,
  'array_filter': _arrayFilter,
  'array_transform': _arrayTransform,
};
