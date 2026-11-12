// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart'
    as core_filter show Filter, CompositeFilter;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart'
    hide Filter, CompositeFilter;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/listen_to_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/filter.dart'
    as api show CompositeFilter, UnaryFilter;
import 'package:cloud_firestore_vm/src/firebase/firestore/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/snapshot_listen_options.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/vector_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/vector_value.dart';
import 'package:meta/meta.dart';

/// An enum for the direction of a sort.
enum Direction { ascending, descending }

/// A [Query] which you can read or listen to. You can also construct refined [Query] objects by adding filters and
/// ordering.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class Query<T extends dynamic> {
  @internal
  const Query(this.query, this.firestore, [this.converter]);

  /// The converter attached with [withConverter], or null for raw maps.
  final FirestoreDataConverter<T>? converter;

  /// Returns a query that converts documents with [converter] (type [U]).
  /// Filters, ordering and limits are kept. Use [withoutConverter] to go
  /// back to raw maps.
  Query<U> withConverter<U extends Object?>(
      FirestoreDataConverter<U> converter) {
    return Query<U>(query, firestore, converter);
  }

  /// Returns a query over the same documents that yields raw
  /// `Map<String, Object?>` values (the equivalent of `withConverter(null)` in
  /// the JS SDK).
  Query<Map<String, Object?>> withoutConverter() {
    return Query<Map<String, Object?>>(query, firestore);
  }

  final core.Query query;
  final Firestore firestore;

  /// Creates and returns a new Query with the additional filter that documents must contain the specified field and the
  /// value should be equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereEqualTo(String field, Object? value) {
    return _whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.equal, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be equal to the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereEqualToField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.equal, value);
  }

  /// Creates and returns a new Query with the additional filter that documents must contain the specified field and the
  /// value does not equal the specified value.
  ///
  /// A Query can have only one [whereNotEqualTo] filter, and it cannot be combined with [whereNotIn]
  /// (this client check also applies inside [Filter.or] / [Filter.and]).
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereNotEqualTo(String field, Object? value) {
    return _whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.notEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value does not equal the specified value.
  ///
  /// A Query can have only one [whereNotEqualToField] filter, and it cannot be combined with
  /// [whereNotInField].
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereNotEqualToField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.notEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be less than the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereLessThan(String field, Object? value) {
    return _whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.lessThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be less than the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereLessThanField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.lessThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be less than or equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereLessThanOrEqualTo(String field, Object? value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.lessThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be less than or equal to the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereLessThanOrEqualToField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.lessThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be greater than the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereGreaterThan(String field, Object? value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.graterThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be greater than the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereGreaterThanField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.graterThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be greater than or equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereGreaterThanOrEqualTo(String field, Object? value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.graterThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be greater than or equal to the specified value.
  ///
  /// [fieldPath] The path of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query<T> whereGreaterThanOrEqualToField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.graterThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field, the
  /// value must be an array, and that the array must contain the provided value.
  ///
  /// Several array-contains filters can be combined; the backend validates the combination.
  ///
  /// [field] The name of the field containing an array to search
  /// [value] The value that must be contained in the array
  ///
  /// Returns the created [Query].
  Query<T> whereArrayContains(String field, Object? value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.arrayContains, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field, the
  /// value must be an array, and that the array must contain the provided value.
  ///
  /// Several array-contains filters can be combined; the backend validates the combination.
  ///
  /// [fieldPath] The path of the field containing an array to search
  /// [value] The value that must be contained in the array
  ///
  /// Returns the created [Query].
  Query<T> whereArrayContainsField(FieldPath fieldPath, Object? value) {
    return _whereHelper(fieldPath, FilterOperator.arrayContains, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field, the value must be a list, and that the
  /// list must contain at least one value from the provided array.
  ///
  /// It cannot be combined with [whereNotIn]; the backend validates other combinations.
  Query<T> whereArrayContainsAny(String field, List<Object?> value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.arrayContainsAny, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field, the value must be an array, and that the
  /// array must contain at least one value from the provided array.
  ///
  /// It cannot be combined with [whereNotIn]; the backend validates other combinations.
  Query<T> whereArrayContainsAnyField(FieldPath fieldPath, List<Object?> value) {
    return _whereHelper(fieldPath, FilterOperator.arrayContainsAny, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must equal one of the
  /// values from the provided array.
  ///
  /// It cannot be combined with [whereNotIn]; the backend validates other combinations.
  Query<T> whereIn(String field, List<Object?> value) {
    return _whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.IN, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must equal one of the
  /// values from the provided array.
  ///
  /// It cannot be combined with [whereNotIn]; the backend validates other combinations.
  Query<T> whereInField(FieldPath fieldPath, List<Object?> value) {
    return _whereHelper(fieldPath, FilterOperator.IN, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must not equal any of the
  /// values from the provided array.
  ///
  /// A Query can have only one [whereNotIn] filter, and it cannot be combined
  /// with [whereArrayContainsAny], [whereIn] or [whereNotEqualTo].
  Query<T> whereNotIn(String field, List<Object?> value) {
    return _whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.NOT_IN, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must not equal any of the
  /// values from the provided array.
  ///
  /// A Query can have only one [whereNotInField] filter, and it cannot be
  /// combined with [whereArrayContainsAny], [whereIn] or [whereNotEqualToField].
  Query<T> whereNotInField(FieldPath fieldPath, List<Object?> value) {
    return _whereHelper(fieldPath, FilterOperator.NOT_IN, value);
  }

  /// Creates and returns a new [Query] with the additional [filter].
  ///
  /// The filter can be a single field filter created with the [Filter]
  /// factories, or a conjunction/disjunction created with [Filter.and] and
  /// [Filter.or] (OR queries). A composite filter without any filters returns
  /// this query unchanged.
  ///
  /// NOTE: a FlutterFire-style `where(field, isEqualTo: ...)` with named
  /// parameters is intentionally not provided here; it can be added later as
  /// an extension that builds the same [Filter]s.
  Query<T> where(Filter filter) {
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
  Query<T> _whereHelper(FieldPath fieldPath, FilterOperator op, Object? value) {
    return where(api.UnaryFilter(fieldPath, op, value));
  }

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
            'Invalid query. You can\'t perform "$op" queries on FieldPath.documentId().');
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
      fieldValue = firestore.dataConverter.parseQueryValue(value,
          allowArrays: op == FilterOperator.IN || op == FilterOperator.NOT_IN);
    }
    return FieldFilter(internalPath, op, fieldValue);
  }

  /// Takes an [api.CompositeFilter], parses each of its subfilters, and
  /// returns a new filter that is constructed using the parsed values.
  core_filter.Filter _parseCompositeFilter(
      api.CompositeFilter compositeFilterData) {
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
        parsedFilters, compositeFilterData.operator);
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
        'Parsing is only supported for Filter.UnaryFilter and Filter.CompositeFilter.');
  }

  /// Parses the given documentIdValue into a ReferenceValue, throwing
  /// appropriate errors if the value is anything other than a DocumentReference
  /// or String, or if the string is malformed.
  FieldValue _parseDocumentIdValue(Object? value) {
    if (value is String) {
      if (value.isEmpty) {
        throw ArgumentError(
            'Invalid query. When querying with FieldPath.documentId() you must provide a valid document ID, but it was an empty string.');
      }

      if (!query.isCollectionGroupQuery && value.contains('/')) {
        throw ArgumentError(
            'Invalid query. When querying a collection by FieldPath.documentId() you must provide a plain document ID, but "$value" contains a "/" character.');
      }

      final ResourcePath path =
          query.path.appendField(ResourcePath.fromString(value));
      if (!DocumentKey.isDocumentKey(path)) {
        throw ArgumentError(
            'Invalid query. When querying a collection group by FieldPath.documentId(), the value provided must result in a valid document path, but "$path" is not because it has an odd number of segments (${path.length}).');
      }
      return ReferenceValue.valueOf(
          firestore.databaseId, DocumentKey.fromPath(path));
    } else if (value is DocumentReference) {
      return ReferenceValue.valueOf(firestore.databaseId, value.key);
    } else {
      throw ArgumentError(
          'Invalid query. When querying with FieldPath.documentId() you must provide a valid String or '
          'DocumentReference, but it was of type: ${typeName(value)}');
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
          'Invalid Query. A non-empty array is required for "$op" filters.');
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
          FilterOperator.notEqual
        ];
      default:
        return <FilterOperator>[];
    }
  }

  /// Checks that adding the given field filter to the given query yields a
  /// valid query.
  void _validateNewFieldFilter(core.Query query, FieldFilter fieldFilter) {
    final FilterOperator filterOp = fieldFilter.operator;

    final FilterOperator? conflictingOperator =
        _findOpInsideFilters(query.filters, _conflictingOps(filterOp));
    if (conflictingOperator != null) {
      // We special case when it's a duplicate op to give a slightly clearer
      // error message.
      if (conflictingOperator == filterOp) {
        throw ArgumentError(
            'Invalid Query. You cannot use more than one "$filterOp" filter.');
      } else {
        throw ArgumentError(
            'Invalid Query. You cannot use "$filterOp" filters with "$conflictingOperator" filters.');
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
      List<core_filter.Filter> filters, List<FilterOperator> operators) {
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
  Query<T> orderByField(FieldPath fieldPath,
      [Direction direction = Direction.ascending]) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    return _orderBy(fieldPath.internalPath, direction);
  }

  Query<T> _orderBy(core.FieldPath fieldPath, Direction direction) {
    checkNotNull(direction, 'Provided direction must not be null.');
    if (query.getStartAt() != null) {
      throw ArgumentError(
          'Invalid query. You must not call Query.startAt() or Query.startAfter() before calling Query.orderBy().');
    }
    if (query.getEndAt() != null) {
      throw ArgumentError(
          'Invalid query. You must not call Query.endAt() or Query.endBefore() before calling Query.orderBy().');
    }
    final OrderByDirection dir = direction == Direction.ascending
        ? OrderByDirection.ascending
        : OrderByDirection.descending;
    return Query<T>(query.orderBy(OrderBy.getInstance(dir, fieldPath)), firestore, converter);
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
          'Invalid Query. Query limit ($limit) is invalid. Limit must be positive.');
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
          'Invalid Query. Query limitToLast ($limit) is invalid. Limit must be positive.');
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
    final Bound bound =
        _boundFromDocumentSnapshot('startAt', snapshot, /*before:*/ true);
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that starts at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> startAt(List<Object?> fieldValues) {
    final Bound bound =
        _boundFromFields('startAt', fieldValues, /*before:*/ true);
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
    final Bound bound =
        _boundFromDocumentSnapshot('startAfter', snapshot, /*before:*/ false);
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that starts after the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query after, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> startAfter(List<Object?> fieldValues) {
    final Bound bound =
        _boundFromFields('startAfter', fieldValues, /*before:*/ false);
    return Query<T>(query.startAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends before the provided document (exclusive). The end position is relative
  /// to the order of the query. The document must contain all of the fields provided in the orderBy of this query.
  ///
  /// [snapshot] the snapshot of the document to end before.
  ///
  /// Returns the created Query.
  Query<T> endBeforeDocument(DocumentSnapshot<Object?> snapshot) {
    final Bound bound =
        _boundFromDocumentSnapshot('endBefore', snapshot, /*before:*/ true);
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends before the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query before, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> endBefore(List<Object?> fieldValues) {
    final Bound bound =
        _boundFromFields('endBefore', fieldValues, /*before:*/ true);
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends at the provided document (inclusive). The end position is relative to
  /// the order of the query. The document must contain all of the fields provided in the [orderBy] of this query.
  ///
  /// [snapshot] the snapshot of the document to end at.
  ///
  /// Returns the created Query.
  Query<T> endAtDocument(DocumentSnapshot<Object?> snapshot) {
    final Bound bound =
        _boundFromDocumentSnapshot('endAt', snapshot, /*before:*/ false);
    return Query<T>(query.endAt(bound), firestore, converter);
  }

  /// Creates and returns a new [Query] that ends at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> endAt(List<Object?> fieldValues) {
    final Bound bound =
        _boundFromFields('endAt', fieldValues, /*before:*/ false);
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
      String methodName, DocumentSnapshot<Object?> snapshot, bool before) {
    checkNotNull<DocumentSnapshot<Object?>>(
        snapshot, 'Provided snapshot must not be null.');
    if (!snapshot.exists) {
      throw ArgumentError(
          'Can\'t use a DocumentSnapshot for a document that doesn\'t exist for $methodName().');
    }
    final Document document = snapshot.document!;
    final List<FieldValue> components = <FieldValue>[];

    // Because people expect to continue/end a query at the exact document provided, we need to use the implicit sort
    // order rather than the explicit sort order, because it's guaranteed to contain the document key. That way the
    // position becomes unambiguous and the query continues/ends exactly at the provided document. Without the key (by
    // using the explicit sort orders), multiple documents could match the position, yielding duplicate results.
    for (OrderBy orderBy in query.orderByConstraints) {
      if (orderBy.field == core.FieldPath.keyPath) {
        components
            .add(ReferenceValue.valueOf(firestore.databaseId, document.key));
      } else {
        final FieldValue? value = document.getField(orderBy.field);
        if (value is ServerTimestampValue) {
          throw ArgumentError(
              'Invalid query. You are trying to start or end a query using a document for which the field '
              '\'${orderBy.field}\' is an uncommitted server timestamp. (Since the value of this field is unknown, you '
              'cannot start/end a query with it.)');
        } else if (value != null) {
          components.add(value);
        } else {
          throw ArgumentError(
              'Invalid query. You are trying to start or end a query using a document for which the field '
              '\'${orderBy.field}\' (used as the orderBy) does not exist.');
        }
      }
    }
    return Bound(position: components, before: before);
  }

  /// Converts a list of field values to Bound.
  Bound _boundFromFields(String methodName, List<Object?> values, bool before) {
    // Use explicit order by's because it has to match the query the user made
    final List<OrderBy> explicitOrderBy = query.explicitSortOrder;
    if (values.length > explicitOrderBy.length) {
      throw ArgumentError(
          'Too many arguments provided to $methodName(). The number of arguments must be less than or equal to the '
          'number of orderBy() clauses.');
    }

    final List<FieldValue> components = <FieldValue>[];
    for (int i = 0; i < values.length; i++) {
      final Object? rawValue = values[i];
      final OrderBy orderBy = explicitOrderBy[i];
      if (orderBy.field == core.FieldPath.keyPath) {
        if (rawValue is! String) {
          throw ArgumentError(
              'Invalid query. Expected a string for document ID in $methodName(), but got $rawValue.');
        }
        final String documentId = rawValue;

        if (!query.isCollectionGroupQuery && documentId.contains('/')) {
          throw ArgumentError(
              'Invalid query. When querying a collection and ordering by FieldPath.documentId(), the value passed to $methodName() must be a plain document ID, but "$documentId" contains a slash.');
        }
        final ResourcePath path =
            query.path.appendField(ResourcePath.fromString(documentId));
        if (!DocumentKey.isDocumentKey(path)) {
          throw ArgumentError(
              'Invalid query. When querying a collection group and ordering by FieldPath.documentId(), the value passed to $methodName() must result in a valid document path, but "$path" is not because it contains an odd number of segments.');
        }
        final DocumentKey key = DocumentKey.fromPath(path);
        components.add(ReferenceValue.valueOf(firestore.databaseId, key));
      } else {
        final FieldValue wrapped =
            firestore.dataConverter.parseQueryValue(rawValue);
        components.add(wrapped);
      }
    }

    return Bound(position: components, before: before);
  }

  /// Executes the query and returns the results as a [QuerySnapshot].
  ///
  /// By default, get() attempts to provide up-to-date data when possible by waiting for data from the server, but it
  /// may return cached data or fail if you are offline and the server cannot be reached. This behavior can be altered
  /// via the [Source] parameter.
  ///
  /// [source] a value to configure the get behavior.
  ///
  /// Returns a Future that will be resolved with the results of the [Query].
  Future<QuerySnapshot<T>> get([Source source = Source.defaultSource]) async {
    _validateHasExplicitOrderByForLimitToLast();
    if (source == Source.cache) {
      final ViewSnapshot viewSnap =
          await firestore.client.getDocumentsFromLocalCache(query);

      return QuerySnapshot<T>(
          Query<T>(query, firestore, converter), viewSnap, firestore);
    } else {
      return _getViaSnapshotListener(source);
    }
  }

  Future<QuerySnapshot<T>> _getViaSnapshotListener(Source source) {
    const ListenOptions options = ListenOptions.all();

    return _firstAndCancel(
        _getSnapshotsInternal(options).map((QuerySnapshot<T> snapshot) {
      if (snapshot.metadata.isFromCache && source == Source.server) {
        throw FirestoreError(
            'Failed to get documents from server. (However, these documents may exist in the local cache. Run again '
            'without setting source to Source.server to retrieve the cached documents.)',
            FirestoreErrorCode.unavailable);
      } else {
        return snapshot;
      }
    }));
  }

  /// Returns a [VectorQuery] that finds the [limit] documents whose
  /// [vectorField] is nearest to [queryVector] according to [distanceMeasure].
  ///
  /// [queryVector] is a [VectorValue] or a `List<double>`. If
  /// [distanceResultField] is set, the computed distance is stored in that
  /// field of each returned document. If [distanceThreshold] is set, only
  /// documents within that threshold are returned.
  ///
  /// The search runs on the server only. The filters of this query narrow the
  /// candidates; its orderings are superseded by the distance ordering.
  VectorQuery findNearest(
    String vectorField,
    Object queryVector,
    int limit,
    DistanceMeasure distanceMeasure, {
    String? distanceResultField,
    double? distanceThreshold,
  }) {
    return findNearestField(
        FieldPath.fromDotSeparatedPath(vectorField),
        queryVector,
        limit,
        distanceMeasure,
        distanceResultField: distanceResultField,
        distanceThreshold: distanceThreshold);
  }

  /// Same as [findNearest] but takes the vector field as a [FieldPath].
  VectorQuery findNearestField(
    FieldPath vectorField,
    Object queryVector,
    int limit,
    DistanceMeasure distanceMeasure, {
    String? distanceResultField,
    double? distanceThreshold,
  }) {
    final VectorValue vector;
    if (queryVector is VectorValue) {
      vector = queryVector;
    } else if (queryVector is List<double>) {
      vector = VectorValue(queryVector);
    } else {
      throw ArgumentError(
          'Invalid vector query: the query vector must be a VectorValue or a List<double>, but was ${queryVector.runtimeType}.');
    }
    return VectorQuery(this, vectorField.internalPath, vector, limit,
        distanceMeasure,
        distanceResultField: distanceResultField,
        distanceThreshold: distanceThreshold);
  }

  /// Returns an [AggregateQuery] that counts the documents in the result set of
  /// this query, without downloading the documents.
  ///
  /// The count is computed on the server: it fails when the client is offline.
  AggregateQuery count() =>
      AggregateQuery(this, <AggregateField>[AggregateField.count()]);

  /// Returns an [AggregateQuery] that calculates the given aggregations over the
  /// result set of this query without downloading the documents.
  AggregateQuery aggregate(List<AggregateField> aggregateFields) {
    if (aggregateFields.isEmpty) {
      throw ArgumentError('At least one AggregateField is required.');
    }
    return AggregateQuery(this, aggregateFields);
  }

  /// Return cached results first and then queries the server with resume token
  /// to ensure unnecessary reads are not made.
  Stream<QuerySnapshot<T>> get snapshots {
    final ListenOptions options = _internalOptions(MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  /// Return cached results first and then queries the server with resume token
  /// to ensure unnecessary reads are not made.
  Stream<QuerySnapshot<T>> getSnapshots([MetadataChanges? changes]) {
    final ListenOptions options =
        _internalOptions(changes ?? MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  /// Starts listening with the given [options], which also select the
  /// [ListenSource]: with [ListenSource.cache] the events are raised from the
  /// local cache only (local writes, cache updates) and the backend is not
  /// contacted for this listener.
  Stream<QuerySnapshot<T>> getSnapshotsWithOptions(SnapshotListenOptions options) {
    return _getSnapshotsInternal(
        _internalOptions(options.metadataChanges, options.source));
  }

  void _validateHasExplicitOrderByForLimitToLast() {
    if (query.hasLimitToLast && query.explicitSortOrder.isEmpty) {
      throw StateError(
          'limitToLast() queries require specifying at least one orderBy() clause');
    }
  }

  Stream<QuerySnapshot<T>> _getSnapshotsInternal(ListenOptions options) {
    _validateHasExplicitOrderByForLimitToLast();
    return listenToQuery(firestore.client, query, options).map(
        (ViewSnapshot snapshot) => QuerySnapshot<T>(this, snapshot, firestore));
  }

  /// Converts the  API options object to the internal options object.
  static ListenOptions _internalOptions(MetadataChanges metadataChanges,
      [ListenSource source = ListenSource.defaultSource]) {
    return ListenOptions(
      source: source,
      includeDocumentMetadataChanges:
          metadataChanges == MetadataChanges.include,
      includeQueryMetadataChanges: metadataChanges == MetadataChanges.include,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Query &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          firestore == other.firestore &&
          converter == other.converter;

  @override
  int get hashCode =>
      query.hashCode ^ firestore.hashCode ^ converter.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('firestore', firestore))
        .toString();
  }
}

/// Returns the first event of [stream] and waits for the subscription to be
/// completely cancelled, so a subsequent listen on the same query doesn't race
/// with the removal of the previous listener.
Future<T> _firstAndCancel<T>(Stream<T> stream) async {
  await for (final T value in stream) {
    return value;
  }
  throw StateError('No element');
}
