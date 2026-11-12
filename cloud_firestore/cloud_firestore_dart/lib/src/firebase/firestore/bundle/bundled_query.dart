// Copyright 2021 Google LLC
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

// Ported from the Firestore Android SDK (com.google.firebase.firestore.bundle).

import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';

/// Whether the limit of a bundled query applies to the beginning or the end of the results.
///
/// PORTING NOTE: kept next to the bundled query; the core [Query] has its own `LimitType` (Android: `Query.LimitType`),
/// see [BundledQuery.toQuery].
enum BundledQueryLimitType {
  /// `limit()`: the first N results.
  first,

  /// `limitToLast()`: the last N results.
  last,
}

/// A bundled query represents a query target and its limit.
class BundledQuery implements BundleElement {
  const BundledQuery(this.query, this.limitType);

  /// The query that represents the user-issued query. OrderBy constraints are not inverted for `limitToLast()`
  /// queries. In the Android SDK this is a `Target`; the port uses [Query] for both.
  final Query query;

  /// The user provided limit type.
  final BundledQueryLimitType limitType;

  /// The user-issued query: [query] with `limitToLast()` applied when [limitType] says so.
  ///
  /// [query] itself always keeps its order constraints as the user wrote them (the Query/Target split flips them in
  /// [Query.toTarget] for limit-to-last queries).
  Query toQuery() => limitType == BundledQueryLimitType.last && query.hasLimit
      ? query.limitToLast(query.getLimit())
      : query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundledQuery &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          limitType == other.limitType;

  @override
  int get hashCode => query.hashCode ^ limitType.hashCode;

  @override
  String toString() => 'BundledQuery{query: $query, limitType: $limitType}';
}
