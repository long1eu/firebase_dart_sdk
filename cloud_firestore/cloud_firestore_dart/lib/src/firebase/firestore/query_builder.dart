// The query builder shared by the Query of the main library (query.dart) and
// the Query of Firestore Lite (lite/query.dart): parsing and validating
// filters, orderings, limits and cursors, on the internal query. The two
// public classes keep the documentation and wrap the results.
//
// This file must not depend on either client (no Firestore class, no
// reference or snapshot class): Firestore Lite is compiled without the main
// client.

import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart'
    as core_filter
    show Filter, CompositeFilter;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart'
    hide Filter, CompositeFilter;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart'
    as api
    show CompositeFilter, UnaryFilter;
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';

/// Builds and validates the internal queries behind the public `Query`
/// classes, for the database [databaseId].
class QueryBuilder {
  const QueryBuilder(this.databaseId, this.dataConverter, this.referenceKey);

  /// The database of the queries.
  final DatabaseId databaseId;

  /// Parses the values of filters and cursors.
  final UserDataConverter dataConverter;

  /// The key of a value when it is a document reference of the client that
  /// uses this builder, null for every other value.
  final DocumentKey? Function(Object? value) referenceKey;

  /// Fails for a limit-to-last query without an ordering: it has no "last".
  static void validateHasExplicitOrderByForLimitToLast(core.Query query) {
    if (query.hasLimitToLast && query.explicitSortOrder.isEmpty) {
      throw StateError(
        'limitToLast() queries require specifying at least one orderBy() clause',
      );
    }
  }

  /// Returns [query] with the filters of `Query.where` added: see the
  /// documentation there.
  core.Query where(
    core.Query query,
    Object fieldOrFilter, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final List<Filter> filters;
    if (fieldOrFilter is Filter) {
      final bool hasConstraint =
          isEqualTo != null ||
          isNotEqualTo != null ||
          isLessThan != null ||
          isLessThanOrEqualTo != null ||
          isGreaterThan != null ||
          isGreaterThanOrEqualTo != null ||
          arrayContains != null ||
          arrayContainsAny != null ||
          whereIn != null ||
          whereNotIn != null ||
          isNull != null;
      if (hasConstraint) {
        throw ArgumentError(
          'Invalid query. Named arguments cannot be combined with a Filter '
          'in where().',
        );
      }
      filters = <Filter>[fieldOrFilter];
    } else {
      final FieldPath fieldPath;
      if (fieldOrFilter is FieldPath) {
        fieldPath = fieldOrFilter;
      } else if (fieldOrFilter is String) {
        fieldPath = FieldPathInternal.fromArgument('where', fieldOrFilter);
      } else {
        throw ArgumentError.value(
          fieldOrFilter,
          'fieldOrFilter',
          'where() expects a Filter, a String field or a FieldPath',
        );
      }
      api.UnaryFilter filter(FilterOperator op, Object? value) =>
          api.UnaryFilter(fieldPath, op, value);
      filters = <Filter>[
        if (isEqualTo != null) filter(FilterOperator.equal, isEqualTo),
        if (isNotEqualTo != null) filter(FilterOperator.notEqual, isNotEqualTo),
        if (isLessThan != null) filter(FilterOperator.lessThan, isLessThan),
        if (isLessThanOrEqualTo != null)
          filter(FilterOperator.lessThanOrEqual, isLessThanOrEqualTo),
        if (isGreaterThan != null)
          filter(FilterOperator.graterThan, isGreaterThan),
        if (isGreaterThanOrEqualTo != null)
          filter(FilterOperator.graterThanOrEqual, isGreaterThanOrEqualTo),
        if (arrayContains != null)
          filter(FilterOperator.arrayContains, arrayContains),
        if (arrayContainsAny != null)
          filter(FilterOperator.arrayContainsAny, arrayContainsAny.toList()),
        if (whereIn != null) filter(FilterOperator.IN, whereIn.toList()),
        if (whereNotIn != null)
          filter(FilterOperator.NOT_IN, whereNotIn.toList()),
        if (isNull != null)
          filter(isNull ? FilterOperator.equal : FilterOperator.notEqual, null),
      ];
      if (filters.isEmpty) {
        throw ArgumentError(
          "Invalid query. where('$fieldPath') needs at least one non-null "
          'named argument. Use isNull to compare with null.',
        );
      }
    }

    core.Query result = query;
    for (final Filter filter in filters) {
      result = whereFilter(result, filter);
    }
    return result;
  }

