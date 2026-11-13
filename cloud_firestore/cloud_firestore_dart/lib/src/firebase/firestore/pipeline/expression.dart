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

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/pipeline/window.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pb;
import 'package:meta/meta.dart';

/// Converts pipeline building blocks to their wire representation.
@internal
class PipelineEncoder {
  PipelineEncoder(DatabaseId databaseId)
    : serializer = RemoteSerializer(databaseId),
      _converter = UserDataConverter(databaseId);

  final RemoteSerializer serializer;
  final UserDataConverter _converter;

  /// Encodes a plain user value (number, string, `Timestamp`, `GeoPoint`,
  /// `VectorValue`, `DocumentReference`, list, map, ...).
  pb.Value encodeUserValue(Object? value) {
    return serializer.encodeValue(
      _converter.parseQueryValue(value, allowArrays: true),
    );
  }

  /// Encodes a value that is already in the internal model.
  pb.Value encodeModelValue(model.FieldValue value) {
    return serializer.encodeValue(value);
  }
}

/// Wraps [value] in an [Expression] unless it already is one.
///
/// Maps become a `map` function and lists an `array` function, so that they
/// may contain nested expressions. Everything else becomes a [Constant].
@internal
Expression toExpression(Object? value) {
  if (value is Expression) {
    return value;
  } else if (value is Map) {
    final List<Expression> args = <Expression>[];
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw ArgumentError('Map keys must be strings, but found: $key');
      }
      args
        ..add(Constant(key))
        ..add(toExpression(entry.value));
    }
    return FunctionExpression('map', args);
  } else if (value is List) {
    return FunctionExpression(
      'array',
      value.map(toExpression).toList(growable: false),
    );
  } else {
    return Constant(value);
  }
}

/// Wraps [value] in an expression, reading a [String] as a field name.
@internal
Expression fieldOrExpression(Object value) {
  if (value is String) {
    return Field.of(value);
  } else if (value is FieldPath) {
    return Field.of(value);
  }
  return toExpression(value);
}

Expression _listArgument(Object values, String method) {
  if (values is Expression) {
    return values;
  } else if (values is List) {
    return _ListOfExpressions(values.map(toExpression).toList(growable: false));
  }
  throw ArgumentError(
    '$method() expects a List or an Expression, but got: $values',
  );
}

Expression _vectorArgument(Object vector) {
  if (vector is Expression) {
    return vector;
  } else if (vector is VectorValue) {
    return Constant(vector);
  } else if (vector is List<double>) {
    return Constant(VectorValue(vector));
  }
  throw ArgumentError(
    'A vector must be a VectorValue, a List<double> or an Expression, but '
    'got: $vector',
  );
}

/// A value computed by the server while it runs a pipeline: a [Field]
/// reference, a [Constant], or a [FunctionExpression] over other expressions.
///
/// Wherever a method takes an `Object?` operand, an [Expression] is used as is
/// and any other value is treated as a constant.
///
/// **Preview**: the Pipelines API is experimental and may change.
abstract class Expression {
  /// Returns the wire representation of this expression.
  @internal
  pb.Value toProto(PipelineEncoder encoder);

  /// Gives this expression a name, for use in `select`, `addFields` and
  /// `distinct`.
  AliasedExpression as(String alias) => AliasedExpression(this, alias);

  /// Sorts by this expression, smallest first.
  Ordering ascending() => Ordering(this, OrderingDirection.ascending);

  /// Sorts by this expression, largest first.
  Ordering descending() => Ordering(this, OrderingDirection.descending);

  /// Treats this expression as a boolean, so that it can be used as a
  /// condition (for example a field that holds a boolean).
  BooleanExpression asBoolean() {
    final Expression self = this;
    return self is BooleanExpression ? self : BooleanExpression(self);
  }

  FunctionExpression _function(
    String name, [
    List<Object?> others = const <Object?>[],
  ]) {
    return FunctionExpression(name, <Expression>[
      this,
      ...others.map(toExpression),
    ]);
  }

  BooleanExpression _condition(
    String name, [
    List<Object?> others = const <Object?>[],
  ]) {
    return BooleanExpression(_function(name, others));
  }

  // Comparison

  /// Whether this expression is equal to [other].
  BooleanExpression equal(Object? other) =>
      _condition('equal', <Object?>[other]);

