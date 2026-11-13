// What the tests ported from the Android SDK call: the expression functions
// under the names of the Kotlin API, `evaluate`, and the assertions of
// Android's pipeline/testUtil.kt and of Truth.
//
// The Kotlin functions take a variable number of arguments; here they take
// optional positional parameters.

// ignore_for_file: non_constant_identifier_names, constant_identifier_names
// ignore_for_file: avoid_classes_with_only_static_members, directives_ordering

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show Blob, Timestamp, VectorValue;
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/expression_evaluator.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/expression.dart'
    show PipelineEncoder;
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart' as t;

export 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/evaluation/evaluate_result.dart';

final DatabaseId _databaseId = DatabaseId.forProject('project');
final UserDataConverter _converter = UserDataConverter(_databaseId);
final PipelineEncoder _encoder = PipelineEncoder(_databaseId);
final ExpressionEvaluator _evaluator = ExpressionEvaluator(_databaseId);

final int maxLong = int.parse('9223372036854775807');
final int minLong = int.parse('-9223372036854775808');
const int maxInt = 2147483647;
const int minInt = -2147483648;

/// A document to evaluate against.
class TestDocument {
  TestDocument(this.key, this.data);

  final DocumentKey key;
  final model.ObjectValue data;
}

TestDocument doc(String path, int version, Map<String, Object?> data) =>
    TestDocument(
      DocumentKey.fromPathString(path),
      encodeValue(data) as model.ObjectValue,
    );

final TestDocument EMPTY_DOC = doc('foo/1', 0, <String, Object?>{});

/// The model value of a plain value (Android's `Values.encodeValue`).
model.FieldValue encodeValue(Object? value) {
  if (value is model.FieldValue) {
    return value;
  } else if (value is Uint8List) {
    return model.BlobValue.valueOf(Blob(value));
  } else if (value is List) {
    return model.ArrayValue.fromList(value.map(encodeValue).toList());
  } else if (value is Map) {
    return model.ObjectValue.fromMap(<String, model.FieldValue>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key! as String: encodeValue(entry.value),
    });
  } else if (value is Uint8List) {
    return model.BlobValue.valueOf(Blob(value));
  }
  return _converter.parseQueryValue(value);
}

final model.FieldValue NULL_VALUE = model.NullValue.nullValue();

EvaluateResult evaluate(Expression expression, [TestDocument? document]) {
  final TestDocument input = document ?? EMPTY_DOC;
  return _evaluator.evaluate(
    expression.toProto(_encoder),
    EvaluationInput(input.data, key: input.key),
  );
}

const EvaluateResult EvaluateResultError = EvaluateResult.error;
const EvaluateResult EvaluateResultUnset = EvaluateResult.unset;

EvaluateResult EvaluateResultValue(Object? value) =>
    EvaluateValue(encodeValue(value));

/// The constructors of Android's `EvaluateResult` companion.
abstract final class EvaluateResults {
  static final EvaluateResult NULL = EvaluateResult.nullValue;
  static const EvaluateResult TRUE = EvaluateResult.trueValue;
  static const EvaluateResult FALSE = EvaluateResult.falseValue;
  static EvaluateResult boolean(bool? value) =>
      value == null ? NULL : EvaluateValue(encodeValue(value));
  static EvaluateResult long(int value) => EvaluateValue(encodeValue(value));
  static EvaluateResult double(num value) =>
      EvaluateValue(encodeValue(value.toDouble()));
  static EvaluateResult string(String value) =>
      EvaluateValue(encodeValue(value));
  static EvaluateResult list(List<Object?> values) =>
      EvaluateValue(encodeValue(values));
  static EvaluateResult timestamp(int seconds, int nanos) =>
      EvaluateValue(encodeValue(Timestamp(seconds, nanos)));
  static EvaluateResult value(Object? value) =>
      EvaluateValue(encodeValue(value));
}