  /// Returns [query] with [filter] added, or [query] itself when [filter] is
  /// a composite filter without any filters.
  core.Query whereFilter(core.Query query, Filter filter) {
    final core_filter.Filter parsedFilter = _parseFilter(query, filter);
    if (parsedFilter.filters.isEmpty) {
      // Return the existing query if not adding any more filters (because the
      // composite filter is empty).
      return query;
    }
    _validateNewFilter(query, parsedFilter);
    return query.filter(parsedFilter);
  }

  FieldFilter _parseFieldFilter(
    core.Query query,
    api.UnaryFilter fieldFilterData,
  ) {
    final FieldPath fieldPath = fieldFilterData.field;
    final FilterOperator op = fieldFilterData.operator;
    final Object? value = fieldFilterData.value;
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    checkNotNull(op, 'Provided op must not be null.');
    final FieldValue fieldValue;
    final core.FieldPath internalPath = fieldPath.internalPath;
    if (internalPath.isKeyField) {
      if (op == FilterOperator.arrayContains ||
          op == FilterOperator.arrayContainsAny) {
        throw ArgumentError(
          'Invalid query. You can\'t perform "$op" queries on FieldPath.documentId().',
        );
      } else if (op == FilterOperator.IN || op == FilterOperator.NOT_IN) {
        _validateDisjunctiveFilterElements(value, op);
        final List<FieldValue> referenceList = <FieldValue>[];
        for (Object? arrayValue in value! as List<Object?>) {
          referenceList.add(_parseDocumentIdValue(query, arrayValue));
        }
        fieldValue = ArrayValue.fromList(referenceList);
      } else {
        fieldValue = _parseDocumentIdValue(query, value);
      }
    } else {
      if (op == FilterOperator.IN ||
          op == FilterOperator.NOT_IN ||
          op == FilterOperator.arrayContainsAny) {
        _validateDisjunctiveFilterElements(value, op);
      }
      fieldValue = dataConverter.parseQueryValue(
        value,
        allowArrays: op == FilterOperator.IN || op == FilterOperator.NOT_IN,
        methodName: 'where',
      );
    }
    return FieldFilter(internalPath, op, fieldValue);
  }

  core_filter.Filter _parseCompositeFilter(
    core.Query query,
    api.CompositeFilter compositeFilterData,
  ) {
    final List<core_filter.Filter> parsedFilters = <core_filter.Filter>[];
    for (Filter filter in compositeFilterData.filters) {
      final core_filter.Filter parsedFilter = _parseFilter(query, filter);
      if (parsedFilter.filters.isNotEmpty) {
        parsedFilters.add(parsedFilter);
      }
    }

    // For composite filters containing 1 filter, return the only filter.
    // For example: AND(FieldFilter1) == FieldFilter1
    if (parsedFilters.length == 1) {
      return parsedFilters[0];
    }
    return core_filter.CompositeFilter(
      parsedFilters,
      compositeFilterData.operator,
    );
  }

  core_filter.Filter _parseFilter(core.Query query, Filter filter) {
    if (filter is api.UnaryFilter) {
      return _parseFieldFilter(query, filter);
    } else if (filter is api.CompositeFilter) {
      return _parseCompositeFilter(query, filter);
    }
    throw fail(
      'Parsing is only supported for Filter.UnaryFilter and Filter.CompositeFilter.',
    );
  }

