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

import 'dart:collection';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:collection/collection.dart';

/// A query that calculates aggregations over the documents of a [Query]
/// without downloading the documents themselves.
class AggregateQuery {
  /// Implementation detail of the SDK; not part of the supported API. Use [Query.count] or
  /// [Query.aggregate].
  AggregateQuery._(this.query, List<AggregateField> aggregateFields)
    : aggregateFields = List<AggregateField>.unmodifiable(aggregateFields),
      aliases = null;

  /// Creates an aggregate query whose results are keyed by the user-chosen
  /// aliases of [aliases] (see `Query.aggregateWithAliases`).
  AggregateQuery._withAliases(this.query, Map<String, AggregateField> aliases)
    : aggregateFields = List<AggregateField>.unmodifiable(
        LinkedHashSet<AggregateField>.of(aliases.values),
      ),
      aliases = Map<String, AggregateField>.unmodifiable(aliases);

  /// The query whose result set is aggregated.
  final Query<Object?> query;

  /// The aggregations requested by this query.
  final List<AggregateField> aggregateFields;

  /// The user-chosen aliases of the aggregations, or null when the query was
  /// created from a list of fields. `AggregateQuerySnapshot.data` is keyed by
  /// these aliases when they are present.
  final Map<String, AggregateField>? aliases;

  /// Executes the aggregation on the server and returns the results.
  ///
  /// Aggregations are never computed from the local cache: when the client is
  /// offline the returned Future fails with a `FirestoreError` whose code is
  /// `unavailable`.
  Future<AggregateQuerySnapshot> get([
    AggregateSource source = AggregateSource.server,
  ]) async {
    final Map<String, FieldValue> data = await query.firestore.client
        .runAggregateQuery(query.query, aggregateFields);
    return AggregateQuerySnapshotInternal.create(this, data);
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

/// Members of [AggregateQuery] for the SDK itself. Not exported by the public libraries.
extension AggregateQueryInternal on AggregateQuery {
  /// An aggregate query over [query] for [aggregateFields].
  static AggregateQuery create(
    Query<Object?> query,
    List<AggregateField> aggregateFields,
  ) => AggregateQuery._(query, aggregateFields);

  /// An aggregate query whose results are keyed by the user-chosen aliases
  /// of [aliases] (see `Query.aggregateWithAliases`).
  static AggregateQuery withAliases(
    Query<Object?> query,
    Map<String, AggregateField> aliases,
  ) => AggregateQuery._withAliases(query, aliases);
}
