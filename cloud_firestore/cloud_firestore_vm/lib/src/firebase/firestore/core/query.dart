// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

enum QueryLimitType { limitToFirst, limitToLast }

/// Encapsulates all the query attributes we support in the SDK. It can be run against the
/// LocalStore, as well as be converted to a {@code Target} to query the RemoteStore results.
class Query {
  /// Initializes a Query with all of its components directly.
  Query(
    this.path, {
    this.collectionGroup,
    this.filters = const <Filter>[],
    this.explicitSortOrder = const <OrderBy>[],
    int limit = Target.kNoLimit,
    QueryLimitType limitType = QueryLimitType.limitToFirst,
    Bound startAt,
    Bound endAt,
  })  : _limit = limit,
        _limitType = limitType,
        _startAt = startAt,
        _endAt = endAt;

  static final OrderBy keyOrderingAsc = OrderBy.getInstance(OrderByDirection.ascending, FieldPath.keyPath);

  static final OrderBy keyOrderingDesc = OrderBy.getInstance(OrderByDirection.descending, FieldPath.keyPath);

  /// Returns the list of ordering constraints that were explicitly requested on the query by the user.
  ///
  /// Note that the actual query performed might add additional sort orders to match the behavior of the backend.
  final List<OrderBy> explicitSortOrder;

  // The corresponding Target of this Query instance.
  Target _memoizedTarget;

  /// The filters on the documents returned by the query.
  final List<Filter> filters;

  /// The base path of the query.
  final ResourcePath path;

  final String collectionGroup;

  final int _limit;
  final QueryLimitType _limitType;

  /// An optional bound to start the query at.
  final Bound _startAt;

  /// An optional bound to end the query at.
  final Bound _endAt;

  /// Returns true if this Query is for a specific document.
  bool get isDocumentQuery {
    return DocumentKey.isDocumentKey(path) && collectionGroup == null && filters.isEmpty;
  }

  /// Returns true if this is a collection group query.
  bool get isCollectionGroupQuery => collectionGroup != null;

  /// Returns true if this query does not specify any query constraints that could remove results.
  bool get matchesAllDocuments {
    return filters.isEmpty &&
        _limit == Target.kNoLimit &&
        startAt == null &&
        endAt == null &&
        (explicitSortOrder.isEmpty || (explicitSortOrder.length == 1 && firstOrderByField.isKeyField));
  }

  /// The maximum number of results to return. If there is no limit on the query, then this will
  /// cause an assertion failure.
  int getLimitToFirst() {
    hardAssert(hasLimitToFirst, 'Called getLimitToFirst when no limit was set');
    return _limit;
  }

  bool get hasLimitToFirst {
    return _limitType == QueryLimitType.limitToFirst && _limit != Target.kNoLimit;
  }

  /// The maximum number of last-matching results to return. If there is no limit on the query, then
  /// this will cause an assertion failure.
  int getLimitToLast() {
    hardAssert(hasLimitToLast, 'Called getLimitToLast when no limit was set');
    return _limit;
  }

  bool get hasLimitToLast {
    return _limitType == QueryLimitType.limitToLast && _limit != Target.kNoLimit;
  }

  QueryLimitType getLimitType() {
    hardAssert(hasLimitToLast || hasLimitToFirst, 'Called getLimitType when no limit was set');
    return _limitType;
  }

  /// An optional bound to start the query at.
  Bound getStartAt() => _startAt;

  /// An optional bound to end the query at.
  Bound getEndAt() => _endAt;

  /// Returns the first field in an order-by constraint, or null if none.
  FieldPath get firstOrderByField {
    if (explicitSortOrder.isEmpty) {
      return null;
    }
    return explicitSortOrder[0].field;
  }

  /// Returns the field of the first filter on this Query that's an inequality, or null if none.
  FieldPath get inequalityField {
    for (Filter filter in filters) {
      if (filter is FieldFilter) {
        final FieldFilter relationFilter = filter;
        if (relationFilter.isInequality) {
          return relationFilter.field;
        }
      }
    }
    return null;
  }

  /// Checks if any of the provided filter operators are included in the query
  /// and returns the first one that is, or null if none are.
  FilterOperator findFilterOperator(List<FilterOperator> filterOps) {
    for (Filter filter in filters) {
      if (filter is FieldFilter) {
        final FilterOperator queryOp = filter.operator;

        if (filterOps.contains(queryOp)) {
          return queryOp;
        }
      }
    }
    return null;
  }