  FieldValue _parseDocumentIdValue(core.Query query, Object? value) {
    if (value is String) {
      if (value.isEmpty) {
        throw ArgumentError(
          'Invalid query. When querying with FieldPath.documentId() you must provide a valid document ID, but it was an empty string.',
        );
      }

      if (!query.isCollectionGroupQuery && value.contains('/')) {
        throw ArgumentError(
          'Invalid query. When querying a collection by FieldPath.documentId() you must provide a plain document ID, but "$value" contains a "/" character.',
        );
      }

      final ResourcePath path = query.path.appendField(
        ResourcePath.fromString(value),
      );
      if (!DocumentKey.isDocumentKey(path)) {
        throw ArgumentError(
          'Invalid query. When querying a collection group by FieldPath.documentId(), the value provided must result in a valid document path, but "$path" is not because it has an odd number of segments (${path.length}).',
        );
      }
      return ReferenceValue.valueOf(databaseId, DocumentKey.fromPath(path));
    }
    final DocumentKey? key = referenceKey(value);
    if (key != null) {
      return ReferenceValue.valueOf(databaseId, key);
    } else {
      throw ArgumentError(
        'Invalid query. When querying with FieldPath.documentId() you must provide a valid String or '
        'DocumentReference, but it was of type: ${typeName(value)}',
      );
    }
  }

  void _validateDisjunctiveFilterElements(Object? value, FilterOperator op) {
    if (value is! List || value.isEmpty) {
      throw ArgumentError(
        'Invalid Query. A non-empty array is required for "$op" filters.',
      );
    }
  }

  List<FilterOperator> _conflictingOps(FilterOperator op) {
    switch (op) {
      case FilterOperator.notEqual:
        return <FilterOperator>[FilterOperator.notEqual, FilterOperator.NOT_IN];
      case FilterOperator.arrayContainsAny:
      case FilterOperator.IN:
        return <FilterOperator>[FilterOperator.NOT_IN];
      case FilterOperator.NOT_IN:
        return <FilterOperator>[
          FilterOperator.arrayContainsAny,
          FilterOperator.IN,
          FilterOperator.NOT_IN,
          FilterOperator.notEqual,
        ];
      default:
        return <FilterOperator>[];
    }
  }

  void _validateNewFieldFilter(core.Query query, FieldFilter fieldFilter) {
    final FilterOperator filterOp = fieldFilter.operator;

    final FilterOperator? conflictingOperator = _findOpInsideFilters(
      query.filters,
      _conflictingOps(filterOp),
    );
    if (conflictingOperator != null) {
      // We special case when it's a duplicate op to give a slightly clearer
      // error message.
      if (conflictingOperator == filterOp) {
        throw ArgumentError(
          'Invalid Query. You cannot use more than one "$filterOp" filter.',
        );
      } else {
        throw ArgumentError(
          'Invalid Query. You cannot use "$filterOp" filters with "$conflictingOperator" filters.',
        );
      }
    }
  }

  void _validateNewFilter(core.Query query, core_filter.Filter filter) {
    core.Query testQuery = query;
    for (FieldFilter subfilter in filter.flattenedFilters) {
      _validateNewFieldFilter(testQuery, subfilter);
      testQuery = testQuery.filter(subfilter);
    }
  }

  FilterOperator? _findOpInsideFilters(
    List<core_filter.Filter> filters,
    List<FilterOperator> operators,
  ) {
    for (core_filter.Filter filter in filters) {
      for (FieldFilter fieldFilter in filter.flattenedFilters) {
        if (operators.contains(fieldFilter.operator)) {
          return fieldFilter.operator;
        }
      }
    }
    return null;
  }

  /// Returns [query] ordered by [fieldPath] as well.
  core.Query orderBy(
    core.Query query,
    core.FieldPath fieldPath, {
    required bool descending,
  }) {
    if (query.getStartAt() != null) {
      throw ArgumentError(
        'Invalid query. You must not call Query.startAt() or Query.startAfter() before calling Query.orderBy().',
      );
    }
    if (query.getEndAt() != null) {
      throw ArgumentError(
        'Invalid query. You must not call Query.endAt() or Query.endBefore() before calling Query.orderBy().',
      );
    }
    final OrderByDirection dir = descending
        ? OrderByDirection.descending
        : OrderByDirection.ascending;
    return query.orderBy(OrderBy.getInstance(dir, fieldPath));
  }

  /// Returns [query] limited to its first [limit] documents.
  core.Query limit(core.Query query, int limit) {
    if (limit <= 0) {
      throw ArgumentError(
        'Invalid Query. Query limit ($limit) is invalid. Limit must be positive.',
      );
    }
    return query.limitToFirst(limit);
  }