  /// Whether this expression is not equal to [other].
  BooleanExpression notEqual(Object? other) =>
      _condition('not_equal', <Object?>[other]);

  /// Whether this expression is less than [other].
  BooleanExpression lessThan(Object? other) =>
      _condition('less_than', <Object?>[other]);

  /// Whether this expression is less than or equal to [other].
  BooleanExpression lessThanOrEqual(Object? other) =>
      _condition('less_than_or_equal', <Object?>[other]);

  /// Whether this expression is greater than [other].
  BooleanExpression greaterThan(Object? other) =>
      _condition('greater_than', <Object?>[other]);

  /// Whether this expression is greater than or equal to [other].
  BooleanExpression greaterThanOrEqual(Object? other) =>
      _condition('greater_than_or_equal', <Object?>[other]);

  /// Whether this expression is equal to any of [values], a `List` of values
  /// or expressions, or an [Expression] that evaluates to an array.
  BooleanExpression equalAny(Object values) => BooleanExpression(
    FunctionExpression('equal_any', <Expression>[
      this,
      _listArgument(values, 'equalAny'),
    ]),
  );

  /// Whether this expression is equal to none of [values], a `List` of values
  /// or expressions, or an [Expression] that evaluates to an array.
  BooleanExpression notEqualAny(Object values) => BooleanExpression(
    FunctionExpression('not_equal_any', <Expression>[
      this,
      _listArgument(values, 'notEqualAny'),
    ]),
  );

  // Existence and errors

  /// Whether this expression (usually a [Field]) has a value in the document.
  BooleanExpression exists() => _condition('exists');

  /// Whether this expression has no value in the document.
  BooleanExpression isAbsent() => _condition('is_absent');

  /// Whether evaluating this expression produces an error.
  BooleanExpression isError() => _condition('is_error');

  // Arithmetic

  /// Adds [other] to this expression.
  FunctionExpression add(Object? other) => _function('add', <Object?>[other]);

  /// Subtracts [other] from this expression.
  FunctionExpression subtract(Object? other) =>
      _function('subtract', <Object?>[other]);

  /// Multiplies this expression by [other].
  FunctionExpression multiply(Object? other) =>
      _function('multiply', <Object?>[other]);

  /// Divides this expression by [other].
  FunctionExpression divide(Object? other) =>
      _function('divide', <Object?>[other]);

  /// The remainder of dividing this expression by [other].
  FunctionExpression mod(Object? other) => _function('mod', <Object?>[other]);

  // Arrays

  /// Whether this array contains [element].
  BooleanExpression arrayContains(Object? element) =>
      _condition('array_contains', <Object?>[element]);

  /// Whether this array contains at least one of [values], a `List` of values
  /// or expressions, or an [Expression] that evaluates to an array.
  BooleanExpression arrayContainsAny(Object values) => BooleanExpression(
    FunctionExpression('array_contains_any', <Expression>[
      this,
      _listArgument(values, 'arrayContainsAny'),
    ]),
  );

  /// Whether this array contains all of [values], a `List` of values or
  /// expressions, or an [Expression] that evaluates to an array.
  BooleanExpression arrayContainsAll(Object values) => BooleanExpression(
    FunctionExpression('array_contains_all', <Expression>[
      this,
      _listArgument(values, 'arrayContainsAll'),
    ]),
  );

  /// The number of elements of this array.
  FunctionExpression arrayLength() => _function('array_length');

  // Strings

  /// Concatenates this string with [others].
  FunctionExpression stringConcat(List<Object?> others) =>
      _function('string_concat', others);

  /// Whether this string starts with [prefix].
  BooleanExpression startsWith(Object prefix) =>
      _condition('starts_with', <Object?>[prefix]);

  /// Whether this string ends with [suffix].
  BooleanExpression endsWith(Object suffix) =>
      _condition('ends_with', <Object?>[suffix]);

  /// Whether this string contains [substring].
  BooleanExpression stringContains(Object substring) =>
      _condition('string_contains', <Object?>[substring]);

  /// This string in lower case.
  FunctionExpression toLower() => _function('to_lower');

  /// This string in upper case.
  FunctionExpression toUpper() => _function('to_upper');

  /// This string without leading and trailing whitespace, or without the
  /// leading and trailing characters of [characters] when given.
  FunctionExpression trim([Object? characters]) =>
      _function('trim', <Object?>[if (characters != null) characters]);