extension EvaluateResultSuccess on EvaluateResult {
  /// Android counts a missing value as a success.
  bool get isSuccess => !this.isError;
}

/// Whether two values are the same value of the same type: Android compares
/// the protos, where the integer 1 is not the double 1.0 and NaN is NaN.
bool sameValue(model.FieldValue? a, model.FieldValue? b) {
  if (a == null || b == null) {
    return a == null && b == null;
  }
  if (a is model.ArrayValue && b is model.ArrayValue) {
    if (a.internalValue.length != b.internalValue.length) {
      return false;
    }
    for (int i = 0; i < a.internalValue.length; i++) {
      if (!sameValue(a.internalValue[i], b.internalValue[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is model.ObjectValue && b is model.ObjectValue) {
    if (a.internalValue.length != b.internalValue.length) {
      return false;
    }
    for (final MapEntry<String, model.FieldValue> entry in a.internalValue) {
      if (!sameValue(entry.value, b.internalValue[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a.runtimeType != b.runtimeType) {
    return false;
  }
  if (a is model.DoubleValue && b is model.DoubleValue) {
    final double x = a.value;
    final double y = b.value;
    return (x.isNaN && y.isNaN) || (x == y && x.isNegative == y.isNegative);
  }
  return a.compareTo(b) == 0;
}

bool _sameResult(EvaluateResult a, EvaluateResult b) =>
    a.isError == b.isError &&
    a.isUnset == b.isUnset &&
    sameValue(a.value, b.value);

String _message(String format, List<Object?> args) {
  int index = 0;
  return format.replaceAllMapped(
    RegExp('%s|%d'),
    (Match m) => index < args.length ? '${args[index++]}' : m[0]!,
  );
}

void assertEvaluatesTo(
  EvaluateResult result,
  Object? expected, [
  String format = '',
  Object? a1,
  Object? a2,
  Object? a3,
  Object? a4,
]) {
  final String reason = _message(format, <Object?>[a1, a2, a3, a4]);
  if (expected is EvaluateResult) {
    t.expect(
      _sameResult(result, expected),
      t.isTrue,
      reason: '$reason: expected $expected, got $result',
    );
    return;
  }
  final model.FieldValue value = encodeValue(expected);
  t.expect(
    !result.isError && sameValue(result.value, value),
    t.isTrue,
    reason: '$reason: expected $value, got $result',
  );
}

void assertEvaluatesToNull(
  EvaluateResult result, [
  String format = '',
  Object? a1,
  Object? a2,
  Object? a3,
  Object? a4,
]) {
  t.expect(
    result.value,
    t.isA<model.NullValue>(),
    reason:
        '${_message(format, <Object?>[a1, a2, a3, a4])}: expected null, got $result',
  );
}

void assertEvaluatesToUnset(
  EvaluateResult result, [
  String format = '',
  Object? a1,
  Object? a2,
  Object? a3,
  Object? a4,
]) {
  t.expect(
    result.isUnset,
    t.isTrue,
    reason:
        '${_message(format, <Object?>[a1, a2, a3, a4])}: expected unset, got $result',
  );
}

void assertEvaluatesToError(
  EvaluateResult result, [
  String format = '',
  Object? a1,
  Object? a2,
  Object? a3,
  Object? a4,
]) {
  t.expect(
    result.isError,
    t.isTrue,
    reason:
        '${_message(format, <Object?>[a1, a2, a3, a4])}: expected an error, got $result',
  );
}

/// The subset of Truth the tests use.
class Subject {
  Subject(this.actual, [this.reason]);

  final Object? actual;
  final String? reason;

  EvaluateResult get _result {
    final Object? value = actual;
    return value is Expression ? evaluate(value) : value! as EvaluateResult;
  }

  void isEqualTo(Object? expected) {
    final Object? value = actual;
    if (value is model.FieldValue || expected is model.FieldValue) {
      t.expect(
        sameValue(
          value as model.FieldValue?,
          expected == null ? null : encodeValue(expected),
        ),
        t.isTrue,
        reason: '${reason ?? ''} expected $expected, got $value',
      );
    } else if (value is EvaluateResult && expected is EvaluateResult) {
      t.expect(
        _sameResult(value, expected),
        t.isTrue,
        reason: '${reason ?? ''} expected $expected, got $value',
      );
    } else {
      t.expect(value, expected, reason: reason);
    }
  }

  void isTrue() => t.expect(actual, t.isTrue, reason: reason);
  void isFalse() => t.expect(actual, t.isFalse, reason: reason);
  void isNull() => t.expect(actual, t.isNull, reason: reason);
  void isSameInstanceAs(Object? expected) => isEqualTo(expected);

  void evaluatesTo(Object? expected) =>
      assertEvaluatesTo(_result, expected, reason ?? '$actual');
  void evaluatesToNull() => assertEvaluatesToNull(_result, reason ?? '$actual');
  void evaluatesToError() =>
      assertEvaluatesToError(_result, reason ?? '$actual');
  void evaluatesToUnset() =>
      assertEvaluatesToUnset(_result, reason ?? '$actual');

  Subject that(Object? value) => Subject(value, reason);

  /// `isWithin(tolerance).of(expected)`.
  Tolerance isWithin(double tolerance) =>
      Tolerance(actual! as double, tolerance, reason);
}

class Tolerance {
  Tolerance(this.actual, this.tolerance, this.reason);

  final double actual;
  final double tolerance;
  final String? reason;

  void of(double expected) =>
      t.expect(actual, t.closeTo(expected, tolerance), reason: reason);
}

extension ModelDouble on model.FieldValue {
  double get doubleValue => (this as model.DoubleValue).value;
}

Subject assertThat(Object? actual) => Subject(actual);

Subject assertWithMessage(
  String format, [
  Object? a1,
  Object? a2,
  Object? a3,
  Object? a4,
]) => Subject(null, _message(format, <Object?>[a1, a2, a3, a4]));

// ---- values ----

Blob blob([
  Object a = _none,
  Object b = _none,
  Object c = _none,
  Object d = _none,
  Object e = _none,
  Object f = _none,
  Object g = _none,
  Object h = _none,
  Object i = _none,
  Object j = _none,
  Object k = _none,
  Object l = _none,
  Object m = _none,
  Object n = _none,
  Object o = _none,
  Object p = _none,
]) => Blob(
  Uint8List.fromList(
    _args(<Object?>[
      a,
      b,
      c,
      d,
      e,
      f,
      g,
      h,
      i,
      j,
      k,
      l,
      m,
      n,
      o,
      p,
    ]).cast<int>(),
  ),
);

/// Android's `ByteString` and `Blob` factories.
abstract final class ByteString {
  static final Uint8List EMPTY = Uint8List(0);
  static Uint8List copyFromUtf8(String text) =>
      Uint8List.fromList(utf8.encode(text));
  static Uint8List copyFrom(List<int> bytes) => Uint8List.fromList(bytes);
  static Uint8List fromHex(String hex) => Uint8List.fromList(
    Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]),
  );
}

Blob blobFromByteString(List<int> bytes) => Blob(Uint8List.fromList(bytes));

model.FieldValue ref(String path) =>
    model.ReferenceValue.valueOf(_databaseId, DocumentKey.fromPathString(path));

// ---- expressions, under their Kotlin names ----

const Object _none = Object();

List<Object?> _args(List<Object?> args) => <Object?>[
  for (final Object? arg in args)
    if (!identical(arg, _none)) arg,
];

/// The first parameter of the Kotlin functions: a `String` there is the name
/// of a field.
Object? _first(Object? value) => value is String ? field(value) : value;

FunctionExpression _fn(String name, List<Object?> args) =>
    FunctionExpression(name, _args(args).map(_wrap).toList());

Object? _wrap(Object? value) {
  if (value is model.FieldValue) {
    return Constant.fromModel(value);
  } else if (value is Uint8List) {
    return Constant(Blob(value));
  }
  return value;
}

BooleanExpression _bool(String name, List<Object?> args) =>
    BooleanExpression(_fn(name, args));

Expression constant(Object? value) {
  final Object? wrapped = _wrap(value);
  return wrapped is Expression ? wrapped : Constant(wrapped);
}

Expression nullValue() => Constant(null);

Field field(String name) => Field.of(name);

/// An expression that fails. Android has an `error` function for its tests;
/// the backend has none, so this divides by zero.
Expression error([String message = '']) =>
    FunctionExpression('divide', <Object?>[Constant(1), Constant(0)]);

Expression array([
  Object? a = _none,
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
  Object? f = _none,
  Object? g = _none,
  Object? h = _none,
  Object? i = _none,
  Object? j = _none,
  Object? k = _none,
  Object? l = _none,
]) {
  final List<Object?> args = _args(<Object?>[
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
  ]);
  if (args.length == 1 && args[0] is List) {
    return _fn('array', args[0]! as List<Object?>);
  }
  return _fn('array', args);
}

Expression map(Map<String, Object?> entries) => _fn('map', <Object?>[
  for (final MapEntry<String, Object?> entry in entries.entries) ...<Object?>[
    Constant(entry.key),
    entry.value,
  ],
]);

Expression vector(List<double> values) => Constant(VectorValue(values));

/// The functions that take any number of arguments, with a list.
FunctionExpression logicalMaximumAll(List<Object?> args) =>
    _fn('maximum', args);
FunctionExpression logicalMinimumAll(List<Object?> args) =>
    _fn('minimum', args);
FunctionExpression stringConcatAll(List<Object?> args) =>
    _fn('string_concat', args);

FunctionExpression Function(Object?, Object?) _binary(String name) =>
    (Object? a, Object? b) => _fn(name, <Object?>[_first(a), b]);

FunctionExpression Function(Object?) _unary(String name) =>
    (Object? a) => _fn(name, <Object?>[_first(a)]);

BooleanExpression Function(Object?, Object?) _binaryBool(String name) =>
    (Object? a, Object? b) => _bool(name, <Object?>[_first(a), b]);

final FunctionExpression Function(Object?, Object?) add = _binary('add');
final FunctionExpression Function(Object?, Object?) subtract = _binary(
  'subtract',
);
final FunctionExpression Function(Object?, Object?) multiply = _binary(
  'multiply',
);
final FunctionExpression Function(Object?, Object?) divide = _binary('divide');
final FunctionExpression Function(Object?, Object?) mod = _binary('mod');
final FunctionExpression Function(Object?, Object?) pow = _binary('pow');
final FunctionExpression Function(Object?, Object?) log = _binary('log');
final FunctionExpression Function(Object?, Object?) roundToPrecision = _binary(
  'round',
);
final FunctionExpression Function(Object?) abs = _unary('abs');
final FunctionExpression Function(Object?) ceil = _unary('ceil');
final FunctionExpression Function(Object?) floor = _unary('floor');
final FunctionExpression Function(Object?) round = _unary('round');
final FunctionExpression Function(Object?) sqrt = _unary('sqrt');
final FunctionExpression Function(Object?) exp = _unary('exp');
final FunctionExpression Function(Object?) ln = _unary('ln');
final FunctionExpression Function(Object?) log10 = _unary('log10');

final BooleanExpression Function(Object?, Object?) equal = _binaryBool('equal');
final BooleanExpression Function(Object?, Object?) notEqual = _binaryBool(
  'not_equal',
);
final BooleanExpression Function(Object?, Object?) lessThan = _binaryBool(
  'less_than',
);
final BooleanExpression Function(Object?, Object?) lessThanOrEqual =
    _binaryBool('less_than_or_equal');
final BooleanExpression Function(Object?, Object?) greaterThan = _binaryBool(
  'greater_than',
);
final BooleanExpression Function(Object?, Object?) greaterThanOrEqual =
    _binaryBool('greater_than_or_equal');

Expression _listArgument(Object? values) =>
    values is List ? _fn('array', values) : constant(values);

BooleanExpression equalAny(Object? value, Object? values) =>
    _bool('equal_any', <Object?>[_first(value), _listArgument(values)]);
BooleanExpression notEqualAny(Object? value, Object? values) =>
    _bool('not_equal_any', <Object?>[_first(value), _listArgument(values)]);

BooleanExpression _variadicBool(String name, List<Object?> args) =>
    _bool(name, args);

BooleanExpression and(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _variadicBool('and', <Object?>[a, b, c, d, e]);
BooleanExpression or(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _variadicBool('or', <Object?>[a, b, c, d, e]);
BooleanExpression xor(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _variadicBool('xor', <Object?>[a, b, c, d, e]);
BooleanExpression not(Object? a) => _bool('not', <Object?>[a]);
FunctionExpression conditional(Object? condition, Object? a, Object? b) =>
    _fn('conditional', <Object?>[condition, a, b]);
BooleanExpression isError(Object? a) => _bool('is_error', <Object?>[a]);
BooleanExpression exists(Object? a) => _bool('exists', <Object?>[_first(a)]);

FunctionExpression logicalMaximum(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _fn('maximum', <Object?>[_first(a), b, c, d, e]);
FunctionExpression logicalMinimum(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _fn('minimum', <Object?>[_first(a), b, c, d, e]);

// Strings.
final FunctionExpression Function(Object?) charLength = _unary('char_length');
final FunctionExpression Function(Object?) byteLength = _unary('byte_length');
final FunctionExpression Function(Object?) toLower = _unary('to_lower');
final FunctionExpression Function(Object?) toUpper = _unary('to_upper');
final FunctionExpression Function(Object?) trim = _unary('trim');
final FunctionExpression Function(Object?) reverse = _unary('reverse');
final BooleanExpression Function(Object?, Object?) startsWith = _binaryBool(
  'starts_with',
);
final BooleanExpression Function(Object?, Object?) endsWith = _binaryBool(
  'ends_with',
);
final BooleanExpression Function(Object?, Object?) stringContains = _binaryBool(
  'string_contains',
);
final BooleanExpression Function(Object?, Object?) like = _binaryBool('like');
final BooleanExpression Function(Object?, Object?) regexContains = _binaryBool(
  'regex_contains',
);
final BooleanExpression Function(Object?, Object?) regexMatch = _binaryBool(
  'regex_match',
);
final FunctionExpression Function(Object?, Object?) regexFind = _binary(
  'regex_find',
);
final FunctionExpression Function(Object?, Object?) regexFindAll = _binary(
  'regex_find_all',
);
final FunctionExpression Function(Object?, Object?) join = _binary('join');
FunctionExpression substring(
  Object? value,
  Object? position, [
  Object? length = _none,
]) => _fn('substring', <Object?>[_first(value), position, length]);
FunctionExpression stringConcat(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _fn('string_concat', <Object?>[_first(a), b, c, d, e]);
FunctionExpression concat(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _fn('concat', <Object?>[_first(a), b, c, d, e]);

// Arrays.
final FunctionExpression Function(Object?) arrayLength = _unary('array_length');
final FunctionExpression Function(Object?) arrayReverse = _unary(
  'array_reverse',
);
final FunctionExpression Function(Object?) arrayFirst = _unary('array_first');
final FunctionExpression Function(Object?) arrayLast = _unary('array_last');
final FunctionExpression Function(Object?) arrayMaximum = _unary('maximum');
final FunctionExpression Function(Object?) arrayMinimum = _unary('minimum');
final FunctionExpression Function(Object?, Object?) arrayFirstN = _binary(
  'array_first_n',
);
final FunctionExpression Function(Object?, Object?) arrayLastN = _binary(
  'array_last_n',
);
final FunctionExpression Function(Object?, Object?) arrayMaximumN = _binary(
  'maximum_n',
);
final FunctionExpression Function(Object?, Object?) arrayMinimumN = _binary(
  'minimum_n',
);
final FunctionExpression Function(Object?, Object?) arrayGet = _binary(
  'array_get',
);
final FunctionExpression Function(Object?, Object?) arrayIndexOfAll = _binary(
  'array_index_of_all',
);
final BooleanExpression Function(Object?, Object?) arrayContains = _binaryBool(
  'array_contains',
);
BooleanExpression arrayContainsAny(Object? array, Object? values) => _bool(
  'array_contains_any',
  <Object?>[_first(array), _listArgument(values)],
);
BooleanExpression arrayContainsAll(Object? array, Object? values) => _bool(
  'array_contains_all',
  <Object?>[_first(array), _listArgument(values)],
);
FunctionExpression arrayIndexOf(Object? array, Object? value) =>
    _fn('array_index_of', <Object?>[_first(array), value, 'first']);
FunctionExpression arrayLastIndexOf(Object? array, Object? value) =>
    _fn('array_index_of', <Object?>[_first(array), value, 'last']);
FunctionExpression arrayConcat(
  Object? a, [
  Object? b = _none,
  Object? c = _none,
  Object? d = _none,
  Object? e = _none,
]) => _fn('array_concat', <Object?>[_first(a), b, c, d, e]);

// Maps.
final FunctionExpression Function(Object?, Object?) mapGet = _binary('map_get');

// Timestamps.
FunctionExpression timestampAdd(
  Object? timestamp,
  Object? unit,
  Object? amount,
) => _fn('timestamp_add', <Object?>[_first(timestamp), unit, amount]);
FunctionExpression timestampSubtract(
  Object? timestamp,
  Object? unit,
  Object? amount,
) => _fn('timestamp_subtract', <Object?>[_first(timestamp), unit, amount]);
final FunctionExpression Function(Object?) timestampToUnixMicros = _unary(
  'timestamp_to_unix_micros',
);
final FunctionExpression Function(Object?) timestampToUnixMillis = _unary(
  'timestamp_to_unix_millis',
);
final FunctionExpression Function(Object?) timestampToUnixSeconds = _unary(
  'timestamp_to_unix_seconds',
);
final FunctionExpression Function(Object?) unixMicrosToTimestamp = _unary(
  'unix_micros_to_timestamp',
);
final FunctionExpression Function(Object?) unixMillisToTimestamp = _unary(
  'unix_millis_to_timestamp',
);
final FunctionExpression Function(Object?) unixSecondsToTimestamp = _unary(
  'unix_seconds_to_timestamp',
);

// Vectors.
final FunctionExpression Function(Object?, Object?) cosineDistance = _binary(
  'cosine_distance',
);
final FunctionExpression Function(Object?, Object?) dotProduct = _binary(
  'dot_product',
);
final FunctionExpression Function(Object?, Object?) euclideanDistance = _binary(
  'euclidean_distance',
);
final FunctionExpression Function(Object?) vectorLength = _unary(
  'vector_length',
);

// ---- Kotlin conversions the tests use ----

extension KotlinBytes on Uint8List {
  Uint8List toByteArray() => this;
  Uint8List concat(Uint8List other) =>
      Uint8List.fromList(Uint8List.fromList(<int>[...this, ...other]));
}

extension KotlinString on String {
  String repeat(int count) => this * count;
  int get code => codeUnitAt(0);
  Uint8List toByteArray([Object? charset]) =>
      Uint8List.fromList(utf8.encode(this));
}

extension KotlinInt on int {
  int toByte() => this & 0xff;
}

extension KotlinList on List<Object?> {
  List<double> toDoubleArray() =>
      cast<num>().map((num n) => n.toDouble()).toList();
}