  /// Returns [query] limited to its last [limit] documents.
  core.Query limitToLast(core.Query query, int limit) {
    if (limit <= 0) {
      throw ArgumentError(
        'Invalid Query. Query limitToLast ($limit) is invalid. Limit must be positive.',
      );
    }
    return query.limitToLast(limit);
  }

  /// The bound of [query] at [document], the document of a snapshot (null
  /// when the document of the snapshot does not exist), for the cursor
  /// method [methodName].
  Bound boundFromDocument(
    core.Query query,
    String methodName,
    Document? document, {
    required bool inclusive,
  }) {
    if (document == null) {
      throw ArgumentError(
        'Can\'t use a DocumentSnapshot for a document that doesn\'t exist for $methodName().',
      );
    }
    final List<FieldValue> components = <FieldValue>[];

    // Because people expect to continue/end a query at the exact document provided, we need to use the implicit sort
    // order rather than the explicit sort order, because it's guaranteed to contain the document key. That way the
    // position becomes unambiguous and the query continues/ends exactly at the provided document. Without the key (by
    // using the explicit sort orders), multiple documents could match the position, yielding duplicate results.
    for (OrderBy orderBy in query.orderByConstraints) {
      if (orderBy.field == core.FieldPath.keyPath) {
        components.add(ReferenceValue.valueOf(databaseId, document.key));
      } else {
        final FieldValue? value = document.getField(orderBy.field);
        if (value is ServerTimestampValue) {
          throw ArgumentError(
            'Invalid query. You are trying to start or end a query using a document for which the field '
            '\'${orderBy.field}\' is an uncommitted server timestamp. (Since the value of this field is unknown, you '
            'cannot start/end a query with it.)',
          );
        } else if (value != null) {
          components.add(value);
        } else {
          throw ArgumentError(
            'Invalid query. You are trying to start or end a query using a document for which the field '
            '\'${orderBy.field}\' (used as the orderBy) does not exist.',
          );
        }
      }
    }
    return Bound(position: components, inclusive: inclusive);
  }

  /// The bound of [query] at the field [values], for the cursor method
  /// [methodName].
  Bound boundFromFields(
    core.Query query,
    String methodName,
    List<Object?> values, {
    required bool inclusive,
  }) {
    // Use explicit order by's because it has to match the query the user made
    final List<OrderBy> explicitOrderBy = query.explicitSortOrder;
    if (values.length > explicitOrderBy.length) {
      throw ArgumentError(
        'Too many arguments provided to $methodName(). The number of arguments must be less than or equal to the '
        'number of orderBy() clauses.',
      );
    }

    final List<FieldValue> components = <FieldValue>[];
    for (int i = 0; i < values.length; i++) {
      final Object? rawValue = values[i];
      final OrderBy orderBy = explicitOrderBy[i];
      if (orderBy.field == core.FieldPath.keyPath) {
        if (rawValue is! String) {
          throw ArgumentError(
            'Invalid query. Expected a string for document ID in $methodName(), but got $rawValue.',
          );
        }
        final String documentId = rawValue;

        if (!query.isCollectionGroupQuery && documentId.contains('/')) {
          throw ArgumentError(
            'Invalid query. When querying a collection and ordering by FieldPath.documentId(), the value passed to $methodName() must be a plain document ID, but "$documentId" contains a slash.',
          );
        }
        final ResourcePath path = query.path.appendField(
          ResourcePath.fromString(documentId),
        );
        if (!DocumentKey.isDocumentKey(path)) {
          throw ArgumentError(
            'Invalid query. When querying a collection group and ordering by FieldPath.documentId(), the value passed to $methodName() must result in a valid document path, but "$path" is not because it contains an odd number of segments.',
          );
        }
        final DocumentKey key = DocumentKey.fromPath(path);
        components.add(ReferenceValue.valueOf(databaseId, key));
      } else {
        final FieldValue wrapped = dataConverter.parseQueryValue(
          rawValue,
          methodName: methodName,
        );
        components.add(wrapped);
      }
    }

    return Bound(position: components, inclusive: inclusive);
  }
}