  /// Like [trim], for the start of the string only.
  FunctionExpression ltrim([Object? characters]) =>
      _function('ltrim', <Object?>[if (characters != null) characters]);

  /// Like [trim], for the end of the string only.
  FunctionExpression rtrim([Object? characters]) =>
      _function('rtrim', <Object?>[if (characters != null) characters]);

  /// The number of bytes of this string (in UTF-8) or of these bytes.
  FunctionExpression byteLength() => _function('byte_length');

  /// The length of this string, array, map, vector or bytes value.
  FunctionExpression length() => _function('length');

  /// The part of this string that starts at [position] (0-based) and has
  /// [length] characters, or runs to the end without [length].
  FunctionExpression substring(Object position, [Object? length]) =>
      _function('substring', <Object?>[position, if (length != null) length]);

  /// The parts of this string between occurrences of [delimiter].
  FunctionExpression split(Object delimiter) =>
      _function('split', <Object?>[delimiter]);

  /// The elements of this array of strings, joined with [delimiter].
  FunctionExpression join(Object delimiter) =>
      _function('join', <Object?>[delimiter]);

  /// This string with every occurrence of [find] replaced by [replacement].
  FunctionExpression stringReplaceAll(Object find, Object replacement) =>
      _function('string_replace_all', <Object?>[find, replacement]);

  /// This string with the first occurrence of [find] replaced by
  /// [replacement].
  FunctionExpression stringReplaceOne(Object find, Object replacement) =>
      _function('string_replace_one', <Object?>[find, replacement]);

  /// This string repeated [repetitions] times.
  FunctionExpression stringRepeat(Object repetitions) =>
      _function('string_repeat', <Object?>[repetitions]);

  /// The position of the first occurrence of [search] in this string, or -1.
  FunctionExpression stringIndexOf(Object search) =>
      _function('string_index_of', <Object?>[search]);

  /// This string with its characters in reverse order.
  FunctionExpression stringReverse() => _function('string_reverse');

  /// This string, array or bytes value in reverse order.
  FunctionExpression reverse() => _function('reverse');

  /// This value concatenated with [others] (strings, arrays or bytes).
  FunctionExpression concat(List<Object?> others) =>
      _function('concat', others);

  /// The first part of this string that matches the regular expression
  /// [pattern].
  FunctionExpression regexFind(Object pattern) =>
      _function('regex_find', <Object?>[pattern]);

  /// All parts of this string that match the regular expression [pattern].
  FunctionExpression regexFindAll(Object pattern) =>
      _function('regex_find_all', <Object?>[pattern]);

  /// The number of characters of this string.
  FunctionExpression charLength() => _function('char_length');

  /// Whether this string matches the SQL-style `LIKE` [pattern].
  BooleanExpression like(Object pattern) =>
      _condition('like', <Object?>[pattern]);

  /// Whether the whole string matches the regular expression [pattern].
  BooleanExpression regexMatch(Object pattern) =>
      _condition('regex_match', <Object?>[pattern]);

  /// Whether a part of this string matches the regular expression [pattern].
  BooleanExpression regexContains(Object pattern) =>
      _condition('regex_contains', <Object?>[pattern]);

  // Maps and documents

  /// The value stored under [key] in this map.
  FunctionExpression mapGet(String key) => _function('map_get', <Object?>[key]);

  /// The document id of this document reference (or document path).
  FunctionExpression documentId() => _function('document_id');

  // Math

  /// The absolute value of this number.
  FunctionExpression abs() => _function('abs');

  /// This number rounded up to a whole number.
  FunctionExpression ceil() => _function('ceil');

  /// This number rounded down to a whole number.
  FunctionExpression floor() => _function('floor');

  /// This number rounded to [decimalPlaces] (to a whole number without it).
  FunctionExpression round([Object? decimalPlaces]) =>
      _function('round', <Object?>[if (decimalPlaces != null) decimalPlaces]);

  /// This number cut off after [decimalPlaces] (at the decimal point without
  /// it).
  FunctionExpression trunc([Object? decimalPlaces]) =>
      _function('trunc', <Object?>[if (decimalPlaces != null) decimalPlaces]);

  /// This number raised to the power [exponent].
  FunctionExpression pow(Object exponent) =>
      _function('pow', <Object?>[exponent]);

  /// The square root of this number.
  FunctionExpression sqrt() => _function('sqrt');