  /// Creates a new Query with an additional filter.
  ///
  /// [filter] is the predicate to filter by.
  Query filter(Filter filter) {
    hardAssert(!isDocumentQuery, 'No filter is allowed for document query');

    FieldPath newInequalityField;
    if (filter is FieldFilter && filter.isInequality) {
      newInequalityField = filter.field;
    }

    final FieldPath queryInequalityField = inequalityField;
    hardAssert(queryInequalityField == null || newInequalityField == null || queryInequalityField == newInequalityField,
        'Query must only have one inequality field');

    hardAssert(
        explicitSortOrder.isEmpty || newInequalityField == null || explicitSortOrder[0].field == newInequalityField,
        'First orderBy must match inequality field');

    return copyWith(filters: <Filter>[...filters, filter]);
  }

  /// Creates a new Query with an additional ordering constraint.
  ///
  /// [order] is the key and direction to order by.
  Query orderBy(OrderBy order) {
    hardAssert(!isDocumentQuery, 'No ordering is allowed for document query');

    if (explicitSortOrder.isEmpty) {
      final FieldPath inequality = inequalityField;
      if (inequality != null && inequality != order.field) {
        throw fail('First orderBy must match inequality field');
      }
    }
    final List<OrderBy> updatedSortOrder = <OrderBy>[...explicitSortOrder, order];
    return copyWith(explicitSortOrder: updatedSortOrder);
  }

  /// Returns a new Query with the given [limit] on how many results can be returned.
  Query limitToFirst(int limit) {
    return copyWith(limit: limit, limitType: QueryLimitType.limitToFirst);
  }

  /// Returns a new Query with the given limit on how many last-matching results can be returned.
  Query limitToLast(int limit) {
    return copyWith(limit: limit, limitType: QueryLimitType.limitToLast);
  }

  /// Creates a new Query starting at the provided bound.
  /// The [bound] to end this query at.
  Query startAt(Bound bound) => copyWith(startAt: bound);

  /// Creates a new Query ending at the provided bound.
  ///
  /// The [bound] to end this query at.
  Query endAt(Bound bound) => copyWith(endAt: bound);

  /// Helper to convert a collection group query into a collection query at a
  /// specific path. This is used when executing collection group queries, since
  /// we have to split the query into a set of collection queries at multiple
  /// paths.
  Query asCollectionQueryAtPath(ResourcePath path) {
    return Query(
      path,
      filters: filters,
      explicitSortOrder: explicitSortOrder,
      limit: _limit,
      startAt: _startAt,
      endAt: _endAt,
    );
  }

  List<OrderBy> getOrderBy() {
    return orderByConstraints;
  }

  /// Returns the full list of ordering constraints on the query.
  ///
  /// This might include additional sort orders added implicitly to match the
  /// backend behavior.
  List<OrderBy> get orderByConstraints {
    final FieldPath inequalityField = this.inequalityField;
    if (inequalityField != null && firstOrderByField == null) {
      // In order to implicitly add key ordering, we must also add the
      // inequality filter field for it to be a valid query. Note that the
      // default inequality field and key ordering is ascending.
      if (inequalityField.isKeyField) {
        return <OrderBy>[keyOrderingAsc];
      } else {
        return <OrderBy>[OrderBy.getInstance(OrderByDirection.ascending, inequalityField), keyOrderingAsc];
      }
    } else {
      final List<OrderBy> res = <OrderBy>[];
      bool foundKeyOrdering = false;
      for (OrderBy explicit in explicitSortOrder) {
        res.add(explicit);
        if (explicit.field == FieldPath.keyPath) {
          foundKeyOrdering = true;
        }
      }
      if (!foundKeyOrdering) {
        // The direction of the implicit key ordering always matches the
        // direction of the last explicit sort order
        final OrderByDirection lastDirection = explicitSortOrder.isNotEmpty
            ? explicitSortOrder[explicitSortOrder.length - 1].direction
            : OrderByDirection.ascending;
        res.add(lastDirection == OrderByDirection.ascending ? keyOrderingAsc : keyOrderingDesc);
      }
      return res;
    }
  }

  bool _matchesPathAndCollectionGroup(Document doc) {
    final ResourcePath docPath = doc.key.path;
    if (collectionGroup != null) {
      // NOTE: this.path is currently always empty since we don't expose
      // Collection Group queries rooted at a document path yet.
      return doc.key.hasCollectionId(collectionGroup) && path.isPrefixOf(docPath);
    } else if (DocumentKey.isDocumentKey(path)) {
      return path == docPath;
    } else {
      return path.isPrefixOf(docPath) && path.length == docPath.length - 1;
    }
  }

  bool _matchesFilters(Document doc) {
    for (Filter filter in filters) {
      if (!filter.matches(doc)) {
        return false;
      }
    }
    return true;
  }

