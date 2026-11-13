// Local evaluation of the aggregate functions of pipelines: a pure library,
// like expression_evaluator.dart.

import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/decimal.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;

/// Accumulates the values of one aggregate function over the inputs of a
/// group.
abstract class Accumulator {
  /// Adds the result of the argument of the function for one input. For a
  /// function without an argument (`count()`) the result is ignored.
  void add(EvaluateResult result);

  /// The aggregate of everything that was added. An [EvaluateResult.error]
  /// fails the pipeline, as on the backend.
  EvaluateResult get result;
}

/// Evaluates aggregate functions (`count`, `sum`, `average`, ...) in their
/// wire form.
class AggregateEvaluator {
  AggregateEvaluator(this.expressions);

  /// Evaluates the arguments of the functions.
  final ExpressionEvaluator expressions;

  static final Map<String, Accumulator Function()> _accumulators =
      <String, Accumulator Function()>{
        'count': _Count.new,
        'count_if': _CountIf.new,
        'count_distinct': _CountDistinct.new,
        'sum': _Sum.new,
        'average': _Average.new,
        'minimum': () => _Extremum(maximum: false),
        'maximum': () => _Extremum(maximum: true),
        'first': () => _FirstOrLast(first: true),
        'last': () => _FirstOrLast(first: false),
        'array_agg': _ArrayAgg.new,
        'array_agg_distinct': _ArrayAggDistinct.new,
      };

  /// Whether the aggregate function [name] can be evaluated locally.
  static bool supports(String name) => _accumulators.containsKey(name);

  /// The names of the aggregate functions that can be evaluated locally.
  static Iterable<String> get supportedFunctions => _accumulators.keys;

  /// Evaluates the aggregate [function] over [inputs], in their order.
  ///
  /// Throws an [UnsupportedExpression] for a function that can not be
  /// evaluated locally.
  EvaluateResult aggregate(
    pb.Value function,
    Iterable<EvaluationInput> inputs,
  ) {
    if (function.whichValueType() != pb.Value_ValueType.functionValue) {
      throw UnsupportedExpression('Not an aggregate function: $function');
    }
    final pb.Function_ call = function.functionValue;
    final Accumulator Function()? create = _accumulators[call.name];
    if (create == null) {
      throw UnsupportedExpression(
        'The aggregate function ${call.name}() is not evaluated locally',
      );
    }
    final Accumulator accumulator = create();
    // first() stops at the first input: an error in the expression for a
    // later input does not matter. (last() evaluates them all.)
    final Iterable<EvaluationInput> evaluated = call.name == 'first'
        ? inputs.take(1)
        : inputs;
    for (final EvaluationInput input in evaluated) {
      if (call.args.isEmpty) {
        accumulator.add(EvaluateResult.trueValue);
        continue;
      }
      final EvaluateResult result = expressions.evaluate(call.args[0], input);
      if (result.isError) {
        return EvaluateResult.error;
      }
      accumulator.add(result);
    }
    return accumulator.result;
  }
}

bool _isNullOrUnset(EvaluateResult result) => result.isNullOrUnset;

EvaluateResult _integer(int value) =>
    EvaluateValue(IntegerValue.valueOf(exactInteger(value)));

bool _equal(FieldValue a, FieldValue b) =>
    a.typeOrder == b.typeOrder && a.compareTo(b) == 0;

/// `count()` counts the inputs, `count(expression)` those for which the
/// expression has a value that is not null.
class _Count implements Accumulator {
  int _count = 0;

  @override
  void add(EvaluateResult result) {
    if (!_isNullOrUnset(result)) {
      _count++;
    }
  }

  @override
  EvaluateResult get result => _integer(_count);
}

class _CountIf implements Accumulator {
  int _count = 0;

  @override
  void add(EvaluateResult result) {
    final FieldValue? value = result.value;
    if (value is BoolValue && value.value) {
      _count++;
    }
  }

  @override
  EvaluateResult get result => _integer(_count);
}

/// The distinct values, in the order they were first seen. A value that
/// equals an earlier one (`1` and `1.0`) replaces it.
class _Distinct {
  final List<FieldValue> values = <FieldValue>[];

  void add(FieldValue value) {
    final int index = values.indexWhere((FieldValue v) => _equal(v, value));
    if (index < 0) {
      values.add(value);
    } else {
      values[index] = value;
    }
  }
}

class _CountDistinct implements Accumulator {
  final _Distinct _distinct = _Distinct();

  @override
  void add(EvaluateResult result) {
    if (!_isNullOrUnset(result)) {
      _distinct.add(result.value!);
    }
  }

  @override
  EvaluateResult get result => _integer(_distinct.values.length);
}

