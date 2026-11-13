// Local evaluation of pipeline expressions: a pure library, without any
// wiring to a client.
//
// An expression is evaluated in its wire form (the `Value` that
// `Expression.toProto` produces), so that this library does not depend on the
// public expression classes and can evaluate a pipeline that was read back
// from storage.
//
// Sources of the semantics, in this order: the local evaluation of the
// Android SDK (`pipeline/evaluation/*.kt`, whose registry still uses older
// function names: `eq` is `equal` here, `logical_max` is `maximum`,
// `str_concat` is `string_concat`, ...), and the Enterprise edition
// emulator, which was asked wherever Android has no implementation or
// disagrees. `test/integration_enterprise/pipeline_evaluation_property_test.dart`
// compares this library with the emulator.

library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/aggregate_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/decimal.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/re2.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;

part 'arithmetic.dart';
part 'arrays.dart';
part 'comparison.dart';
part 'maps.dart';
part 'strings.dart';
part 'timestamps.dart';
part 'vectors.dart';

/// What an expression is evaluated against: the fields of a document or of
/// an intermediate result of a pipeline.
class EvaluationInput {
  const EvaluationInput(
    this.fields, {
    this.key,
    this.createTime,
    this.updateTime,
  });

  /// The fields.
  final ObjectValue fields;

  /// The key of the document, when the input still is a document: the value
  /// of `__name__`.
  final DocumentKey? key;

  /// The value of `__create_time__`, if known.
  final Timestamp? createTime;

  /// The value of `__update_time__`, if known.
  final Timestamp? updateTime;
}

/// Thrown for an expression this library can not evaluate: a function it
/// does not implement, a subquery, a named time zone. Unlike an
/// [EvaluateResult.error] this says nothing about the data: the caller has to
/// send the pipeline to the backend instead.
class UnsupportedExpression implements Exception {
  UnsupportedExpression(this.message);

  final String message;

  @override
  String toString() => 'UnsupportedExpression: $message';
}

/// Whether integers are JavaScript numbers (code compiled with dart2js), which
/// hold integers exactly only up to 2^53.
const bool jsIntegers = identical(1, 1.0);

const int _maxSafeInteger = 9007199254740991; // 2^53 - 1

/// [value], when it is exact.
///
/// Compiled to JavaScript an `int` beyond ±(2^53 - 1) is a double that
/// stands for several 64-bit integers, so neither an operand nor a result
/// there can be computed as the backend would: such an expression is not
/// evaluated locally ([UnsupportedExpression]) rather than evaluated wrong.
int exactInteger(int value) {
  if (jsIntegers && (value > _maxSafeInteger || value < -_maxSafeInteger)) {
    throw UnsupportedExpression(
      'The integer $value is beyond the integers JavaScript numbers hold '
      'exactly (±2^53 - 1)',
    );
  }
  return value;
}

typedef _Function = EvaluateResult Function(_Call call);

/// Evaluates pipeline expressions for the database [databaseId].
class ExpressionEvaluator {
  ExpressionEvaluator(
    this.databaseId, {
    Timestamp Function()? now,
    math.Random? random,
  }) : _serializer = RemoteSerializer(databaseId),
       _now = now ?? Timestamp.now,
       _random = random ?? math.Random();

  final DatabaseId databaseId;
  final RemoteSerializer _serializer;
  final Timestamp Function() _now;
  final math.Random _random;

  /// Whether the function [name] can be evaluated locally.
  static bool supports(String name) => _functions.containsKey(name);

  /// The names of the functions that can be evaluated locally.
  static Iterable<String> get supportedFunctions => _functions.keys;

  /// Evaluates [expression] for [input]. [variables] are the values of the
  /// variables the expression may refer to.
  ///
  /// Throws an [UnsupportedExpression] for an expression that can not be
  /// evaluated locally.
  EvaluateResult evaluate(
    pb.Value expression,
    EvaluationInput input, {
    Map<String, EvaluateResult> variables = const <String, EvaluateResult>{},
  }) {
    return _Scope(this, input, variables).eval(expression);
  }
}

/// Why some functions are not evaluated locally, appended to the message of
/// the [UnsupportedExpression].
const Map<String, String> _unsupportedReasons = <String, String>{
  'document_matches':
      ': it is a full-text search function, evaluated only by the backend '
      '(in a search stage, against its search index); no SDK evaluates it '
      'locally',
  'score':
      ': it is the relevance of a full-text search, computed only by the '
      'backend in a search stage; no SDK evaluates it locally',
  'over':
      ': window functions are evaluated only by the add_window_fields stage '
      'on the backend',
  'rank':
      ': window functions are evaluated only by the add_window_fields stage '
      'on the backend',
};