  /// Euler's number raised to the power of this number.
  FunctionExpression exp() => _function('exp');

  /// The natural logarithm of this number.
  FunctionExpression ln() => _function('ln');

  /// The logarithm of this number to the given [base].
  FunctionExpression log(Object base) => _function('log', <Object?>[base]);

  /// The base 10 logarithm of this number.
  FunctionExpression log10() => _function('log10');

  /// The largest of this value and [others], in Firestore's value ordering.
  FunctionExpression logicalMaximum(List<Object?> others) =>
      _function('maximum', others);

  /// The smallest of this value and [others], in Firestore's value ordering.
  FunctionExpression logicalMinimum(List<Object?> others) =>
      _function('minimum', others);

  // Timestamps

  /// This timestamp plus [amount] of [unit] (`'microsecond'`,
  /// `'millisecond'`, `'second'`, `'minute'`, `'hour'` or `'day'`).
  FunctionExpression timestampAdd(Object unit, Object amount) =>
      _function('timestamp_add', <Object?>[unit, amount]);

  /// This timestamp minus [amount] of [unit]; see [timestampAdd].
  FunctionExpression timestampSubtract(Object unit, Object amount) =>
      _function('timestamp_subtract', <Object?>[unit, amount]);

  /// The number of whole [unit]s from [start] (a field name or an
  /// expression) to this timestamp.
  FunctionExpression timestampDiff(Object start, Object unit) =>
      FunctionExpression('timestamp_diff', <Object?>[
        this,
        fieldOrExpression(start),
        unit,
      ]);

  /// This timestamp truncated to [granularity] (for example `'day'`),
  /// optionally in [timezone].
  FunctionExpression timestampTruncate(
    Object granularity, [
    Object? timezone,
  ]) => _function('timestamp_trunc', <Object?>[
    granularity,
    if (timezone != null) timezone,
  ]);

  /// The [part] (for example `'year'` or `'dayofweek'`) of this timestamp,
  /// optionally in [timezone].
  FunctionExpression timestampExtract(Object part, [Object? timezone]) =>
      _function('timestamp_extract', <Object?>[
        part,
        if (timezone != null) timezone,
      ]);

  /// This timestamp as microseconds since the Unix epoch.
  FunctionExpression timestampToUnixMicros() =>
      _function('timestamp_to_unix_micros');

  /// This timestamp as milliseconds since the Unix epoch.
  FunctionExpression timestampToUnixMillis() =>
      _function('timestamp_to_unix_millis');

  /// This timestamp as seconds since the Unix epoch.
  FunctionExpression timestampToUnixSeconds() =>
      _function('timestamp_to_unix_seconds');

  /// The timestamp this number of microseconds after the Unix epoch.
  FunctionExpression unixMicrosToTimestamp() =>
      _function('unix_micros_to_timestamp');

  /// The timestamp this number of milliseconds after the Unix epoch.
  FunctionExpression unixMillisToTimestamp() =>
      _function('unix_millis_to_timestamp');

  /// The timestamp this number of seconds after the Unix epoch.
  FunctionExpression unixSecondsToTimestamp() =>
      _function('unix_seconds_to_timestamp');

  // Vectors

  /// The cosine distance between this vector and [other] (a `VectorValue`, a
  /// `List<double>` or an expression).
  FunctionExpression cosineDistance(Object other) =>
      _function('cosine_distance', <Object?>[_vectorArgument(other)]);

  /// The dot product of this vector and [other]; see [cosineDistance].
  FunctionExpression dotProduct(Object other) =>
      _function('dot_product', <Object?>[_vectorArgument(other)]);

  /// The Euclidean distance between this vector and [other]; see
  /// [cosineDistance].
  FunctionExpression euclideanDistance(Object other) =>
      _function('euclidean_distance', <Object?>[_vectorArgument(other)]);

  /// The number of dimensions of this vector.
  FunctionExpression vectorLength() => _function('vector_length');

  // More arrays

  /// This array followed by the elements of the arrays in [others].
  FunctionExpression arrayConcat(List<Object?> others) =>
      _function('array_concat', others);

  /// The element at [index] of this array (negative counts from the end).
  FunctionExpression arrayGet(Object index) =>
      _function('array_get', <Object?>[index]);