  /// A document must have a value for every ordering clause in order to show up in the results.
  bool _matchesOrderBy(Document doc) {
    for (OrderBy order in explicitSortOrder) {
      // order by key always matches
      if (order.field != FieldPath.keyPath && doc.getField(order.field) == null) {
        return false;
      }
    }
    return true;
  }

  /// Makes sure a document is within the bounds, if provided.
  bool _matchesBounds(Document doc) {
    if (_startAt != null && !_startAt.sortsBeforeDocument(orderByConstraints, doc)) {
      return false;
    }
    if (_endAt != null && _endAt.sortsBeforeDocument(orderByConstraints, doc)) {
      return false;
    }
    return true;
  }

  /// Returns true if the document matches the constraints of this query.
  bool matches(Document doc) {
    return _matchesPathAndCollectionGroup(doc) && _matchesOrderBy(doc) && _matchesFilters(doc) && _matchesBounds(doc);
  }

  /// Returns a comparator that will sort documents according to this Query's
  /// sort order.
  Comparator<Document> get comparator => QueryComparator(orderByConstraints).comparator;

  /// Returns a [Target] instance this query will be mapped to in backend and local store.
  Target toTarget() {
    if (_memoizedTarget == null) {
      if (_limitType == QueryLimitType.limitToFirst) {
        _memoizedTarget = Target(
          path: path,
          collectionGroup: collectionGroup,
          filters: filters,
          orderBy: getOrderBy(),
          limit: _limit,
          startAt: getStartAt(),
          endAt: getEndAt(),
        );
      } else {
        // Flip the orderBy directions since we want the last results
        final List<OrderBy> newOrderBy = <OrderBy>[];
        for (OrderBy orderBy in orderByConstraints) {
          final OrderByDirection dir = orderBy.direction == OrderByDirection.descending
              ? OrderByDirection.ascending
              : OrderByDirection.descending;
          newOrderBy.add(OrderBy.getInstance(dir, orderBy.field));
        }

        // We need to swap the cursors to match the now-flipped query ordering.
        final Bound newStartAt = _endAt != null ? Bound(position: _endAt.position, before: !_endAt.before) : null;
        final Bound newEndAt = _startAt != null ? Bound(position: _startAt.position, before: !_startAt.before) : null;

        _memoizedTarget = Target(
          path: path,
          collectionGroup: collectionGroup,
          filters: filters,
          orderBy: newOrderBy,
          limit: _limit,
          startAt: newStartAt,
          endAt: newEndAt,
        );
      }
    }

    return _memoizedTarget;
  }

  /// Returns a canonical string representing this query. This should match the
  /// iOS and Android canonical ids for a query exactly.
  // TODO(long1eu): This is now only used in tests and SpecTestCase. Maybe we can delete it?
  String get canonicalId {
    return '${toTarget().canonicalId}|lt:$_limitType';
  }

  Query copyWith({
    List<Filter> filters,
    String collectionGroup,
    List<OrderBy> explicitSortOrder,
    int limit,
    QueryLimitType limitType,
    Bound startAt,
    Bound endAt,
  }) {
    return Query(
      path,
      collectionGroup: collectionGroup ?? this.collectionGroup,
      filters: filters ?? this.filters,
      explicitSortOrder: explicitSortOrder ?? this.explicitSortOrder,
      limit: limit ?? _limit,
      limitType: limitType ?? _limitType,
      startAt: startAt ?? _startAt,
      endAt: endAt ?? _endAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Query &&
            runtimeType == other.runtimeType &&
            _limitType == other._limitType &&
            toTarget() == other.toTarget();
  }

  @override
  int get hashCode => _limitType.hashCode ^ toTarget().hashCode;

  @override
  String toString() {
    return (StringBuffer()
          ..write('Query(target=')
          ..write(toTarget())
          ..write(';limitType=')
          ..write(_limitType)
          ..write(')'))
        .toString();
  }
}

class QueryComparator {
  factory QueryComparator(List<OrderBy> order) {
    bool hasKeyOrdering = false;
    for (OrderBy orderBy in order) {
      hasKeyOrdering = hasKeyOrdering || orderBy.field == FieldPath.keyPath;
    }
    if (!hasKeyOrdering) {
      throw ArgumentError('QueryComparator needs to have a key ordering');
    }

    return QueryComparator._(order);
  }

  const QueryComparator._(this.sortOrder);

  final List<OrderBy> sortOrder;

  Comparator<Document> get comparator {
    return (Document doc1, Document doc2) {
      for (OrderBy order in sortOrder) {
        final int comp = order.compare(doc1, doc2);
        if (comp != 0) {
          return comp;
        }
      }
      return 0;
    };
  }
}