/// The input and the variables an expression is evaluated with.
class _Scope {
  _Scope(this.evaluator, this.input, this.variables);

  final ExpressionEvaluator evaluator;
  final EvaluationInput input;
  final Map<String, EvaluateResult> variables;

  _Scope withVariables(Map<String, EvaluateResult> more) =>
      _Scope(evaluator, input, <String, EvaluateResult>{...variables, ...more});

  EvaluateResult eval(pb.Value expression) {
    switch (expression.whichValueType()) {
      case pb.Value_ValueType.fieldReferenceValue:
        return _field(expression.fieldReferenceValue);
      case pb.Value_ValueType.functionValue:
        final pb.Function_ function = expression.functionValue;
        final _Function? implementation = _functions[function.name];
        if (implementation == null) {
          throw UnsupportedExpression(
            'The function ${function.name}() is not evaluated locally'
            '${_unsupportedReasons[function.name] ?? ''}',
          );
        }
        return implementation(_Call(this, function));
      case pb.Value_ValueType.variableReferenceValue:
        final EvaluateResult? variable =
            variables[expression.variableReferenceValue];
        if (variable == null) {
          throw UnsupportedExpression(
            'The variable ${expression.variableReferenceValue} is not defined',
          );
        }
        return variable;
      case pb.Value_ValueType.pipelineValue:
        throw UnsupportedExpression('Subqueries are not evaluated locally');
      case pb.Value_ValueType.arrayValue:
        // A list of expressions (the second argument of equal_any, for
        // example) has this form too: its elements are evaluated.
        final List<FieldValue> elements = <FieldValue>[];
        for (final pb.Value element in expression.arrayValue.values) {
          final EvaluateResult result = eval(element);
          if (result.isError) {
            return EvaluateResult.error;
          }
          elements.add(result.value ?? NullValue.nullValue());
        }
        return EvaluateValue(ArrayValue.fromList(elements));
      case pb.Value_ValueType.notSet:
        return EvaluateResult.error;
      default:
        // A constant.
        return EvaluateValue(evaluator._serializer.decodeValue(expression));
    }
  }

  EvaluateResult _field(String name) {
    switch (name) {
      case '__name__':
        final DocumentKey? key = input.key;
        return key == null
            ? EvaluateResult.unset
            : EvaluateValue(ReferenceValue.valueOf(evaluator.databaseId, key));
      case '__create_time__':
        final Timestamp? time = input.createTime;
        return time == null
            ? EvaluateResult.unset
            : EvaluateValue(TimestampValue.valueOf(time));
      case '__update_time__':
        final Timestamp? time = input.updateTime;
        return time == null
            ? EvaluateResult.unset
            : EvaluateValue(TimestampValue.valueOf(time));
    }
    final FieldValue? value = input.fields.get(
      FieldPath.fromServerFormat(name),
    );
    return value == null ? EvaluateResult.unset : EvaluateValue(value);
  }
}

/// One call of a function: its arguments, not evaluated yet.
class _Call {
  _Call(this.scope, this._function);

  final _Scope scope;
  final pb.Function_ _function;

  String get name => _function.name;

  List<pb.Value> get args => _function.args;

  int get length => _function.args.length;

  /// Evaluates the argument at [index].
  EvaluateResult arg(int index) => scope.eval(_function.args[index]);

  /// Evaluates all the arguments, in order.
  List<EvaluateResult> evalAll() => <EvaluateResult>[
    for (final pb.Value arg in args) scope.eval(arg),
  ];

  /// The argument at [index] when it is a string literal, as the names of
  /// units and types have to be.
  String? literal(int index) {
    final pb.Value arg = args[index];
    return arg.whichValueType() == pb.Value_ValueType.stringValue
        ? arg.stringValue
        : null;
  }
}

// ---- helpers shared by the function implementations ----

const EvaluateResult _error = EvaluateResult.error;
const EvaluateResult _unset = EvaluateResult.unset;
final EvaluateResult _null = EvaluateResult.nullValue;

EvaluateResult _bool(bool value) =>
    value ? EvaluateResult.trueValue : EvaluateResult.falseValue;

EvaluateResult _int(int value) =>
    EvaluateValue(IntegerValue.valueOf(exactInteger(value)));

EvaluateResult _double(double value) =>
    EvaluateValue(DoubleValue.valueOf(value));

EvaluateResult _string(String value) =>
    EvaluateValue(StringValue.valueOf(value));

EvaluateResult _bytes(List<int> value) =>
    EvaluateValue(BlobValue.valueOf(Blob(Uint8List.fromList(value))));

EvaluateResult _list(List<FieldValue> value) =>
    EvaluateValue(ArrayValue.fromList(value));

