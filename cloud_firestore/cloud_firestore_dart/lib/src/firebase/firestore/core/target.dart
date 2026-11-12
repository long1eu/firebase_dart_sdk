// Copyright 2019 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:collection/collection.dart';

/// A Target represents the WatchTarget representation of a Query, which is used
/// by the LocalStore and the RemoteStore to keep track of and to execute
/// backend queries. While multiple Queries can map to the same Target, each
/// Target maps to a single WatchTarget in RemoteStore and a single QueryData
/// entry in persistence.
///
/// NOTE: you should always construct a Target from `Query.toTarget` instead of
/// using this constructor, because Query provides an implicit `orderBy`
/// property.
class Target {
  Target(
    this.path, {
    this.collectionGroup,
    this.filters = const <Filter>[],
    this.orderBy = const <OrderBy>[],
    this.limit = noLimit,
    this.startAt,
    this.endAt,
  });

  static const int noLimit = -1;

  /// The base path of the query.
  final ResourcePath path;

  /// An optional collection group within which to query.
  final String? collectionGroup;

  /// The filters on the documents returned by the query.
  final List<Filter> filters;

  /// The full list of orderings (including the implicit key ordering).
  final List<OrderBy> orderBy;

  final int limit;

  /// An optional bound to start the query at.
  final Bound? startAt;

  /// An optional bound to end the query at.
  final Bound? endAt;

  String? _memoizedCanonicalId;

  /// Returns true if this Target is for a specific document.
  bool get isDocumentQuery =>
      DocumentKey.isDocumentKey(path) &&
      collectionGroup == null &&
      filters.isEmpty;

  bool get hasLimit => limit != noLimit;

  /// The maximum number of results to return. If there is no limit on the
  /// query, then this will cause an assertion failure.
  int getLimit() {
    hardAssert(hasLimit, 'Called getLimit when no limit was set');
    return limit;
  }

  /// Returns a canonical string representing this target.
  String get canonicalId {
    final String? memoized = _memoizedCanonicalId;
    if (memoized != null) {
      return memoized;
    }

    final StringBuffer builder = StringBuffer(path.canonicalString);

    if (collectionGroup != null) {
      builder //
        ..write('|cg:')
        ..write(collectionGroup);
    }

    // Add filters.
    builder.write('|f:');
    for (Filter filter in filters) {
      builder.write(filter.canonicalId);
    }

    // Add order by.
    builder.write('|ob:');
    for (OrderBy orderBy in orderBy) {
      builder
        ..write(orderBy.field.canonicalString)
        ..write(
            orderBy.direction == OrderByDirection.ascending ? 'asc' : 'desc');
    }

    // Add limit.
    if (hasLimit) {
      builder //
        ..write('|l:')
        ..write(limit);
    }

    final Bound? startAt = this.startAt;
    if (startAt != null) {
      builder //
        ..write('|lb:')
        ..write(startAt.canonicalString());
    }

    final Bound? endAt = this.endAt;
    if (endAt != null) {
      builder //
        ..write('|ub:')
        ..write(endAt.canonicalString());
    }

    return _memoizedCanonicalId = builder.toString();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Target &&
            runtimeType == other.runtimeType &&
            limit == other.limit &&
            collectionGroup == other.collectionGroup &&
            path == other.path &&
            startAt == other.startAt &&
            endAt == other.endAt &&
            const ListEquality<OrderBy>().equals(orderBy, other.orderBy) &&
            const ListEquality<Filter>().equals(filters, other.filters);
  }

  @override
  int get hashCode =>
      const ListEquality<OrderBy>().hash(orderBy) ^
      collectionGroup.hashCode ^
      const ListEquality<Filter>().hash(filters) ^
      path.hashCode ^
      limit.hashCode ^
      startAt.hashCode ^
      endAt.hashCode;

  @override
  String toString() {
    final StringBuffer builder = StringBuffer() //
      ..write('Query(')
      ..write(path.canonicalString);
    if (collectionGroup != null) {
      builder //
        ..write(' collectionGroup=')
        ..write(collectionGroup);
    }
    if (filters.isNotEmpty) {
      builder.write(' where ');
      for (int i = 0; i < filters.length; i++) {
        if (i > 0) {
          builder.write(' and ');
        }
        builder.write(filters[i]);
      }
    }

    if (orderBy.isNotEmpty) {
      builder.write(' order by ');
      for (int i = 0; i < orderBy.length; i++) {
        if (i > 0) {
          builder.write(', ');
        }
        builder.write(orderBy[i]);
      }
    }

    builder.write(')');
    return builder.toString();
  }
}
