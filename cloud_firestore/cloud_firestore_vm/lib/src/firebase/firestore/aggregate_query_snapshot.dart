// Copyright 2022 Google LLC
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

import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:collection/collection.dart';

/// The results of executing an [AggregateQuery].
class AggregateQuerySnapshot {
  AggregateQuerySnapshot(this.query, Map<String, FieldValue> data)
      : _data = Map<String, FieldValue>.unmodifiable(data);

  /// The query that produced this snapshot.
  final AggregateQuery query;

  /// Results keyed by [AggregateField.alias].
  final Map<String, FieldValue> _data;

  /// The result of the count aggregation. Throws an [ArgumentError] when the
  /// query did not request [AggregateField.count] or the result is null.
  int getCount() {
    final int? value = getInt(AggregateField.count());
    if (value == null) {
      throw ArgumentError(
          'RunAggregationQueryResponse alias ${AggregateField.count().alias} is null');
    }
    return value;
  }

  /// The result of [aggregateField]: an `int`, a `double` or null (for
  /// example the average over no numeric values).
  ///
  /// Throws an [ArgumentError] if [aggregateField] was not requested.
  Object? get(AggregateField aggregateField) {
    final FieldValue? value = _data[aggregateField.alias];
    if (value == null) {
      throw ArgumentError(
          "'${aggregateField.operator}(${aggregateField.fieldPath})' was not requested in the aggregation query.");
    }
    return value.value;
  }

  /// The result of [aggregateField] as an `int` (doubles are truncated and saturated, NaN is 0), or
  /// null if the result is null.
  int? getInt(AggregateField aggregateField) {
    final num? value = _getNumber(aggregateField);
    if (value == null || value is int) {
      return value as int?;
    }
    // Saturating conversion (as Java's `double.longValue()`): NaN becomes 0 and
    // the infinities become the extreme integers. Dart's `toInt()` would throw.
    if (value.isNaN) {
      return 0;
    }
    if (value.isInfinite) {
      return value.isNegative ? _minInt : _maxInt;
    }
    return value.toInt();
  }

  static const int _maxInt = 9223372036854775807;
  static const int _minInt = -9223372036854775808;

  /// The result of [aggregateField] as a `double`, or null if the result is
  /// null.
  double? getDouble(AggregateField aggregateField) {
    final num? value = _getNumber(aggregateField);
    return value?.toDouble();
  }

  num? _getNumber(AggregateField aggregateField) {
    final Object? value = get(aggregateField);
    if (value == null) {
      return null;
    } else if (value is! num) {
      throw StateError("AggregateField '${aggregateField.alias}' is not a num");
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AggregateQuerySnapshot &&
          query == other.query &&
          const MapEquality<String, FieldValue>().equals(_data, other._data);

  @override
  int get hashCode =>
      Object.hash(query, const MapEquality<String, FieldValue>().hash(_data));
}