  /// The elements of this array from [offset], at most [length] of them.
  FunctionExpression arraySlice(Object offset, [Object? length]) =>
      _function('array_slice', <Object?>[offset, if (length != null) length]);

  /// This array in reverse order.
  FunctionExpression arrayReverse() => _function('array_reverse');

  /// The first element of this array.
  FunctionExpression arrayFirst() => _function('array_first');

  /// The first [n] elements of this array.
  FunctionExpression arrayFirstN(Object n) =>
      _function('array_first_n', <Object?>[n]);

  /// The last element of this array.
  FunctionExpression arrayLast() => _function('array_last');

  /// The last [n] elements of this array.
  FunctionExpression arrayLastN(Object n) =>
      _function('array_last_n', <Object?>[n]);

  /// The position of the first occurrence of [search] in this array, or -1.
  FunctionExpression arrayIndexOf(Object? search) =>
      _function('array_index_of', <Object?>[search, 'first']);

  /// The position of the last occurrence of [search] in this array, or -1.
  FunctionExpression arrayLastIndexOf(Object? search) =>
      _function('array_index_of', <Object?>[search, 'last']);

  /// The positions of all occurrences of [search] in this array.
  FunctionExpression arrayIndexOfAll(Object? search) =>
      _function('array_index_of_all', <Object?>[search]);

  /// The elements of this array for which [filter] holds.
  ///
  /// [filter] is called once, with an expression that stands for the current
  /// element, to build the condition:
  ///
  /// ```dart
  /// field('scores').arrayFilter((score) => score.greaterThan(50));
  /// ```
  ///
  /// [alias] is the name of the server-side variable that holds the element;
  /// change it when lambdas are nested.
  FunctionExpression arrayFilter(
    BooleanExpression Function(Expression element) filter, {
    String alias = 'element',
  }) {
    return _function('array_filter', <Object?>[
      alias,
      filter(VariableExpression(alias)),
    ]);
  }

  /// This array with every element replaced by the result of [transform].
  ///
  /// [transform] is called once, with an expression that stands for the
  /// current element; a result that is not an [Expression] is a constant.
  ///
  /// ```dart
  /// field('prices').arrayTransform((price) => price.multiply(2));
  /// ```
  ///
  /// [alias] is the name of the server-side variable that holds the element.
  FunctionExpression arrayTransform(
    Object? Function(Expression element) transform, {
    String alias = 'element',
  }) {
    return _function('array_transform', <Object?>[
      alias,
      toExpression(transform(VariableExpression(alias))),
    ]);
  }

  /// Like [arrayTransform], but [transform] also receives an expression for
  /// the position of the element in the array.
  FunctionExpression arrayTransformWithIndex(
    Object? Function(Expression element, Expression index) transform, {
    String elementAlias = 'element',
    String indexAlias = 'index',
  }) {
    return _function('array_transform', <Object?>[
      elementAlias,
      indexAlias,
      toExpression(
        transform(
          VariableExpression(elementAlias),
          VariableExpression(indexAlias),
        ),
      ),
    ]);
  }

  /// The largest element of this array.
  FunctionExpression arrayMaximum() => _function('maximum');

  /// The smallest element of this array.
  FunctionExpression arrayMinimum() => _function('minimum');

  /// The sum of the numeric elements of this array.
  FunctionExpression arraySum() => _function('sum');

  /// The [n] largest elements of this array, largest first.
  FunctionExpression arrayMaximumN(Object n) =>
      _function('maximum_n', <Object?>[n]);

  /// The [n] smallest elements of this array, smallest first.
  FunctionExpression arrayMinimumN(Object n) =>
      _function('minimum_n', <Object?>[n]);

  // More maps

  /// This map merged with [second] and [others]; later maps win.
  FunctionExpression mapMerge(
    Object second, [
    List<Object> others = const <Object>[],
  ]) => _function('map_merge', <Object?>[second, ...others]);

  /// This map without the entry for [key].
  FunctionExpression mapRemove(Object key) =>
      _function('map_remove', <Object?>[key]);

  /// This map with [key] set to [value].
  ///
  /// [moreKeyValues] continues with further key/value pairs:
  /// `mapSet('a', 1, ['b', 2])` sets both `a` and `b`.
  FunctionExpression mapSet(
    Object key,
    Object? value, [
    List<Object?> moreKeyValues = const <Object?>[],
  ]) {
    if (moreKeyValues.length.isOdd) {
      throw ArgumentError(
        'mapSet() takes key/value pairs, but moreKeyValues has an odd number '
        'of elements: $moreKeyValues',
      );
    }
    return _function('map_set', <Object?>[key, value, ...moreKeyValues]);
  }

