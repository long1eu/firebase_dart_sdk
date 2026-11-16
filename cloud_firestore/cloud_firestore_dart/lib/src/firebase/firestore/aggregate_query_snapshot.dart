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

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exact_number.dart';
import 'package:collection/collection.dart';

/// The results of executing an [AggregateQuery].
///
/// Read each result with the [AggregateField] that asked for it:
///
/// ```dart
/// final AggregateQuerySnapshot snapshot = await firestore
///     .collection('orders')
///     .aggregate(<AggregateField>[
///       AggregateField.count(),
///       AggregateField.average('total'),
///     ])
///     .get();
/// final int? count = snapshot.count;
/// final double? average = snapshot.getAverage('total');
/// ```
///
/// The results come from the server at the time of the request; they do not
/// include local writes that are still pending.
class AggregateQuerySnapshot {
  /// Implementation detail of the SDK; not part of the supported API.
  AggregateQuerySnapshot._(this.query, Map<String, FieldValue> data)
    : _data = Map<String, FieldValue>.unmodifiable(data);

  /// The query that produced this snapshot.
  final AggregateQuery query;

  /// Results keyed by the alias of each aggregate field.
  final Map<String, FieldValue> _data;

  /// All results of this snapshot: each value is an `int`, a `double` or
  /// null, as returned by [get].
  ///
  /// This is the counterpart of the JS SDK's `AggregateQuerySnapshot.data()`.
  /// For a query created with `Query.aggregateWithAliases` the keys are the
  /// user-chosen aliases. Otherwise they are the aliases this SDK derives for
  /// each field (for example `count`, or `sum_price`
  /// for `AggregateField.sum('price')`).
  Map<String, Object?> data() {
    final Map<String, AggregateField>? aliases = query.aliases;
    if (aliases != null) {
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry<String, AggregateField> entry in aliases.entries)
          entry.key: get(entry.value),
      });
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final MapEntry<String, FieldValue> entry in _data.entries)
        entry.key: entry.value.value,
    });
  }

  /// The result of the count aggregation (`count()` or [AggregateField.count]), or null when the query did not ask
  /// for it.
  ///
  /// ```dart
  /// final int? n = (await firestore.collection('cities').count().get()).count;
  /// ```
  int? get count {
    final FieldValue? value = _data[AggregateField.count().alias];
    final Object? count = value?.value;
    return count is Int32Value ? count.value : (count as num?)?.toInt();
  }

  /// The result of [AggregateField.sum] over [field] (a [String] or a [FieldPath]): an `int` for a sum of
  /// integers that fits in 64 bits, a `double` otherwise, or null (for example a sum over no numeric value).
  ///
  /// A [Decimal128Value] result (Enterprise edition) is converted to the closest `double`. Throws an
  /// [ArgumentError] if the query did not ask for this sum.
  num? getSum(Object field) => _getNumber(AggregateField.sum(field));

  /// The result of [AggregateField.average] over [field] (a [String] or a [FieldPath]), or null when no document
  /// has a numeric value for the field.
  ///
  /// Throws an [ArgumentError] if the query did not ask for this average.
  double? getAverage(Object field) =>
      _getNumber(AggregateField.average(field))?.toDouble();

  /// The result of [aggregateField]: an `int`, a `double` or null (for
  /// example the average over no numeric values).
  ///
  /// On an Enterprise edition database the sum and the average over values
  /// that include a [Decimal128Value] are a [Decimal128Value]. [getSum] and
  /// [getAverage] convert it to the closest `double`.
  ///
  /// Throws an [ArgumentError] if [aggregateField] was not requested.
  ///
  /// ```dart
  /// final Object? sum = snapshot.get(AggregateField.sum('total'));
  /// ```
  Object? get(AggregateField aggregateField) {
    final FieldValue? value = _data[aggregateField.alias];
    if (value == null) {
      throw ArgumentError(
        "'${aggregateField.operator}(${aggregateField.fieldPath})' was not requested in the aggregation query.",
      );
    }
    return value.value;
  }

  num? _getNumber(AggregateField aggregateField) {
    final Object? value = get(aggregateField);
    if (value == null) {
      return null;
    } else if (value is Decimal128Value) {
      return ExactNumber.parse(value.stringValue).toDouble();
    } else if (value is Int32Value) {
      return value.value;
    } else if (value is! num) {
      throw StateError("AggregateField '${aggregateField.alias}' is not a num");
    }
    return value;
  }

  /// Two snapshots are equal when they aggregate the same query and hold the
  /// same results under the same names (as `aggregateQuerySnapshotEqual` of
  /// the JS SDK): the order the aggregations were asked in does not matter.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AggregateQuerySnapshot &&
          query.query == other.query.query &&
          const MapEquality<String, Object?>().equals(data(), other.data());

  @override
  int get hashCode => Object.hash(
    query.query,
    const MapEquality<String, Object?>().hash(data()),
  );
}

/// Members of [AggregateQuerySnapshot] for the SDK itself. Not exported by the public libraries.
extension AggregateQuerySnapshotInternal on AggregateQuerySnapshot {
  /// The snapshot of [query] with the results [data], keyed by alias.
  static AggregateQuerySnapshot create(
    AggregateQuery query,
    Map<String, FieldValue> data,
  ) => AggregateQuerySnapshot._(query, data);
}
