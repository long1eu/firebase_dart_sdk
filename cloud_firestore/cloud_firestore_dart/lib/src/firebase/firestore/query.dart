// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart'
    hide Filter, CompositeFilter;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/listen_to_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/distance_measure.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart'
    as api
    show UnaryFilter;
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/listen_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_builder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/snapshot_listen_options.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:firebase_app_dart/internal.dart';

/// An enum for the direction of a sort.
enum Direction {
  /// Smallest values first.
  ascending,

  /// Largest values first.
  descending,
}

/// A [Query] which you can read or listen to. You can also construct refined [Query] objects by adding filters and
/// ordering.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class Query<T extends dynamic> {
  /// Implementation detail of the SDK; not part of the supported API. Use [Firestore.collection] or
  /// [Firestore.collectionGroup].
  const Query._(this._query, this.firestore, [this.converter]);

  /// The converter attached with [withConverter], or null for raw maps.
  final FirestoreDataConverter<T>? converter;

  /// Returns a query that converts documents with [converter] (type [U]).
  /// Filters, ordering and limits are kept. Use [withoutConverter] to go
  /// back to raw maps.
  Query<U> withConverter<U extends Object?>(
    FirestoreDataConverter<U> converter,
  ) {
    return Query<U>._(query, firestore, converter);
  }

  /// Returns a query over the same documents that yields raw
  /// `Map<String, Object?>` values (the equivalent of `withConverter(null)` in
  /// the JS SDK).
  Query<Map<String, Object?>> withoutConverter() {
    return Query<Map<String, Object?>>._(query, firestore);
  }

  final core.Query _query;

  /// The [Firestore] instance this query belongs to.
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
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.equal,
      value,
    );
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
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.notEqual,
      value,
    );
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
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.lessThan,
      value,
    );
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
    return _whereHelper(
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.lessThanOrEqual,
      value,
    );
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
    return _whereHelper(
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.graterThan,
      value,
    );
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
    return _whereHelper(
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.graterThanOrEqual,
      value,
    );
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
    return _whereHelper(
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.arrayContains,
      value,
    );
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
    return _whereHelper(
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.arrayContainsAny,
      value,
    );
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field, the value must be an array, and that the
  /// array must contain at least one value from the provided array.
  ///
  /// It cannot be combined with [whereNotIn]; the backend validates other combinations.
  Query<T> whereArrayContainsAnyField(
    FieldPath fieldPath,
    List<Object?> value,
  ) {
    return _whereHelper(fieldPath, FilterOperator.arrayContainsAny, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must equal one of the
  /// values from the provided array.
  ///
  /// It cannot be combined with [whereNotIn]; the backend validates other combinations.
  Query<T> whereIn(String field, List<Object?> value) {
    return _whereHelper(
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.IN,
      value,
    );
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
      FieldPath.fromDotSeparatedPath(field),
      FilterOperator.NOT_IN,
      value,
    );
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
    return _withQuery(
      _builder.where(
        query,
        fieldOrFilter,
        isEqualTo: isEqualTo,
        isNotEqualTo: isNotEqualTo,
        isLessThan: isLessThan,
        isLessThanOrEqualTo: isLessThanOrEqualTo,
        isGreaterThan: isGreaterThan,
        isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
        arrayContains: arrayContains,
        arrayContainsAny: arrayContainsAny,
        whereIn: whereIn,
        whereNotIn: whereNotIn,
        isNull: isNull,
      ),
    );
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should satisfy
  /// the relation constraint provided.
  Query<T> _whereHelper(FieldPath fieldPath, FilterOperator op, Object? value) {
    return _withQuery(
      _builder.whereFilter(query, api.UnaryFilter(fieldPath, op, value)),
    );
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
    checkNotNull(direction, 'Provided direction must not be null.');
    return _withQuery(
      _builder.orderBy(
        query,
        fieldPath.internalPath,
        descending: direction != Direction.ascending,
      ),
    );
  }

  /// Creates and returns a new [Query] that's additionally limited to only return up to the specified number of
  /// documents. This overrides a previous [limitToLast].
  ///
  /// [limit] the maximum number of items to return.
  ///
  /// Returns the created Query.
  Query<T> limit(int limit) {
    return _withQuery(_builder.limit(query, limit));
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
    return _withQuery(_builder.limitToLast(query, limit));
  }

  /// Creates and returns a new [Query] that starts at the provided document (inclusive). The starting position is
  /// relative to the order of the query. The document must contain all of the fields provided in the orderBy of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to start at.
  ///
  /// Returns the created Query.
  Query<T> startAtDocument(DocumentSnapshot<Object?> snapshot) {
    checkNotNull<DocumentSnapshot<Object?>>(
      snapshot,
      'Provided snapshot must not be null.',
    );
    final Bound bound = _builder.boundFromDocument(
      query,
      'startAt',
      snapshot.document,
      inclusive: true,
    );
    return _withQuery(query.startAt(bound));
  }

  /// Creates and returns a new [Query] that starts at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> startAt(List<Object?> fieldValues) {
    final Bound bound = _builder.boundFromFields(
      query,
      'startAt',
      fieldValues,
      inclusive: true,
    );
    return _withQuery(query.startAt(bound));
  }

  /// Creates and returns a new [Query] that starts after the provided document (exclusive). The starting position is
  /// relative to the order of the query. The document must contain all of the fields provided in the [orderBy] of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to start after.
  ///
  /// Returns the created Query.
  Query<T> startAfterDocument(DocumentSnapshot<Object?> snapshot) {
    checkNotNull<DocumentSnapshot<Object?>>(
      snapshot,
      'Provided snapshot must not be null.',
    );
    final Bound bound = _builder.boundFromDocument(
      query,
      'startAfter',
      snapshot.document,
      inclusive: false,
    );
    return _withQuery(query.startAt(bound));
  }

  /// Creates and returns a new [Query] that starts after the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query after, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> startAfter(List<Object?> fieldValues) {
    final Bound bound = _builder.boundFromFields(
      query,
      'startAfter',
      fieldValues,
      inclusive: false,
    );
    return _withQuery(query.startAt(bound));
  }

  /// Creates and returns a new [Query] that ends before the provided document (exclusive). The end position is relative
  /// to the order of the query. The document must contain all of the fields provided in the orderBy of this query.
  ///
  /// [snapshot] the snapshot of the document to end before.
  ///
  /// Returns the created Query.
  Query<T> endBeforeDocument(DocumentSnapshot<Object?> snapshot) {
    checkNotNull<DocumentSnapshot<Object?>>(
      snapshot,
      'Provided snapshot must not be null.',
    );
    final Bound bound = _builder.boundFromDocument(
      query,
      'endBefore',
      snapshot.document,
      inclusive: false,
    );
    return _withQuery(query.endAt(bound));
  }

  /// Creates and returns a new [Query] that ends before the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query before, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> endBefore(List<Object?> fieldValues) {
    final Bound bound = _builder.boundFromFields(
      query,
      'endBefore',
      fieldValues,
      inclusive: false,
    );
    return _withQuery(query.endAt(bound));
  }

  /// Creates and returns a new [Query] that ends at the provided document (inclusive). The end position is relative to
  /// the order of the query. The document must contain all of the fields provided in the [orderBy] of this query.
  ///
  /// [snapshot] the snapshot of the document to end at.
  ///
  /// Returns the created Query.
  Query<T> endAtDocument(DocumentSnapshot<Object?> snapshot) {
    checkNotNull<DocumentSnapshot<Object?>>(
      snapshot,
      'Provided snapshot must not be null.',
    );
    final Bound bound = _builder.boundFromDocument(
      query,
      'endAt',
      snapshot.document,
      inclusive: true,
    );
    return _withQuery(query.endAt(bound));
  }

  /// Creates and returns a new [Query] that ends at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query<T> endAt(List<Object?> fieldValues) {
    final Bound bound = _builder.boundFromFields(
      query,
      'endAt',
      fieldValues,
      inclusive: true,
    );
    return _withQuery(query.endAt(bound));
  }

  QueryBuilder get _builder => QueryBuilder(
    firestore.databaseId,
    firestore.dataConverter,
    _referenceKey,
  );

  /// This query with [newQuery] as its internal query.
  Query<T> _withQuery(core.Query newQuery) {
    // A filter that adds nothing returns the query it was given.
    return identical(newQuery, query)
        ? this
        : Query<T>._(newQuery, firestore, converter);
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
      final ViewSnapshot viewSnap = await firestore.client
          .getDocumentsFromLocalCache(query);

      return QuerySnapshotInternal.create<T>(
        Query<T>._(query, firestore, converter),
        viewSnap,
        firestore,
      );
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
            FirestoreErrorCode.unavailable,
          );
        } else {
          return snapshot;
        }
      }),
    );
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
      distanceThreshold: distanceThreshold,
    );
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
        'Invalid vector query: the query vector must be a VectorValue or a List<double>, but was ${queryVector.runtimeType}.',
      );
    }
    return VectorQueryInternal.create(
      this,
      vectorField.internalPath,
      vector,
      limit,
      distanceMeasure,
      distanceResultField: distanceResultField,
      distanceThreshold: distanceThreshold,
    );
  }

  /// Returns an [AggregateQuery] that counts the documents in the result set of
  /// this query, without downloading the documents.
  ///
  /// The count is computed on the server: it fails when the client is offline.
  AggregateQuery count() => AggregateQueryInternal.create(
    this,
    <AggregateField>[AggregateField.count()],
  );

  /// Returns an [AggregateQuery] that calculates the given aggregations over the
  /// result set of this query without downloading the documents.
  AggregateQuery aggregate(List<AggregateField> aggregateFields) {
    if (aggregateFields.isEmpty) {
      throw ArgumentError('At least one AggregateField is required.');
    }
    return AggregateQueryInternal.create(this, aggregateFields);
  }

  /// Returns an [AggregateQuery] that calculates the given aggregations over the
  /// result set of this query, with results keyed by user-chosen aliases, as
  /// the JS SDK's `getAggregateFromServer(query, {total: sum('price')})`:
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
    return AggregateQueryInternal.withAliases(this, aggregates);
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
    final ListenOptions options = _internalOptions(
      changes ?? MetadataChanges.exclude,
    );
    return _getSnapshotsInternal(options);
  }

  /// Starts listening with the given [options], which also select the
  /// [ListenSource]: with [ListenSource.cache] the events are raised from the
  /// local cache only (local writes, cache updates) and the backend is not
  /// contacted for this listener.
  Stream<QuerySnapshot<T>> getSnapshotsWithOptions(
    SnapshotListenOptions options,
  ) {
    return _getSnapshotsInternal(
      _internalOptions(options.metadataChanges, options.source),
    );
  }

  void _validateHasExplicitOrderByForLimitToLast() {
    QueryBuilder.validateHasExplicitOrderByForLimitToLast(query);
  }

  Stream<QuerySnapshot<T>> _getSnapshotsInternal(ListenOptions options) {
    _validateHasExplicitOrderByForLimitToLast();
    return listenToQuery(firestore.client, query, options).map(
      (ViewSnapshot snapshot) =>
          QuerySnapshotInternal.create<T>(this, snapshot, firestore),
    );
  }

  /// Converts the  API options object to the internal options object.
  static ListenOptions _internalOptions(
    MetadataChanges metadataChanges, [
    ListenSource source = ListenSource.defaultSource,
  ]) {
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
  int get hashCode => query.hashCode ^ firestore.hashCode ^ converter.hashCode;

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

/// The key of [value] when it is a document reference of this library.
DocumentKey? _referenceKey(Object? value) =>
    value is DocumentReference ? value.key : null;

/// A [CollectionReference] can be used for adding documents, getting document references, and
/// querying for documents (using the methods inherited from [Query]).
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test
/// mocks. Subclassing is not supported in production code and new SDK releases may break code that
/// does so.
class CollectionReference<T extends dynamic> extends Query<T> {
  CollectionReference._(
    ResourcePath path,
    Firestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) : super._(core.Query(_checkPath(path)), firestore, converter);

  /// Not an assert: the check has to hold in release builds too.
  static ResourcePath _checkPath(ResourcePath path) {
    if (path.length.remainder(2) != 1) {
      throw ArgumentError(
        'Invalid collection reference. Collection references must have an odd number of '
        'segments, but ${path.canonicalString} has ${path.length}',
      );
    }
    return path;
  }

  /// Return The id of the collection.
  String get id => query.path.last;

  /// Gets a [DocumentReference] to the document that contains this collection. Only subcollections
  /// are contained in a document. For root collections, returns null.
  ///
  /// Returns the [DocumentReference] that contains this collection or null if this is a root
  /// collection.
  DocumentReference<Map<String, Object?>>? get parent {
    final ResourcePath parentPath = query.path.popLast();
    if (parentPath.isEmpty) {
      return null;
    } else {
      return DocumentReferenceInternal.create<Map<String, Object?>>(
        DocumentKey.fromPath(parentPath),
        firestore,
      );
    }
  }

  /// Gets the path of this collection (relative to the root of the database) as a slash-separated
  /// string.
  ///
  /// Returns the path of this collection.
  String get path => query.path.canonicalString;

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within
  /// this collection.
  ///
  /// [documentPath] a slash-separated relative path to a document.
  ///
  /// Returns the [DocumentReference] instance.
  DocumentReference<T> doc([String? documentPath]) => document(documentPath);

  /// Gets a [DocumentReference] instance that refers to the document at the specified path within
  /// this collection. Same as [doc].
  @Deprecated('Use doc instead.')
  DocumentReference<T> document([String? documentPath]) {
    final String path = documentPath ?? autoId();
    return DocumentReferenceInternal.forPath<T>(
      query.path.appendField(ResourcePath.fromString(path)),
      firestore,
      converter,
    );
  }

  /// Adds a new document to this collection with the specified data, assigning it a document ID
  /// automatically.
  ///
  /// [data] a [Map] containing the data for the new document.
  ///
  /// Returns a Future that will be resolved with the [DocumentReference] of the newly created
  /// document.
  Future<DocumentReference<T>> add(T data) async {
    checkNotNull<Object>(data, 'Provided data must not be null.');
    final DocumentReference<T> ref = document();
    await ref.set(data);
    return ref;
  }

  /// Returns a collection reference to the same collection that converts data
  /// with [converter] (type [U]) when reading and writing. Use
  /// [withoutConverter] to go back to raw maps.
  @override
  CollectionReference<U> withConverter<U extends Object?>(
    FirestoreDataConverter<U> converter,
  ) {
    return CollectionReference<U>._(query.path, firestore, converter);
  }

  /// Returns a collection reference to the same collection that reads and
  /// writes raw `Map<String, Object?>` values.
  @override
  CollectionReference<Map<String, Object?>> withoutConverter() {
    return CollectionReference<Map<String, Object?>>._(query.path, firestore);
  }
}

/// Members of [Query] for the SDK itself. Not exported by the public libraries.
extension QueryInternal<T> on Query<T> {
  /// The core query this public query wraps.
  core.Query get query => _query;

  /// Wraps the core [query] of [firestore].
  static Query<T> create<T extends dynamic>(
    core.Query query,
    Firestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) => Query<T>._(query, firestore, converter);
}

/// Members of [CollectionReference] for the SDK itself. Not exported by the public libraries.
extension CollectionReferenceInternal<T> on CollectionReference<T> {
  /// A reference to the collection at [path] in [firestore]. Throws an [ArgumentError] if [path] is not a
  /// collection path.
  static CollectionReference<T> create<T extends dynamic>(
    ResourcePath path,
    Firestore firestore, [
    FirestoreDataConverter<T>? converter,
  ]) => CollectionReference<T>._(path, firestore, converter);
}