  /// The value of the field [key] of this map or document, for example of
  /// `currentDocument()` or of a variable that holds a document.
  FunctionExpression getField(Object key) =>
      _function('get_field', <Object?>[key]);

  /// The keys of this map.
  FunctionExpression mapKeys() => _function('map_keys');

  /// The values of this map.
  FunctionExpression mapValues() => _function('map_values');

  /// The entries of this map, as an array of maps with `k` and `v`.
  FunctionExpression mapEntries() => _function('map_entries');

  // Types, missing values and errors

  /// The name of the type of this value (for example `'string'`).
  FunctionExpression type() => _function('type');

  /// Whether this value is of the type with the name [type].
  BooleanExpression isType(String type) =>
      _condition('is_type', <Object?>[type]);

  /// This value, or [elseValue] if it is absent.
  FunctionExpression ifAbsent(Object? elseValue) =>
      _function('if_absent', <Object?>[elseValue]);

  /// This value, or [catchValue] if evaluating it fails.
  FunctionExpression ifError(Object? catchValue) =>
      _function('if_error', <Object?>[catchValue]);

  /// This value, or [elseValue] if it is null.
  FunctionExpression ifNull(Object? elseValue) =>
      _function('if_null', <Object?>[elseValue]);

  /// The first of this value, [replacement] and [others] that is neither
  /// null nor absent.
  FunctionExpression coalesce(
    Object? replacement, [
    List<Object?> others = const <Object?>[],
  ]) => _function('coalesce', <Object?>[replacement, ...others]);

  // References and locations

  /// The id of the collection of this document reference.
  FunctionExpression collectionId() => _function('collection_id');

  /// The parent of this document reference.
  FunctionExpression parent() => _function('parent');

  /// The distance in meters between this location and [location] (a
  /// `GeoPoint` or an expression).
  FunctionExpression geoDistance(Object location) =>
      _function('geo_distance', <Object?>[location]);

  // Aggregates

  /// Counts the inputs for which this expression has a value.
  AggregateFunction count() => AggregateFunction('count', <Expression>[this]);

  /// Counts the distinct values of this expression.
  AggregateFunction countDistinct() =>
      AggregateFunction('count_distinct', <Expression>[this]);

  /// Sums the values of this expression.
  AggregateFunction sum() => AggregateFunction('sum', <Expression>[this]);

  /// Averages the values of this expression.
  AggregateFunction average() =>
      AggregateFunction('average', <Expression>[this]);

  /// The smallest value of this expression.
  AggregateFunction minimum() =>
      AggregateFunction('minimum', <Expression>[this]);

  /// The largest value of this expression.
  AggregateFunction maximum() =>
      AggregateFunction('maximum', <Expression>[this]);

  /// The value of this expression for the first input.
  AggregateFunction first() => AggregateFunction('first', <Expression>[this]);

  /// The value of this expression for the last input.
  AggregateFunction last() => AggregateFunction('last', <Expression>[this]);

  /// All values of this expression, as an array.
  AggregateFunction arrayAgg() =>
      AggregateFunction('array_agg', <Expression>[this]);

  /// The distinct values of this expression, as an array.
  AggregateFunction arrayAggDistinct() =>
      AggregateFunction('array_agg_distinct', <Expression>[this]);
}

/// An expression with a name: something that can be selected into a result.
abstract class Selectable {
  /// The name of the output field.
  String get alias;

  /// The expression that produces the value.
  Expression get expression;
}

/// A reference to a field of the input document.
class Field extends Expression implements Selectable {
  @internal
  Field(this.path);

  /// Creates a field reference from a dot-separated [String] or a
  /// [FieldPath]. `__name__` refers to the document name.
  factory Field.of(Object nameOrPath) {
    if (nameOrPath is FieldPath) {
      return Field(nameOrPath.internalPath);
    } else if (nameOrPath is String) {
      if (nameOrPath == documentIdName) {
        return Field(model.FieldPath.keyPath);
      }
      return Field(FieldPath.fromDotSeparatedPath(nameOrPath).internalPath);
    }
    throw ArgumentError(
      'A field must be a String or a FieldPath, but got: $nameOrPath',
    );
  }