bool _isNull(FieldValue? value) => value == null || value is NullValue;

/// The rule most functions follow ("mirroring" in the Android sources): the
/// arguments are all evaluated; an error in any of them is an error; then an
/// argument of the wrong type is an error; then a null (or missing) argument
/// makes the result null; only then [body] sees the values.
///
/// [types] has a check for each argument (the last one is used for the
/// remaining arguments); a null check accepts every value.
EvaluateResult _strict(
  _Call call,
  List<bool Function(FieldValue value)?> types,
  EvaluateResult Function(List<FieldValue> values) body, {
  int? min,
  int? max,
}) {
  if (call.length < (min ?? types.length) ||
      call.length > (max ?? (min == null ? types.length : call.length))) {
    return _error;
  }
  final List<EvaluateResult> results = call.evalAll();
  bool hasNull = false;
  final List<FieldValue> values = <FieldValue>[];
  for (final EvaluateResult result in results) {
    if (result.isError) {
      return _error;
    }
  }
  for (int i = 0; i < results.length; i++) {
    final FieldValue? value = results[i].value;
    if (_isNull(value)) {
      hasNull = true;
      continue;
    }
    final bool Function(FieldValue)? check =
        types[i < types.length ? i : types.length - 1];
    if (check != null && !check(value!)) {
      return _error;
    }
    values.add(value!);
  }
  if (hasNull) {
    return _null;
  }
  try {
    return body(values);
  } on _EvaluationError {
    return _error;
  }
}

/// Thrown inside a function body to make the result an error.
class _EvaluationError implements Exception {
  const _EvaluationError();
}

bool _isString(FieldValue v) => v is StringValue;
bool _isStringOrBytes(FieldValue v) => v is StringValue || v is BlobValue;
bool _isArray(FieldValue v) => v is ArrayValue;
bool _isMap(FieldValue v) => v is ObjectValue;
bool _isNumber(FieldValue v) => v is NumberValue;
bool _isInteger(FieldValue v) => v is IntegerValue || v is Int32FieldValue;
bool _isTimestamp(FieldValue v) => v is TimestampValue;
bool _isVector(FieldValue v) => v is VectorFieldValue;
bool _isBoolean(FieldValue v) => v is BoolValue;
bool _isReference(FieldValue v) => v is ReferenceValue;

int _integer(FieldValue v) =>
    v is Int32FieldValue ? v.intValue : exactInteger((v as IntegerValue).value);

String _text(FieldValue v) => (v as StringValue).value;

Uint8List _blob(FieldValue v) => (v as BlobValue).value.bytes;

List<FieldValue> _elements(FieldValue v) => (v as ArrayValue).internalValue;

// ---- functions about values, absence and errors ----

EvaluateResult _isError(_Call call) => _bool(call.arg(0).isError);

EvaluateResult _exists(_Call call) {
  final EvaluateResult result = call.arg(0);
  return result.isError ? _error : _bool(!result.isUnset);
}

EvaluateResult _isAbsent(_Call call) {
  final EvaluateResult result = call.arg(0);
  return result.isError ? _error : _bool(result.isUnset);
}

EvaluateResult _ifError(_Call call) {
  final EvaluateResult result = call.arg(0);
  return result.isError ? call.arg(1) : result;
}

EvaluateResult _ifAbsent(_Call call) {
  final EvaluateResult result = call.arg(0);
  return result.isUnset ? call.arg(1) : result;
}

EvaluateResult _ifNull(_Call call) {
  final EvaluateResult result = call.arg(0);
  return !result.isError && result.isNullOrUnset ? call.arg(1) : result;
}

EvaluateResult _coalesce(_Call call) {
  EvaluateResult last = _unset;
  for (int i = 0; i < call.length; i++) {
    last = call.arg(i);
    if (last.isError || !last.isNullOrUnset) {
      return last;
    }
  }
  return last;
}

/// The name of the type of [value], as `type()` returns it.
String _typeName(FieldValue value) {
  return switch (value) {
    NullValue() => 'null',
    BoolValue() => 'boolean',
    IntegerValue() => 'int64',
    Int32FieldValue() => 'int32',
    DoubleValue() => 'float64',
    Decimal128FieldValue() => 'decimal128',
    StringValue() => 'string',
    BlobValue() => 'bytes',
    TimestampValue() => 'timestamp',
    ReferenceValue() => 'reference',
    GeoPointValue() => 'geo_point',
    ArrayValue() => 'array',
    VectorFieldValue() => 'vector',
    ObjectValue() => 'map',
    MinKeyValue() => 'min_key',
    MaxKeyValue() => 'max_key',
    BsonObjectIdValue() => 'object_id',
    BsonTimestampValue() => 'bson_timestamp',
    RegexFieldValue() => 'regex',
    _ => throw UnsupportedExpression('type() of ${value.runtimeType}'),
  };
}

