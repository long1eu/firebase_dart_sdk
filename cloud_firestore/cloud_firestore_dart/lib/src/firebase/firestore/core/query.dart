// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:collection';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';

/// Whether a query limit keeps the first or the last matching results.
enum LimitType { limitToFirst, limitToLast }

/// Represents the internal structure of a Firestore Query. It can be run
/// against the LocalStore, as well as be converted to a [Target] (see
/// [toTarget]) to query the RemoteStore results.
class Query {
  /// Initializes a Query with all of its components directly.
  Query(
    this.path, {
    this.collectionGroup,
    this.filters = const <Filter>[],
    this.explicitSortOrder = const <OrderBy>[],
    int limit = noLimit,
    this.limitType = LimitType.limitToFirst,
    Bound? startAt,
    Bound? endAt,
  }) : _limit = limit,
       _startAt = startAt,
       _endAt = endAt;

  static const int noLimit = Target.noLimit;

  static final OrderBy keyOrderingAsc = OrderBy.getInstance(
    OrderByDirection.ascending,
    FieldPath.keyPath,
  );

  static final OrderBy keyOrderingDesc = OrderBy.getInstance(
    OrderByDirection.descending,
    FieldPath.keyPath,
  );

  /// Returns the list of ordering constraints that were explicitly requested on the query by the user.
  ///
  /// Note that the actual query performed might add additional sort orders to match the behavior of the backend.
  final List<OrderBy> explicitSortOrder;

  /// The filters on the documents returned by the query.
  final List<Filter> filters;

  /// The base path of the query.
  final ResourcePath path;

  final String? collectionGroup;

  final int _limit;

  /// Whether [getLimit] keeps the first or the last results. Only meaningful
  /// when [hasLimit] is true.
  final LimitType limitType;

  Target? _memoizedTarget;

  Target? _memoizedAggregateTarget;

  List<OrderBy>? _memoizedOrderBy;

  /// An optional bound to start the query at.
  final Bound? _startAt;

  /// An optional bound to end the query at.
  final Bound? _endAt;

  /// Returns true if this Query is for a specific document.
  bool get isDocumentQuery {
    return DocumentKey.isDocumentKey(path) &&
        collectionGroup == null &&
        filters.isEmpty;
  }

  /// Returns true if this is a collection group query.
  bool get isCollectionGroupQuery => collectionGroup != null;

  /// The maximum number of results to return. If there is no limit on the
  /// query, then this will cause an assertion failure.
  int getLimit() {
    hardAssert(hasLimit, 'Called getLimit when no limit was set');
    return _limit;
  }

  bool get hasLimit => _limit != noLimit;

  /// Whether this query keeps the first [getLimit] matching results.
  bool get hasLimitToFirst =>
      limitType == LimitType.limitToFirst && _limit != noLimit;

  /// Whether this query keeps the last [getLimit] matching results.
  bool get hasLimitToLast =>
      limitType == LimitType.limitToLast && _limit != noLimit;

  /// Returns a new [Query] with the given limit on how many results can be
  /// returned.
  ///
  /// [limit] represents the maximum number of results to return. If
  /// `limit == noLimit`, then no limit is applied. Otherwise, if `limit <= 0`,
  /// behavior is unspecified. This overrides a previous [limitToLast].
  Query limit(int limit) => limitToFirst(limit);

  /// Returns a new [Query] that keeps the first [limit] matching results.
  Query limitToFirst(int limit) =>
      copyWith(limit: limit, limitType: LimitType.limitToFirst);

  /// Returns a new [Query] that keeps the last [limit] matching results.
  Query limitToLast(int limit) =>
      copyWith(limit: limit, limitType: LimitType.limitToLast);

  /// An optional bound to start the query at.
  Bound? getStartAt() => _startAt;

  /// An optional bound to end the query at.
  Bound? getEndAt() => _endAt;

  /// Returns the first field in an order-by constraint, or null if none.
  FieldPath? get firstOrderByField {
    if (explicitSortOrder.isEmpty) {
      return null;
    }
    return explicitSortOrder[0].field;
  }

  /// Returns the sorted set of inequality filter fields used in this query
  /// (including the ones nested in composite filters).
  ///
  /// The list is sorted by field path (segment by segment).
  List<FieldPath> get inequalityFilterFields {
    final SplayTreeSet<FieldPath> result = SplayTreeSet<FieldPath>();
    for (Filter filter in filters) {
      for (FieldFilter subFilter in filter.flattenedFilters) {
        if (subFilter.isInequality) {
          result.add(subFilter.field);
        }
      }
    }
    return result.toList(growable: false);
  }