  /// The field name that refers to the document name (key).
  static const String documentIdName = '__name__';

  @internal
  final model.FieldPath path;

  /// The dot-separated (and escaped where needed) name of the field.
  String get fieldName => path.canonicalString;

  @override
  String get alias => fieldName;

  @override
  Expression get expression => this;

  @override
  pb.Value toProto(PipelineEncoder encoder) {
    return pb.Value()..fieldReferenceValue = fieldName;
  }

  @override
  bool operator ==(Object other) => other is Field && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Field($fieldName)';
}

/// A fixed value.
class Constant extends Expression {
  /// Creates a constant from a plain value: `null`, `bool`, `int`, `double`,
  /// `String`, `DateTime`, `Timestamp`, `GeoPoint`, `Blob`, `VectorValue`,
  /// `DocumentReference`, or lists and maps of those.
  Constant(this.value) : _modelValue = null;

  @internal
  Constant.fromModel(model.FieldValue value)
    : value = value.value,
      _modelValue = value;

  /// The user value of this constant.
  final Object? value;
  final model.FieldValue? _modelValue;

  @override
  pb.Value toProto(PipelineEncoder encoder) {
    final model.FieldValue? modelValue = _modelValue;
    return modelValue != null
        ? encoder.encodeModelValue(modelValue)
        : encoder.encodeUserValue(value);
  }

  @override
  String toString() => 'Constant($value)';
}

/// A reference to a variable: one defined with `Pipeline.define`, or the
/// element of a lambda such as [Expression.arrayFilter]. Create it with
/// `variable(name)`.
class VariableExpression extends Expression {
  /// A reference to the variable [name].
  VariableExpression(this.name);

  /// The name of the variable.
  final String name;

  @override
  pb.Value toProto(PipelineEncoder encoder) {
    return pb.Value()..variableReferenceValue = name;
  }

  @override
  String toString() => 'Variable($name)';
}

/// An expression whose wire form is built by a callback (a pipeline used as a
/// value).
@internal
class RawValueExpression extends Expression {
  RawValueExpression(this._build, this._description);

  final pb.Value Function(PipelineEncoder encoder) _build;
  final String _description;

  @override
  pb.Value toProto(PipelineEncoder encoder) => _build(encoder);

  @override
  String toString() => _description;
}

/// A list of expressions encoded as a plain array (the operand of `equalAny`
/// and friends).
class _ListOfExpressions extends Expression {
  _ListOfExpressions(this.expressions);

  final List<Expression> expressions;

  @override
  pb.Value toProto(PipelineEncoder encoder) {
    return pb.Value()
      ..arrayValue = (pb.ArrayValue()
        ..values.addAll(expressions.map((Expression e) => e.toProto(encoder))));
  }
}

/// A call of a server function.
///
/// Every typed helper (such as [Expression.add]) creates one of these. Create
/// it directly to call a function this SDK has no helper for yet:
///
/// ```dart
/// FunctionExpression('to_lower', [field('title')]);
/// ```
class FunctionExpression extends Expression {
  /// Creates a call of the server function [name] (snake case) with [args].
  /// Arguments that are not expressions are treated as constants.
  FunctionExpression(this.name, [List<Object?> args = const <Object?>[]])
    : args = List<Expression>.unmodifiable(args.map(toExpression));

  /// The server name of the function.
  final String name;

  /// The arguments of the call.
  final List<Expression> args;

  @override
  pb.Value toProto(PipelineEncoder encoder) {
    return pb.Value()
      ..functionValue = (pb.Function_()
        ..name = name
        ..args.addAll(args.map((Expression e) => e.toProto(encoder))));
  }

  @override
  String toString() => '$name(${args.join(', ')})';
}

/// An expression that evaluates to a boolean: the condition of
/// `Pipeline.where`.
class BooleanExpression extends Expression {
  /// Treats [expression] as a boolean. Prefer [Expression.asBoolean].
  BooleanExpression(this.expression);

  /// The wrapped expression.
  final Expression expression;

  @override
  pb.Value toProto(PipelineEncoder encoder) => expression.toProto(encoder);

  /// The negation of this condition.
  BooleanExpression not() => _condition('not');

