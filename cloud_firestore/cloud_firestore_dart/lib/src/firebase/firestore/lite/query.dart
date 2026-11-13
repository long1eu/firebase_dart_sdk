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
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
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
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/aggregate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart'
    show Direction;
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/datastore/datastore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:meta/meta.dart';

/// A [Query] which you can read. You can also construct refined [Query]
/// objects by adding filters and ordering.
///
/// This is the query of Firestore Lite: [get] is one request to the backend.
/// There are no listeners and no cache.
///
// The builder methods and their validation are those of the Query of the
// main library (query.dart); keep the two in step.
class Query<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.collection] or [Firestore.collectionGroup].
  @internal
  const Query(this.query, this.firestore, [this.converter]);

  /// The converter applied to the documents this query returns, if any.
  final FirestoreDataConverter<T>? converter;

  /// Returns the same query, returning objects of type [U] made by
  /// [converter].
  Query<U> withConverter<U extends Object?>(
    FirestoreDataConverter<U> converter,
  ) {
    return Query<U>(query, firestore, converter);
  }

  /// Returns the same query without a converter.
  Query<Map<String, Object?>> withoutConverter() {
    return Query<Map<String, Object?>>(query, firestore);
  }

  /// Implementation detail of the SDK; not part of the supported API.
  @internal
  final core.Query query;

  /// The Firestore instance of this query.
  final Firestore firestore;

  /// Creates and returns a new [Query] with additional filters.
  ///
  /// [fieldOrFilter] is either a [Filter], or a field (a dot-separated
  /// [String] path or a [FieldPath]) that is constrained with the named
  /// arguments, in the FlutterFire style:
  ///
  /// ```dart
  /// query.where(Filter.or([Filter.equalTo('a', 1), Filter.equalTo('b', 2)]));
  /// query.where('age', isGreaterThanOrEqualTo: 18, isLessThan: 65);
  /// query.where(FieldPath.documentIdField, whereIn: ['a', 'b']);
  /// ```
  ///
  /// A [Filter] can be a single field filter created with the [Filter]
  /// factories, or a conjunction/disjunction created with [Filter.and] and
  /// [Filter.or] (OR queries). A composite filter without any filters returns
  /// this query unchanged. No named argument may be given with a [Filter].
  ///
  /// With a field, every named argument that is given adds one filter and all
  /// of them must match. A null argument is the same as an omitted one, so
  /// use `isNull: true` (equal to null) or `isNull: false` (not equal to null)
  /// to compare with null. At least one non-null named argument is required:
  /// unlike FlutterFire, which returns the query unchanged in that case (so
  /// `where('a', isEqualTo: valueThatIsNull)` silently filters nothing), this
  /// method throws.
  ///
  /// Throws an [ArgumentError] if [fieldOrFilter] has another type, if named
  /// arguments are given with a [Filter], or if none is given with a field.
  Query<T> where(
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
        fieldPath = FieldPath.fromDotSeparatedPath(fieldOrFilter);
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

    Query<T> result = this;
    for (final Filter filter in filters) {
      result = result._where(filter);
    }
    return result;
  }

  Query<T> _where(Filter filter) {
    final core_filter.Filter parsedFilter = _parseFilter(filter);
    if (parsedFilter.filters.isEmpty) {
      // Return the existing query if not adding any more filters (because the
      // composite filter is empty).
      return this;
    }
    _validateNewFilter(parsedFilter);
    return Query<T>(query.filter(parsedFilter), firestore, converter);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should satisfy
  /// the relation constraint provided.
  /// Takes a [api.UnaryFilter], parses the value object and returns a new
  /// [FieldFilter] for the field, operator, and parsed value.
  FieldFilter _parseFieldFilter(api.UnaryFilter fieldFilterData) {
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
          referenceList.add(_parseDocumentIdValue(arrayValue));
        }
        fieldValue = ArrayValue.fromList(referenceList);
      } else {
        fieldValue = _parseDocumentIdValue(value);
      }
    } else {
      if (op == FilterOperator.IN ||
          op == FilterOperator.NOT_IN ||
          op == FilterOperator.arrayContainsAny) {
        _validateDisjunctiveFilterElements(value, op);
      }
      fieldValue = firestore.dataConverter.parseQueryValue(
        value,
        allowArrays: op == FilterOperator.IN || op == FilterOperator.NOT_IN,
      );
    }
    return FieldFilter(internalPath, op, fieldValue);
  }

  /// Takes an [api.CompositeFilter], parses each of its subfilters, and
  /// returns a new filter that is constructed using the parsed values.
  core_filter.Filter _parseCompositeFilter(
    api.CompositeFilter compositeFilterData,
  ) {
    final List<core_filter.Filter> parsedFilters = <core_filter.Filter>[];
    for (Filter filter in compositeFilterData.filters) {
      final core_filter.Filter parsedFilter = _parseFilter(filter);
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

  /// Takes a filter whose value has not been parsed, parses the value object
  /// and returns a [FieldFilter] or composite filter with parsed values.
  core_filter.Filter _parseFilter(Filter filter) {
    if (filter is api.UnaryFilter) {
      return _parseFieldFilter(filter);
    } else if (filter is api.CompositeFilter) {
      return _parseCompositeFilter(filter);
    }
    throw fail(
      'Parsing is only supported for Filter.UnaryFilter and Filter.CompositeFilter.',
    );
  }

  /// Parses the given documentIdValue into a ReferenceValue, throwing
  /// appropriate errors if the value is anything other than a DocumentReference
  /// or String, or if the string is malformed.
  FieldValue _parseDocumentIdValue(Object? value) {
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
      return ReferenceValue.valueOf(
        firestore.databaseId,
        DocumentKey.fromPath(path),
      );
    } else if (value is DocumentReference) {
      return ReferenceValue.valueOf(firestore.databaseId, value.key);
    } else {
      throw ArgumentError(
        'Invalid query. When querying with FieldPath.documentId() you must provide a valid String or '
        'DocumentReference, but it was of type: ${typeName(value)}',
      );
    }
  }

  /// Validates that the value passed into a disjunctive filter satisfies all
  /// array requirements.
  ///
  /// The limits on the number of elements (10 for `in`/`not-in`/
  /// `array-contains-any`, 30 disjunctions per query) are no longer checked on
  /// the client; the backend enforces them.
  void _validateDisjunctiveFilterElements(Object? value, FilterOperator op) {
    if (value is! List || value.isEmpty) {
      throw ArgumentError(
        'Invalid Query. A non-empty array is required for "$op" filters.',
      );
    }
  }

  /// Given an operator, returns the set of operators that cannot be used with
  /// it.
  ///
  /// This is not a comprehensive check, and this function should be removed in
  /// the long term. Validations should occur in the Firestore backend.
  ///
  /// Operators in a query must adhere to the following set of rules:
  ///
  ///  1. [FilterOperator.notEqual] cannot be used with another
  ///     [FilterOperator.notEqual] or [FilterOperator.NOT_IN].
  ///  2. [FilterOperator.NOT_IN] cannot be used with
  ///     [FilterOperator.arrayContainsAny], [FilterOperator.IN],
  ///     [FilterOperator.notEqual] or another [FilterOperator.NOT_IN].
  ///
  /// There is no limit on the number of inequality fields, and several `in`
  /// or `array-contains` filters can be combined (for example in an OR).
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

  /// Checks that adding the given field filter to the given query yields a
  /// valid query.
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

  /// Checks that adding the given filter to the current query is valid.
  void _validateNewFilter(core_filter.Filter filter) {
    core.Query testQuery = query;
    for (FieldFilter subfilter in filter.flattenedFilters) {
      _validateNewFieldFilter(testQuery, subfilter);
      testQuery = testQuery.filter(subfilter);
    }
  }

  /// Checks if any of the provided filter operators are included in the given
  /// list of filters (including the ones nested in composite filters) and
  /// returns the first one that is, or null if none are.
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

  /// Creates and returns a new [Query] that's additionally sorted by the specified field.
  /// Optionally in descending order instead of ascending.
  ///
  /// [field] the field to sort by.
  /// [direction] the direction to sort.
  ///
  /// Returns the created Query.
  Query<T> orderBy(String field, [Direction direction = Direction.ascending]) {
    return orderByField(FieldPath.fromDotSeparatedPath(field), direction);
  }

  /// Creates and returns a new [Query] that's additionally sorted by the specified field, optionally in descending
  /// order instead of ascending.
  ///
  /// [fieldPath] the field to sort by.
  /// [direction] the direction to sort.
  ///
  /// Returns the created Query.
  Query<T> orderByField(
    FieldPath fieldPath, [
    Direction direction = Direction.ascending,
  ]) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    return _orderBy(fieldPath.internalPath, direction);
  }

  Query<T> _orderBy(core.FieldPath fieldPath, Direction direction) {
    checkNotNull(direction, 'Provided direction must not be null.');
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
    final OrderByDirection dir = direction == Direction.ascending
        ? OrderByDirection.ascending
        : OrderByDirection.descending;
    return Query<T>(
      query.orderBy(OrderBy.getInstance(dir, fieldPath)),
      firestore,
      converter,
    );
  }

  /// Creates and returns a new [Query] that's additionally limited to only return up to the specified number of
  /// documents. This overrides a previous [limitToLast].
  ///
  /// [limit] the maximum number of items to return.
  ///
  /// Returns the created Query.
  Query<T> limit(int limit) {
    if (limit <= 0) {
      throw ArgumentError(
        'Invalid Query. Query limit ($limit) is invalid. Limit must be positive.',
      );
    }
    return Query<T>(query.limitToFirst(limit), firestore, converter);
  }

  /// Creates and returns a new [Query] that only returns the last matching documents up to the specified number. This
  /// overrides a previous [limit].
  ///
  /// You must specify at least one [orderBy] clause for limitToLast queries, otherwise a [StateError] is thrown when
  /// the query is executed. The results are returned in the order of the query (not reversed).
  ///
  /// [limit] the maximum number of items to return.
  ///
  /// Returns the created Query.
  Query<T> limitToLast(int limit) {
    if (limit <= 0) {
      throw ArgumentError(
        'Invalid Query. Query limitToLast ($limit) is invalid. Limit must be positive.',
      );
    }
    return Query<T>(query.limitToLast(limit), firestore, converter);
  }

  /// Creates and returns a new [Query] that starts at the provided document (inclusive). The starting position is
  /// relative to the order of the query. The document must contain all of the fields provided in the orderBy of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to start at.
  ///
  /// Returns the created Query.
  Query<T> startAtDocument(DocumentSnapshot<Object?> snapshot) {
    final Bound bound = _boundFromDocumentSnapshot(
      'startAt',
      snapshot,
      /*inclusive:*/ true,
    );
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that starts at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> startAt(List<Object?> fieldValues) {
    final Bound bound = _boundFromFields(
      'startAt',
      fieldValues,
      /*inclusive:*/ true,
    );
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that starts after the provided document (exclusive). The starting position is
  /// relative to the order of the query. The document must contain all of the fields provided in the [orderBy] of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to start after.
  ///
  /// Returns the created Query.
  Query<T> startAfterDocument(DocumentSnapshot<Object?> snapshot) {
    final Bound bound = _boundFromDocumentSnapshot(
      'startAfter',
      snapshot,
      /*inclusive:*/ false,
    );
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that starts after the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query after, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> startAfter(List<Object?> fieldValues) {
    final Bound bound = _boundFromFields(
      'startAfter',
      fieldValues,
      /*inclusive:*/ false,
    );
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends before the provided document (exclusive). The end position is relative
  /// to the order of the query. The document must contain all of the fields provided in the orderBy of this query.
  ///
  /// [snapshot] the snapshot of the document to end before.
  ///
  /// Returns the created Query.
  Query<T> endBeforeDocument(DocumentSnapshot<Object?> snapshot) {
    final Bound bound = _boundFromDocumentSnapshot(
      'endBefore',
      snapshot,
      /*inclusive:*/ false,
    );
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends before the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query before, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> endBefore(List<Object?> fieldValues) {
    final Bound bound = _boundFromFields(
      'endBefore',
      fieldValues,
      /*inclusive:*/ false,
    );
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends at the provided document (inclusive). The end position is relative to
  /// the order of the query. The document must contain all of the fields provided in the [orderBy] of this query.
  ///
  /// [snapshot] the snapshot of the document to end at.
  ///
  /// Returns the created Query.
  Query<T> endAtDocument(DocumentSnapshot<Object?> snapshot) {
    final Bound bound = _boundFromDocumentSnapshot(
      'endAt',
      snapshot,
      /*inclusive:*/ true,
    );
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> endAt(List<Object?> fieldValues) {
    final Bound bound = _boundFromFields(
      'endAt',
      fieldValues,
      /*inclusive:*/ true,
    );
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Create a [Bound] from a query given the document.
  ///
  /// Note that the [Bound] will always include the key of the document and so only the provided document will compare
  /// equal to the returned position.
  ///
  /// Will throw if the document does not contain all fields of the order by of the query or if any of the fields in the
  /// order by are an uncommitted server timestamp.
  Bound _boundFromDocumentSnapshot(
    String methodName,
    DocumentSnapshot<Object?> snapshot,
    bool inclusive,
  ) {
    checkNotNull<DocumentSnapshot<Object?>>(
      snapshot,
      'Provided snapshot must not be null.',
    );
    if (!snapshot.exists) {
      throw ArgumentError(
        'Can\'t use a DocumentSnapshot for a document that doesn\'t exist for $methodName().',
      );
    }
    final Document document = snapshot.document!;
    final List<FieldValue> components = <FieldValue>[];

    // Because people expect to continue/end a query at the exact document provided, we need to use the implicit sort
    // order rather than the explicit sort order, because it's guaranteed to contain the document key. That way the
    // position becomes unambiguous and the query continues/ends exactly at the provided document. Without the key (by
    // using the explicit sort orders), multiple documents could match the position, yielding duplicate results.
    for (OrderBy orderBy in query.orderByConstraints) {
      if (orderBy.field == core.FieldPath.keyPath) {
        components.add(
          ReferenceValue.valueOf(firestore.databaseId, document.key),
        );
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

  /// Converts a list of field values to Bound.
  Bound _boundFromFields(
    String methodName,
    List<Object?> values,
    bool inclusive,
  ) {
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
        components.add(ReferenceValue.valueOf(firestore.databaseId, key));
      } else {
        final FieldValue wrapped = firestore.dataConverter.parseQueryValue(
          rawValue,
        );
        components.add(wrapped);
      }
    }

    return Bound(position: components, inclusive: inclusive);
  }

  /// Runs the query on the backend and returns the matching documents.
  ///
  /// A [limitToLast] query is sent with its orderings flipped and the result
  /// is reversed here, as the JS SDK does.
  Future<QuerySnapshot<T>> get() async {
    if (query.hasLimitToLast && query.explicitSortOrder.isEmpty) {
      throw StateError(
        'limitToLast() queries require specifying at least one orderBy() clause',
      );
    }
    final List<Document> documents = await firestore.run(
      (Datastore datastore) => datastore.runQuery(query),
    );
    return QuerySnapshot<T>(
      this,
      query.hasLimitToLast ? documents.reversed.toList() : documents,
    );
  }

  /// Returns an [AggregateQuery] that counts the documents in the result set
  /// of this query without downloading them.
  AggregateQuery count() =>
      AggregateQuery(this, <AggregateField>[AggregateField.count()]);

  /// Returns an [AggregateQuery] that calculates the given aggregations over
  /// the result set of this query without downloading the documents.
  AggregateQuery aggregate(List<AggregateField> aggregateFields) {
    if (aggregateFields.isEmpty) {
      throw ArgumentError('At least one AggregateField is required.');
    }
    return AggregateQuery(this, aggregateFields);
  }

  /// Returns an [AggregateQuery] that calculates the given aggregations over
  /// the result set of this query, with results keyed by user-chosen aliases:
  ///
  /// ```dart
  /// final snapshot = await query.aggregateWithAliases({
  ///   'total': AggregateField.sum('price'),
  ///   'n': AggregateField.count(),
  /// }).get();
  /// snapshot.data(); // {'total': 42, 'n': 3}
  /// ```
  ///
  /// Any string is a valid alias (aliases are not sent to the server) and the
  /// same aggregation may appear under several aliases.
  AggregateQuery aggregateWithAliases(Map<String, AggregateField> aggregates) {
    if (aggregates.isEmpty) {
      throw ArgumentError('At least one AggregateField is required.');
    }
    return AggregateQuery.withAliases(this, aggregates);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Query &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          identical(firestore, other.firestore) &&
          converter == other.converter;

  @override
  int get hashCode => Object.hash(query, firestore, converter);

  @override
  String toString() => 'Query{query: $query}';
}

/// A [CollectionReference] can be used for adding documents, getting document
/// references, and querying for documents (using the methods inherited from
/// [Query]).
class CollectionReference<T extends dynamic> extends Query<T> {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.collection] or [DocumentReference.collection].
  @internal
  CollectionReference(
    ResourcePath path,
    Firestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) : super(core.Query(path), firestore, converter);

  /// Implementation detail of the SDK; not part of the supported API. Use
  /// [Firestore.collection] or [DocumentReference.collection].
  @internal
  factory CollectionReference.forPath(
    ResourcePath path,
    Firestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) {
    if (path.length.remainder(2) != 1) {
      throw ArgumentError(
        'Invalid collection reference. Collection references must have an odd number of '
        'segments, but ${path.canonicalString} has ${path.length}',
      );
    }
    return CollectionReference<T>(path, firestore, converter);
  }

  /// The ID of the collection.
  String get id => query.path.last;

  /// The document that contains this collection, or null for a collection at
  /// the root of the database.
  DocumentReference<Map<String, Object?>>? get parent {
    final ResourcePath parentPath = query.path.popLast();
    if (parentPath.isEmpty) {
      return null;
    }
    return DocumentReference<Map<String, Object?>>(
      DocumentKey.fromPath(parentPath),
      firestore,
    );
  }

  /// The path of the collection, relative to the root of the database.
  String get path => query.path.canonicalString;

  /// Returns a [DocumentReference] to the document at [documentPath] within
  /// this collection, or to a new document with an auto-generated ID when no
  /// path is given.
  DocumentReference<T> doc([String? documentPath]) {
    return DocumentReference<T>.forPath(
      query.path.appendField(ResourcePath.fromString(documentPath ?? autoId())),
      firestore,
      converter,
    );
  }

  /// Adds a new document with [data] to this collection, with an
  /// auto-generated ID, and returns its reference once the backend has
  /// written it.
  Future<DocumentReference<T>> add(T data) async {
    final DocumentReference<T> ref = doc();
    await ref.set(data);
    return ref;
  }

  @override
  CollectionReference<U> withConverter<U extends Object?>(
    FirestoreDataConverter<U> converter,
  ) {
    return CollectionReference<U>(query.path, firestore, converter);
  }

  @override
  CollectionReference<Map<String, Object?>> withoutConverter() {
    return CollectionReference<Map<String, Object?>>(query.path, firestore);
  }

  @override
  String toString() => 'CollectionReference{path: $path}';
}
