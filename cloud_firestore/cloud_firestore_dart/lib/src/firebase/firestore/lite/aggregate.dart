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
import 'dart:collection';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exact_number.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A query that calculates aggregations (count, sum, average) over the result
/// set of a [Query] on the server, without downloading the documents.
class AggregateQuery {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Query.count] or [Query.aggregate].
  @internal
  AggregateQuery(this.query, List<AggregateField> aggregateFields)
    : aggregateFields = List<AggregateField>.unmodifiable(aggregateFields),
      aliases = null;

  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Query.aggregateWithAliases].
  @internal
  AggregateQuery.withAliases(this.query, Map<String, AggregateField> aliases)
    : aggregateFields = List<AggregateField>.unmodifiable(
        LinkedHashSet<AggregateField>.of(aliases.values),
      ),
      aliases = Map<String, AggregateField>.unmodifiable(aliases);

  /// The query whose result set is aggregated.
  final Query<Object?> query;

  /// The aggregations to calculate.
  final List<AggregateField> aggregateFields;

  /// The user-chosen aliases of the aggregations, null unless the query was
  /// made with [Query.aggregateWithAliases].
  final Map<String, AggregateField>? aliases;

  /// Runs the aggregations on the backend.
  Future<AggregateQuerySnapshot> get() async {
    final Firestore firestore = query.firestore;
    final Map<String, FieldValue> data = await firestore.run(
      (Datastore datastore) =>
          datastore.runAggregateQuery(query.query, aggregateFields),
    );
    return AggregateQuerySnapshot(this, data);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AggregateQuery &&
          query == other.query &&
          const ListEquality<AggregateField>().equals(
            aggregateFields,
            other.aggregateFields,
          ) &&
          const MapEquality<String, AggregateField>().equals(
            aliases,
            other.aliases,
          );

  @override
  int get hashCode => Object.hash(
    query,
    const ListEquality<AggregateField>().hash(aggregateFields),
    const MapEquality<String, AggregateField>().hash(aliases),
  );
}

/// The results of executing an [AggregateQuery].
class AggregateQuerySnapshot {
  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  AggregateQuerySnapshot(this.query, Map<String, FieldValue> data)
    : _data = Map<String, FieldValue>.unmodifiable(data);

  /// The query that produced this snapshot.
  final AggregateQuery query;

  final Map<String, FieldValue> _data;

  /// All the results: keyed by the user-chosen aliases for a query made with
  /// [Query.aggregateWithAliases], by the default alias of each aggregation
  /// (`count`, `sum_<field>`, `average_<field>`) otherwise.
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

  /// The number of documents in the result set. Throws an [ArgumentError] if
  /// the query did not ask for the count.
  int getCount() {
    final int? value = getInt(AggregateField.count());
    if (value == null) {
      throw ArgumentError(
        'RunAggregationQueryResponse alias ${AggregateField.count().alias} is null',
      );
    }
    return value;
  }

  /// The result of [aggregateField]. Throws an [ArgumentError] if the query
  /// did not ask for it.
  Object? get(AggregateField aggregateField) {
    final FieldValue? value = _data[aggregateField.alias];
    if (value == null) {
      throw ArgumentError(
        "'${aggregateField.operator}(${aggregateField.fieldPath})' was not requested in the aggregation query.",
      );
    }
    return value.value;
  }

  /// The result of [aggregateField] as an integer (a fractional result is
  /// truncated).
  int? getInt(AggregateField aggregateField) {
    final num? value = _getNumber(aggregateField);
    if (value == null || value is int) {
      return value as int?;
    }
    // Saturating conversion: NaN becomes 0 and the infinities become the
    // extreme integers. Dart's `toInt()` would throw.
    if (value.isNaN) {
      return 0;
    }
    if (value.isInfinite) {
      return value.isNegative ? _minInt : _maxInt;
    }
    return value.toInt();
  }

  // Not literals: they do not compile to JavaScript, where an `int` cannot
  // hold them exactly.
  static final int _maxInt = int.parse('9223372036854775807');
  static final int _minInt = int.parse('-9223372036854775808');

  /// The result of [aggregateField] as a double.
  double? getDouble(AggregateField aggregateField) {
    return _getNumber(aggregateField)?.toDouble();
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