  /// Whether this condition and all of [others] hold.
  BooleanExpression and(
    BooleanExpression other, [
    List<BooleanExpression> others = const <BooleanExpression>[],
  ]) => _condition('and', <Object?>[other, ...others]);

  /// Whether this condition or any of [others] holds.
  BooleanExpression or(
    BooleanExpression other, [
    List<BooleanExpression> others = const <BooleanExpression>[],
  ]) => _condition('or', <Object?>[other, ...others]);

  /// Whether neither this condition nor any of [others] holds.
  BooleanExpression nor(
    BooleanExpression other, [
    List<BooleanExpression> others = const <BooleanExpression>[],
  ]) => _condition('nor', <Object?>[other, ...others]);

  /// Whether an odd number of this condition and [others] hold.
  BooleanExpression xor(
    BooleanExpression other, [
    List<BooleanExpression> others = const <BooleanExpression>[],
  ]) => _condition('xor', <Object?>[other, ...others]);

  /// [thenValue] if this condition holds, [elseValue] otherwise.
  FunctionExpression conditional(Object? thenValue, Object? elseValue) =>
      _function('conditional', <Object?>[thenValue, elseValue]);

  /// Counts the inputs for which this condition holds.
  AggregateFunction countIf() =>
      AggregateFunction('count_if', <Expression>[this]);

  @override
  String toString() => expression.toString();
}

/// An [Expression] with a name, created with [Expression.as].
class AliasedExpression implements Selectable {
  AliasedExpression(this.expression, this.alias);

  @override
  final Expression expression;

  @override
  final String alias;

  @override
  String toString() => '$expression as $alias';
}

/// The direction of an [Ordering].
enum OrderingDirection {
  ascending('ascending'),
  descending('descending');

  const OrderingDirection(this.serverName);

  @internal
  final String serverName;
}

/// A sort key of `Pipeline.sort`, created with [Expression.ascending] or
/// [Expression.descending].
class Ordering {
  Ordering(this.expression, this.direction);

  /// The expression to sort by.
  final Expression expression;

  /// Whether smaller or larger values come first.
  final OrderingDirection direction;

  @internal
  pb.Value toProto(PipelineEncoder encoder) {
    return pb.Value()
      ..mapValue = (pb.MapValue()
        ..fields['direction'] = (pb.Value()..stringValue = direction.serverName)
        ..fields['expression'] = expression.toProto(encoder));
  }

  @override
  String toString() => '$expression ${direction.serverName}';
}

/// A function that combines the values of many inputs into one, for use in
/// `Pipeline.aggregate`.
///
/// Create it directly to call an aggregate this SDK has no helper for yet.
class AggregateFunction {
  /// Creates a call of the server aggregate [name] (snake case) with [args].
  AggregateFunction(this.name, [List<Object?> args = const <Object?>[]])
    : args = List<Expression>.unmodifiable(args.map(toExpression));

  /// The server name of the aggregate.
  final String name;

  /// The arguments of the call.
  final List<Expression> args;

  /// Names the result of this aggregate.
  AliasedAggregate as(String alias) => AliasedAggregate(this, alias);

  /// This aggregate evaluated over [frame], relative to each input, instead
  /// of over the frame of the enclosing `Pipeline.addWindowFields` stage.
  ///
  /// ```dart
  /// pipeline.addWindowFields(
  ///   WindowSpec(sort: [field('date').ascending()]),
  ///   [
  ///     field('amount')
  ///         .average()
  ///         .over(WindowFrame.documents(preceding: 1, following: 1))
  ///         .as('movingAverage'),
  ///   ],
  /// );
  /// ```
  ///
  /// **Beta**: window functions are a preview feature of the server.
  WindowFunction over(WindowFrame frame) =>
      WindowFunction.withFrame(name, args, frame);

  @internal
  pb.Value toProto(PipelineEncoder encoder) {
    return pb.Value()
      ..functionValue = (pb.Function_()
        ..name = name
        ..args.addAll(args.map((Expression e) => e.toProto(encoder))));
  }

  @override
  String toString() => '$name(${args.join(', ')})';
}

/// An [AggregateFunction] with a name, created with [AggregateFunction.as].
class AliasedAggregate {
  AliasedAggregate(this.aggregate, this.alias);

  /// The aggregate that produces the value.
  final AggregateFunction aggregate;

  /// The name of the output field.
  final String alias;

  @override
  String toString() => '$aggregate as $alias';
}
