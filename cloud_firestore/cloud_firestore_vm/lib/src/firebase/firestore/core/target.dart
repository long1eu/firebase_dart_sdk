// File created by
// Lung Razvan <long1eu>
// on 16/01/2021

import 'package:cloud_firestore_vm/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';



/// A Target represents the [WatchTarget] representation of a [Query], which is used by the [LocalStore]
/// and the [RemoteStore] to keep track of and to execute backend queries. While multiple Queries can
/// map to the same [Target], each [Target] maps to a single [WatchTarget] in RemoteStore and a single
/// [TargetData] entry in persistence.
class Target {
  /// Initializes a Target with a path and additional query constraints. Path must currently be empty
  /// if this is a collection group query.
  ///
  /// NOTE: you should always construct Target from [Query.toTarget] instead of using this
  /// constructor, because Query provides an implicit [orderBy] property.
  Target({
    @required this.path,
    @required this.collectionGroup,
    @required this.filters,
    @required this.orderBy,
    @required int limit,
    @required this.startAt,
    @required this.endAt,
  }) : _limit = limit;

  static const int kNoLimit = -1;

  final List<OrderBy> orderBy;

  /// The filters on the documents returned by the query.
  final List<Filter> filters;

  /// The base path of the query.
  final ResourcePath path;

  /// An optional collection group within which to query.
  final String collectionGroup;

  final int _limit;

  /// An optional bound to start the query at.
  final Bound startAt;

  /// An optional bound to end the query at.
  final Bound endAt;

  String _memoizedCannonicalId;

  /// Returns true if this Query is for a specific document.
  bool get isDocumentQuery {
    return DocumentKey.isDocumentKey(path) && collectionGroup == null && filters.isEmpty;
  }

  /// The maximum number of results to return.
  ///
  /// If there is no limit on the query, then this will cause an assertion failure.
  int get limit {
    hardAssert(hasLimit, 'Called getter limit when no limit was set');
    return _limit;
  }

  bool get hasLimit => _limit != kNoLimit;

  /// Returns a canonical string representing this target.
  String get canonicalId {
    if (_memoizedCannonicalId != null) {
      return _memoizedCannonicalId;
    }

    final StringBuffer buffer = StringBuffer() //
      ..write(path.canonicalString);

    if (collectionGroup != null) {
      buffer //
        ..write('|cg:')
        ..write(collectionGroup);
    }

    // Add filters.
    buffer.write('|f:');
    for (Filter filter in filters) {
      buffer.write(filter.canonicalId);
    }

    // Add order by.
    buffer.write('|ob:');
    for (OrderBy orderBy in orderBy) {
      buffer
        ..write(orderBy.field.canonicalString) //
        ..write(orderBy.direction == OrderByDirection.ascending ? 'asc' : 'desc');
    }

    // Add limit.
    if (hasLimit) {
      buffer //
        ..write('|l:')
        ..write(limit);
    }

    if (startAt != null) {
      buffer //
        ..write('|lb:')
        ..write(startAt.canonicalString());
    }

    if (endAt != null) {
      buffer //
        ..write('|ub:')
        ..write(endAt.canonicalString());
    }

    return _memoizedCannonicalId = buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Target &&
          runtimeType == other.runtimeType &&
          collectionGroup == other.collectionGroup &&
          _limit == other._limit &&
          const ListEquality<OrderBy>().equals(orderBy, other.orderBy) &&
          const ListEquality<Filter>().equals(filters, other.filters) &&
          path == other.path &&
          startAt == other.startAt &&
          endAt == other.endAt;

  @override
  int get hashCode =>
      collectionGroup.hashCode ^
      _limit.hashCode ^
      const ListEquality<OrderBy>().hash(orderBy) ^
      const ListEquality<Filter>().hash(filters) ^
      path.hashCode ^
      startAt.hashCode ^
      endAt.hashCode;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer() //
      ..write('Query(')
      ..write(path.canonicalString);
    if (collectionGroup != null) {
      buffer //
        ..write(' collectionGroup=')
        ..write(collectionGroup);
    }
    if (filters.isNotEmpty) {
      buffer.write(' where ');
      for (int i = 0; i < filters.length; i++) {
        if (i > 0) {
          buffer.write(' and ');
        }
        buffer.write(filters[i]);
      }
    }

    if (orderBy.isNotEmpty) {
      buffer.write(' order by ');
      for (int i = 0; i < orderBy.length; i++) {
        if (i > 0) {
          buffer.write(', ');
        }
        buffer.write(orderBy[i]);
      }
    }

    buffer.write(')');
    return buffer.toString();
  }
}