/// The sum of the numbers among the values; other values are ignored. An
/// integer sum that overflows is an error.
class _Sum implements Accumulator {
  BigInt _integers = BigInt.zero;
  double _doubles = 0;
  Decimal? _decimals;
  bool _hasDouble = false;
  int _count = 0;

  static final BigInt _min = -(BigInt.one << 63);
  static final BigInt _max = (BigInt.one << 63) - BigInt.one;
  bool _overflow = false;

  @override
  void add(EvaluateResult result) {
    final FieldValue? value = result.value;
    if (value is! NumberValue) {
      return;
    }
    _count++;
    if (value is Decimal128FieldValue) {
      _decimals =
          (_decimals ?? Decimal.fromInt(0)) +
          Decimal.parse(value.value.stringValue);
    } else if (value is DoubleValue) {
      _hasDouble = true;
      _doubles += value.value;
    } else {
      _integers += BigInt.from(
        value is Int32FieldValue
            ? value.intValue
            : exactInteger((value as IntegerValue).value),
      );
      if (_integers < _min || _integers > _max) {
        _overflow = true;
      }
    }
  }

  int get count => _count;

  /// The sum as a decimal, when a decimal was added.
  Decimal? get decimal {
    final Decimal? decimals = _decimals;
    if (decimals == null) {
      return null;
    }
    Decimal total = decimals + Decimal.finite(_integers, 0);
    if (_hasDouble) {
      total += Decimal.fromDouble(_doubles);
    }
    return total;
  }

  double get asDouble => _doubles + _integers.toDouble();

  bool get failed => _overflow;

  @override
  EvaluateResult get result {
    if (_count == 0) {
      return EvaluateResult.nullValue;
    } else if (_overflow) {
      return EvaluateResult.error;
    }
    final Decimal? total = decimal;
    if (total != null) {
      return EvaluateValue(
        Decimal128FieldValue.valueOf(Decimal128Value(total.toString())),
      );
    } else if (_hasDouble) {
      return EvaluateValue(DoubleValue.valueOf(asDouble));
    }
    return _integer(_integers.toInt());
  }
}

class _Average implements Accumulator {
  final _Sum _sum = _Sum();

  @override
  void add(EvaluateResult result) => _sum.add(result);

  @override
  EvaluateResult get result {
    if (_sum.count == 0) {
      return EvaluateResult.nullValue;
    } else if (_sum.failed) {
      return EvaluateResult.error;
    }
    final Decimal? total = _sum.decimal;
    if (total != null) {
      return EvaluateValue(
        Decimal128FieldValue.valueOf(
          Decimal128Value((total / Decimal.fromInt(_sum.count)).toString()),
        ),
      );
    }
    return EvaluateValue(DoubleValue.valueOf(_sum.asDouble / _sum.count));
  }
}

/// The smallest or the largest of the values that are not null, in the order
/// of the values across all types. Of equal values the first one is kept.
class _Extremum implements Accumulator {
  _Extremum({required this.maximum});

  final bool maximum;
  FieldValue? _best;

  @override
  void add(EvaluateResult result) {
    if (_isNullOrUnset(result)) {
      return;
    }
    final FieldValue value = result.value!;
    final FieldValue? best = _best;
    if (best == null) {
      _best = value;
    } else {
      final int order = value.compareTo(best);
      if (maximum ? order > 0 : order < 0) {
        _best = value;
      }
    }
  }

  @override
  EvaluateResult get result {
    final FieldValue? best = _best;
    return best == null ? EvaluateResult.nullValue : EvaluateValue(best);
  }
}

class _FirstOrLast implements Accumulator {
  _FirstOrLast({required this.first});

  final bool first;
  FieldValue? _value;

  @override
  void add(EvaluateResult result) {
    if (first && _value != null) {
      return;
    }
    _value = result.value ?? NullValue.nullValue();
  }

  @override
  EvaluateResult get result => EvaluateValue(_value ?? NullValue.nullValue());
}

/// The values, nulls included, in the order of the inputs. An input without
/// a value adds nothing.
class _ArrayAgg implements Accumulator {
  final List<FieldValue> _values = <FieldValue>[];

  @override
  void add(EvaluateResult result) {
    final FieldValue? value = result.value;
    if (value != null) {
      _values.add(value);
    }
  }

  @override
  EvaluateResult get result => EvaluateValue(ArrayValue.fromList(_values));
}

/// The distinct values. The backend returns them in no particular order;
/// here it is the order they were first seen.
class _ArrayAggDistinct implements Accumulator {
  final _Distinct _distinct = _Distinct();

  @override
  void add(EvaluateResult result) {
    final FieldValue? value = result.value;
    if (value != null) {
      _distinct.add(value);
    }
  }

  @override
  EvaluateResult get result =>
      EvaluateValue(ArrayValue.fromList(_distinct.values));
}
