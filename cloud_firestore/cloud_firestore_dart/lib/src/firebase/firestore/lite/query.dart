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
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/aggregate.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/lite/snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart'
    show Direction;
import 'package:cloud_firestore_dart/src/firebase/firestore/query_builder.dart';
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
// The filters, orderings, limits and cursors are parsed and validated by
// query_builder.dart, which the Query of the main library uses too.
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
        : Query<T>(newQuery, firestore, converter);
  }

  /// Runs the query on the backend and returns the matching documents.
  ///
  /// A [limitToLast] query is sent with its orderings flipped and the result
  /// is reversed here, as the JS SDK does.
  Future<QuerySnapshot<T>> get() async {
    QueryBuilder.validateHasExplicitOrderByForLimitToLast(query);
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

/// The key of [value] when it is a document reference of this library.
DocumentKey? _referenceKey(Object? value) =>
    value is DocumentReference ? value.key : null;