const Set<String> _typeNames = <String>{
  'null',
  'array',
  'boolean',
  'bytes',
  'timestamp',
  'geo_point',
  'number',
  'int32',
  'int64',
  'float64',
  'decimal128',
  'map',
  'reference',
  'string',
  'vector',
  'max_key',
  'min_key',
  'object_id',
  'regex',
  'bson_timestamp',
};

EvaluateResult _type(_Call call) {
  final EvaluateResult result = call.arg(0);
  if (result.isError) {
    return _error;
  }
  final FieldValue? value = result.value;
  return value == null ? _null : _string(_typeName(value));
}

EvaluateResult _isType(_Call call) {
  final String? type = call.literal(1);
  if (type == null || !_typeNames.contains(type)) {
    return _error;
  }
  final EvaluateResult result = call.arg(0);
  if (result.isError) {
    return _error;
  }
  final FieldValue? value = result.value;
  if (value == null) {
    return _null;
  }
  return _bool(
    type == 'number' ? value is NumberValue : _typeName(value) == type,
  );
}

EvaluateResult _array(_Call call) {
  final List<FieldValue> elements = <FieldValue>[];
  for (final EvaluateResult result in call.evalAll()) {
    if (result.isError) {
      return _error;
    }
    elements.add(result.value ?? NullValue.nullValue());
  }
  return _list(elements);
}

EvaluateResult _map(_Call call) {
  if (call.length.isOdd) {
    return _error;
  }
  final Map<String, FieldValue> entries = <String, FieldValue>{};
  final Set<String> keys = <String>{};
  for (int i = 0; i < call.length; i += 2) {
    final EvaluateResult key = call.arg(i);
    final EvaluateResult value = call.arg(i + 1);
    if (key.isError || value.isError) {
      return _error;
    }
    final FieldValue? keyValue = key.value;
    // It is against the contract of map() to have a key more than once.
    if (keyValue is! StringValue || !keys.add(keyValue.value)) {
      return _error;
    }
    final FieldValue? fieldValue = value.value;
    if (fieldValue != null) {
      entries[keyValue.value] = fieldValue;
    }
  }
  return EvaluateValue(ObjectValue.fromMap(entries));
}

EvaluateResult _currentTimestamp(_Call call) =>
    EvaluateValue(TimestampValue.valueOf(call.scope.evaluator._now()));

EvaluateResult _rand(_Call call) =>
    _double(call.scope.evaluator._random.nextDouble());

// ---- references ----

EvaluateResult _documentId(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isReference],
  (List<FieldValue> v) {
    final ResourcePath path = (v[0] as ReferenceValue).key.path;
    // The root of the database (the parent of a root document) has no id.
    if (path.isEmpty) {
      throw const _EvaluationError();
    }
    return _string(path.last);
  },
);

EvaluateResult _collectionId(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isReference],
  (List<FieldValue> v) {
    final ResourcePath path = (v[0] as ReferenceValue).key.path;
    if (path.length < 2) {
      throw const _EvaluationError();
    }
    return _string(path[path.length - 2]);
  },
);

/// `parent(reference)`: the document that contains the collection of the
/// document. For a document of a root collection that is the root of the
/// database (a reference with an empty path), which itself has no parent.
EvaluateResult _parent(_Call call) => _strict(
  call,
  <bool Function(FieldValue)?>[_isReference],
  (List<FieldValue> v) {
    final ReferenceValue reference = v[0] as ReferenceValue;
    final ResourcePath path = reference.key.path;
    if (path.length < 2) {
      return _null;
    }
    return EvaluateValue(
      ReferenceValue.valueOf(
        reference.databaseId,
        DocumentKey.fromPath(path.popLast().popLast()),
      ),
    );
  },
);

final Map<String, _Function> _functions = <String, _Function>{
  // Values, absence and errors.
  'is_error': _isError,
  'exists': _exists,
  'is_absent': _isAbsent,
  'if_error': _ifError,
  'if_absent': _ifAbsent,
  'if_null': _ifNull,
  'coalesce': _coalesce,
  'type': _type,
  'is_type': _isType,
  'array': _array,
  'map': _map,
  'current_timestamp': _currentTimestamp,
  'rand': _rand,
  'document_id': _documentId,
  'collection_id': _collectionId,
  'parent': _parent,
  ..._comparisonFunctions,
  ..._arithmeticFunctions,
  ..._stringFunctions,
  ..._arrayFunctions,
  ..._mapFunctions,
  ..._timestampFunctions,
  ..._vectorFunctions,
};