  /// Returns the field of the first inequality filter on this Query (in
  /// sorted order, see [inequalityFilterFields]), or null if none.
  FieldPath? get firstInequalityField {
    final List<FieldPath> fields = inequalityFilterFields;
    return fields.isEmpty ? null : fields.first;
  }

  /// Creates a new Query with an additional filter.
  ///
  /// [filter] is the predicate to filter by (a [FieldFilter] or a
  /// [CompositeFilter]). The list of filters of a query is an implicit AND, so
  /// an AND filter is added as its terms (see
  /// [CompositeFilter.conjunctionTerms]).
  Query filter(Filter filter) {
    hardAssert(!isDocumentQuery, 'No filter is allowed for document query');
    return copyWith(
      filters: <Filter>[
        ...filters,
        ...CompositeFilter.conjunctionTerms(filter),
      ],
    );
  }

  /// Creates a new Query with an additional ordering constraint.
  ///
  /// [order] is the key and direction to order by.
  Query orderBy(OrderBy order) {
    hardAssert(!isDocumentQuery, 'No ordering is allowed for document query');

    final List<OrderBy> updatedSortOrder = <OrderBy>[
      ...explicitSortOrder,
      order,
    ];
    return copyWith(explicitSortOrder: updatedSortOrder);
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
      limitType: limitType,
      startAt: _startAt,
      endAt: _endAt,
    );
  }

  /// Returns the full list of ordering constraints on the query.
  ///
  /// This might include additional sort orders added implicitly to match the
  /// backend behavior: any inequality field that is not explicitly ordered is
  /// ordered (lexicographically by field path) in the direction of the last
  /// explicit order, followed by the document key.
  List<OrderBy> get orderByConstraints {
    final List<OrderBy>? memoized = _memoizedOrderBy;
    if (memoized != null) {
      return memoized;
    }

    final List<OrderBy> res = <OrderBy>[];
    final Set<String> fieldsNormalized = <String>{};

    // Any explicit order by fields should be added as is.
    for (OrderBy explicit in explicitSortOrder) {
      res.add(explicit);
      fieldsNormalized.add(explicit.field.canonicalString);
    }

    // The order of the implicit ordering always matches the last explicit
    // order by.
    final OrderByDirection lastDirection = explicitSortOrder.isNotEmpty
        ? explicitSortOrder[explicitSortOrder.length - 1].direction
        : OrderByDirection.ascending;

    // Any inequality fields not explicitly ordered should be implicitly
    // ordered in a lexicographical order. When there are multiple inequality
    // filters on the same field, the field is added only once. The key field
    // sorts first in the set of fields, but it has to be ordered last.
    for (FieldPath field in inequalityFilterFields) {
      if (!fieldsNormalized.contains(field.canonicalString) &&
          !field.isKeyField) {
        res.add(OrderBy.getInstance(lastDirection, field));
      }
    }

    // Add the document key field to the last if it is not explicitly ordered.
    if (!fieldsNormalized.contains(FieldPath.keyPath.canonicalString)) {
      res.add(
        lastDirection == OrderByDirection.ascending
            ? keyOrderingAsc
            : keyOrderingDesc,
      );
    }

    return _memoizedOrderBy = List<OrderBy>.unmodifiable(res);
  }

  bool _matchesPathAndCollectionGroup(Document doc) {
    final ResourcePath docPath = doc.key.path;
    final String? collectionGroup = this.collectionGroup;
    if (collectionGroup != null) {
      // NOTE: this.path is currently always empty since we don't expose
      // Collection Group queries rooted at a document path yet.
      return doc.key.hasCollectionId(collectionGroup) &&
          path.isPrefixOf(docPath);
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
    // The implicit orderBys must be taken into account, too: for an OR query
    // such as "a > 1 || b == 1" there is an implicit "orderBy a", so a
    // document with only {b: 1} matches the filter but not the orderBy.
    for (OrderBy order in orderByConstraints) {
      // order by key always matches
      if (order.field != FieldPath.keyPath &&
          doc.getField(order.field) == null) {
        return false;
      }
    }
    return true;
  }

  /// Makes sure a document is within the bounds, if provided.
  bool _matchesBounds(Document doc) {
    final Bound? startAt = _startAt;
    final Bound? endAt = _endAt;
    if (startAt != null &&
        !startAt.sortsBeforeDocument(orderByConstraints, doc)) {
      return false;
    }
    if (endAt != null && !endAt.sortsAfterDocument(orderByConstraints, doc)) {
      return false;
    }
    return true;
  }

  /// Returns true if the document matches the constraints of this query.
  bool matches(Document doc) {
    return _matchesPathAndCollectionGroup(doc) &&
        _matchesOrderBy(doc) &&
        _matchesFilters(doc) &&
        _matchesBounds(doc);
  }

  /// Returns true if this query does not specify any query constraints that could remove results.
  bool get matchesAllDocuments =>
      filters.isEmpty &&
      _limit == noLimit &&
      _startAt == null &&
      _endAt == null &&
      (explicitSortOrder.isEmpty ||
          (explicitSortOrder.length == 1 && firstOrderByField!.isKeyField));

  /// Returns a comparator that will sort documents according to this Query's
  /// sort order.
  Comparator<Document> get comparator =>
      QueryComparator(orderByConstraints).comparator;

  /// Returns the [Target] this query is mapped to in the backend and the local
  /// store. For a limit-to-last query the orderings are flipped and the bounds
  /// swapped, so that an ordinary limit query is evaluated.
  Target toTarget() => _memoizedTarget ??= _toTarget(orderByConstraints);

  /// Returns the [Target] of an aggregation over this query. Unlike
  /// [toTarget] it only carries the explicit orderings: the implicit ones are
  /// irrelevant to an aggregation.
  Target toAggregateTarget() =>
      _memoizedAggregateTarget ??= _toTarget(explicitSortOrder);

  Target _toTarget(List<OrderBy> orderBys) {
    if (limitType == LimitType.limitToFirst) {
      return Target(
        path,
        collectionGroup: collectionGroup,
        filters: filters,
        orderBy: orderBys,
        limit: _limit,
        startAt: _startAt,
        endAt: _endAt,
      );
    } else {
      // Flip the orderBy directions since we want the last results.
      final List<OrderBy> newOrderBy = <OrderBy>[];
      for (OrderBy orderBy in orderBys) {
        final OrderByDirection dir =
            orderBy.direction == OrderByDirection.descending
            ? OrderByDirection.ascending
            : OrderByDirection.descending;
        newOrderBy.add(OrderBy.getInstance(dir, orderBy.field));
      }

      // We need to swap the cursors to match the now-flipped query ordering.
      final Bound? endAt = _endAt;
      final Bound? startAt = _startAt;
      final Bound? newStartAt = endAt != null
          ? Bound(position: endAt.position, inclusive: endAt.inclusive)
          : null;
      final Bound? newEndAt = startAt != null
          ? Bound(position: startAt.position, inclusive: startAt.inclusive)
          : null;

      return Target(
        path,
        collectionGroup: collectionGroup,
        filters: filters,
        orderBy: newOrderBy,
        limit: _limit,
        startAt: newStartAt,
        endAt: newEndAt,
      );
    }
  }

  /// Returns a canonical string representing this query. This should match the
  /// iOS and Android canonical ids for a query exactly.
  String get canonicalId =>
      '${toTarget().canonicalId}|lt:${limitType == LimitType.limitToFirst ? 'F' : 'L'}';

  Query copyWith({
    List<Filter>? filters,
    String? collectionGroup,
    List<OrderBy>? explicitSortOrder,
    int? limit,
    LimitType? limitType,
    Bound? startAt,
    Bound? endAt,
  }) {
    return Query(
      path,
      collectionGroup: collectionGroup ?? this.collectionGroup,
      filters: filters ?? this.filters,
      explicitSortOrder: explicitSortOrder ?? this.explicitSortOrder,
      limit: limit ?? _limit,
      limitType: limitType ?? this.limitType,
      startAt: startAt ?? _startAt,
      endAt: endAt ?? _endAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Query &&
            runtimeType == other.runtimeType &&
            limitType == other.limitType &&
            toTarget() == other.toTarget();
  }

  @override
  int get hashCode => 31 * toTarget().hashCode + limitType.hashCode;

  @override
  String toString() {
    return 'Query(target=${toTarget()};limitType=${limitType == LimitType.limitToFirst ? 'LIMIT_TO_FIRST' : 'LIMIT_TO_LAST'})';
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
