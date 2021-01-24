// File created by
// Lung Razvan <long1eu>
// on 25/09/2018

import 'dart:async';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/event_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query_stream.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/view_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart'
    as core;
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/source.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:rxdart/rxdart.dart';

/// An enum for the direction of a sort.
enum Direction { ascending, descending }

/// A [Query] which you can read or listen to. You can also construct refined [Query] objects by adding filters and
/// ordering.
///
/// **Subclassing Note**: Firestore classes are not meant to be subclassed except for use in test mocks. Subclassing is
/// not supported in production code and new SDK releases may break code that does so.
class Query {
  const Query(this.query, this.firestore)
      : assert(query != null),
        assert(firestore != null);

  final core.Query query;
  final Firestore firestore;

  /// Creates and returns a new Query with the additional filter that documents must contain the specified field and the
  /// value should be equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query whereEqualTo(String field, Object value) {
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
  Query whereEqualToField(FieldPath fieldPath, Object value) {
    return _whereHelper(fieldPath, FilterOperator.equal, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be less than the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query whereLessThan(String field, Object value) {
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
  Query whereLessThanField(FieldPath fieldPath, Object value) {
    return _whereHelper(fieldPath, FilterOperator.lessThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be less than or equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query whereLessThanOrEqualTo(String field, Object value) {
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
  Query whereLessThanOrEqualToField(FieldPath fieldPath, Object value) {
    return _whereHelper(fieldPath, FilterOperator.lessThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be greater than the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query whereGreaterThan(String field, Object value) {
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
  Query whereGreaterThanField(FieldPath fieldPath, Object value) {
    return _whereHelper(fieldPath, FilterOperator.graterThan, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field and
  /// the value should be greater than or equal to the specified value.
  ///
  /// [field] The name of the field to compare
  /// [value] The value for comparison
  ///
  /// Returns the created [Query].
  Query whereGreaterThanOrEqualTo(String field, Object value) {
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
  Query whereGreaterThanOrEqualToField(FieldPath fieldPath, Object value) {
    return _whereHelper(fieldPath, FilterOperator.graterThanOrEqual, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field, the
  /// value must be an array, and that the array must contain the provided value.
  ///
  /// A Query can have only one [whereArrayContains] filter and it cannot be
  /// combined with [whereArrayContainsAny].
  ///
  /// [field] The name of the field containing an array to search
  /// [value] The value that must be contained in the array
  ///
  /// Returns the created [Query].
  Query whereArrayContains(String field, Object value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.arrayContains, value);
  }

  /// Creates and returns a new [Query] with the additional filter that documents must contain the specified field, the
  /// value must be an array, and that the array must contain the provided value.
  ///
  /// A Query can have only one [whereArrayContains] filter and it cannot be
  /// combined with [whereArrayContainsAny].
  ///
  /// [fieldPath] The path of the field containing an array to search
  /// [value] The value that must be contained in the array
  ///
  /// Returns the created [Query].
  Query whereArrayContainsField(FieldPath fieldPath, Object value) {
    return _whereHelper(fieldPath, FilterOperator.arrayContains, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field, the value must be a list, and that the
  /// list must contain at least one value from the provided array.
  ///
  /// A Query can have only one [whereArrayContainsAny] filter and it cannot be
  /// combined with [whereArrayContains] or [whereIn].
  // TODO(in-queries): Expose to public once backend is ready.
  Query whereArrayContainsAny(String field, List<Object> value) {
    return _whereHelper(FieldPath.fromDotSeparatedPath(field),
        FilterOperator.arrayContainsAny, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field, the value must be an array, and that the
  /// array must contain at least one value from the provided array.
  ///
  /// A Query can have only one [whereArrayContainsAny] filter and it cannot be
  /// combined with [whereArrayContains] or [whereIn].
  // TODO(in-queries): Expose to public once backend is ready.
  Query whereArrayContainsAnyField(FieldPath fieldPath, List<Object> value) {
    return _whereHelper(fieldPath, FilterOperator.arrayContainsAny, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must equal one of the
  /// values from the provided array.
  ///
  /// A Query can have only one [whereIn] filter, and it cannot be combined with
  /// [whereArrayContainsAny].
  // TODO(in-queries): Expose to public once backend is ready.
  Query whereIn(String field, List<Object> value) {
    return _whereHelper(
        FieldPath.fromDotSeparatedPath(field), FilterOperator.IN, value);
  }

  /// Creates and returns a new Query with the additional filter that documents
  /// must contain the specified field and the value must equal one of the
  /// values from the provided array.
  ///
  /// A Query can have only one [whereIn] filter, and it cannot be combined with
  /// [whereArrayContainsAny].
  // TODO(in-queries): Expose to public once backend is ready.
  Query whereInField(FieldPath fieldPath, List<Object> value) {
    return _whereHelper(fieldPath, FilterOperator.IN, value);
  }

  /// Creates and returns a new [Query] with the additional filter that
  /// documents must contain the specified field and the value should satisfy
  /// the relation constraint provided.
  Query _whereHelper(FieldPath fieldPath, FilterOperator op, Object value) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    checkNotNull(op, 'Provided op must not be null.');
    FieldValue fieldValue;
    final core.FieldPath internalPath = fieldPath.internalPath;
    if (internalPath.isKeyField) {
      if (op == FilterOperator.arrayContains ||
          op == FilterOperator.arrayContainsAny) {
        throw ArgumentError(
            'Invalid query. You can\'t perform "$op" queries on FieldPath.documentId().');
      } else if (op == FilterOperator.IN) {
        _validateDisjunctiveFilterElements(value, op);
        final List<FieldValue> referenceList = <FieldValue>[];
        for (Object arrayValue in value) {
          referenceList.add(_parseDocumentIdValue(arrayValue));
        }
        fieldValue = ArrayValue.fromList(referenceList);
      } else {
        fieldValue = _parseDocumentIdValue(value);
      }
    } else {
      if (op == FilterOperator.IN || op == FilterOperator.arrayContainsAny) {
        _validateDisjunctiveFilterElements(value, op);
      }
      fieldValue = firestore.userDataReader.parseQueryValue(value);
    }
    final Filter filter = FieldFilter(fieldPath.internalPath, op, fieldValue);
    _validateNewFilter(filter);
    return Query(query.filter(filter), firestore);
  }

  void _validateOrderByField(core.FieldPath field) {
    final core.FieldPath inequalityField = query.inequalityField;
    if (query.firstOrderByField == null && inequalityField != null) {
      _validateOrderByFieldMatchesInequality(field, inequalityField);
    }
  }

  /// Parses the given documentIdValue into a ReferenceValue, throwing
  /// appropriate errors if the value is anything other than a DocumentReference
  /// or String, or if the string is malformed.
  FieldValue _parseDocumentIdValue(Object value) {
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
  void _validateDisjunctiveFilterElements(Object value, FilterOperator op) {
    if (value is List) {
      if (value.isEmpty) {
        throw ArgumentError(
            'Invalid Query. A non-empty array is required for "$op" filters.');
      } else if (value.length > 10) {
        throw ArgumentError(
            'Invalid Query. "$op" filters support a maximum of 10 elements in the value array.');
      } else if (value.contains(null)) {
        throw ArgumentError(
            'Invalid Query. "$op" filters cannot contain "null" in the value array.');
      } else if (value
          .any((dynamic element) => element is double && element.isNaN)) {
        throw ArgumentError(
            'Invalid Query. "$op" filters cannot contain "NaN" in the value array.');
      }
    } else {
      throw ArgumentError(
          'Invalid Query. A non-empty array is required for "$op" filters.');
    }
  }

  void _validateOrderByFieldMatchesInequality(
      core.FieldPath orderBy, core.FieldPath inequality) {
    if (orderBy != inequality) {
      final String inequalityString = inequality.canonicalString;
      throw ArgumentError('Invalid query. You have an inequality where filter '
          '(whereLessThan(), whereGreaterThan(), etc.) on field '
          '"$inequalityString" and so you must also have "$inequalityString" '
          'as your first orderBy() field, but your first orderBy() is '
          'currently on field "${orderBy.canonicalString}" instead.');
    }
  }

  void _validateNewFilter(Filter filter) {
    if (filter is FieldFilter) {
      final FilterOperator filterOp = filter.operator;
      final bool isArrayOperator =
          FilterOperator.arrayOperators.contains(filterOp);
      final bool isDisjunctiveOperator =
          FilterOperator.disjunctiveOperators.contains(filterOp);

      if (filter.isInequality) {
        final core.FieldPath existingInequality = query.inequalityField;
        final core.FieldPath newInequality = filter.field;

        if (existingInequality != null && existingInequality != newInequality) {
          throw ArgumentError(
            'All where filters other than whereEqualTo() must be on the same field. But you have filters on '
            '\'${existingInequality.canonicalString}\' and \'${newInequality.canonicalString}\'',
          );
        }
        final core.FieldPath firstOrderByField = query.firstOrderByField;
        if (firstOrderByField != null) {
          _validateOrderByFieldMatchesInequality(
              firstOrderByField, newInequality);
        }
      } else if (isDisjunctiveOperator || isArrayOperator) {
        // You can have at most 1 disjunctive filter and 1 array filter. Check
        // if the new filter conflicts with an existing one.
        FilterOperator conflictingOperator;
        if (isDisjunctiveOperator) {
          conflictingOperator =
              query.findFilterOperator(FilterOperator.disjunctiveOperators);
        }
        if (conflictingOperator == null && isArrayOperator) {
          conflictingOperator =
              query.findFilterOperator(FilterOperator.arrayOperators);
        }
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
    }
  }

  /// Creates and returns a new [Query] that's additionally sorted by the specified field.
  /// Optionally in descending order instead of ascending.
  ///
  /// [field] the field to sort by.
  /// [direction] the direction to sort.
  ///
  /// Returns the created Query.
  Query orderBy(String field, [Direction direction = Direction.ascending]) {
    return orderByField(FieldPath.fromDotSeparatedPath(field), direction);
  }

  /// Creates and returns a new [Query] that's additionally sorted by the specified field, optionally in descending
  /// order instead of ascending.
  ///
  /// [fieldPath] the field to sort by.
  /// [direction] the direction to sort.
  ///
  /// Returns the created Query.
  Query orderByField(FieldPath fieldPath,
      [Direction direction = Direction.ascending]) {
    checkNotNull(fieldPath, 'Provided field path must not be null.');
    return _orderBy(fieldPath.internalPath, direction);
  }

  Query _orderBy(core.FieldPath fieldPath, Direction direction) {
    checkNotNull(direction, 'Provided direction must not be null.');
    if (query.getStartAt() != null) {
      throw AssertionError(
          'Invalid query. You must not call Query.startAt() or Query.startAfter() before calling Query.orderBy().');
    }
    if (query.getEndAt() != null) {
      throw ArgumentError(
          'Invalid query. You must not call Query.endAt() or Query.endBefore() before calling Query.orderBy().');
    }
    _validateOrderByField(fieldPath);
    final OrderByDirection dir = direction == Direction.ascending
        ? OrderByDirection.ascending
        : OrderByDirection.descending;
    return Query(query.orderBy(OrderBy.getInstance(dir, fieldPath)), firestore);
  }

  /// Creates and returns a new [Query] that's additionally limited to only return up to the specified number of
  /// documents.
  ///
  /// [limit] the maximum number of items to return.
  ///
  /// Returns the created Query.
  Query limit(int limit) {
    if (limit <= 0) {
      throw ArgumentError(
          'Invalid Query. Query limit ($limit) is invalid. Limit must be positive.');
    }
    return Query(query.limit(limit), firestore);
  }

  /// Creates and returns a new [Query] that starts at the provided document (inclusive). The starting position is
  /// relative to the order of the query. The document must contain all of the fields provided in the orderBy of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to start at.
  ///
  /// Returns the created Query.
  Query startAtDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        _boundFromDocumentSnapshot('startAt', snapshot, /*before:*/ true);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that starts at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query startAt(List<Object> fieldValues) {
    final Bound bound =
        _boundFromFields('startAt', fieldValues, /*before:*/ true);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that starts after the provided document (exclusive). The starting position is
  /// relative to the order of the query. The document must contain all of the fields provided in the [orderBy] of this
  /// query.
  ///
  /// [snapshot] the snapshot of the document to start after.
  ///
  /// Returns the created Query.
  Query startAfterDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        _boundFromDocumentSnapshot('startAfter', snapshot, /*before:*/ false);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that starts after the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to start this query after, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query startAfter(List<Object> fieldValues) {
    final Bound bound =
        _boundFromFields('startAfter', fieldValues, /*before:*/ false);
    return Query(query.startAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends before the provided document (exclusive). The end position is relative
  /// to the order of the query. The document must contain all of the fields provided in the orderBy of this query.
  ///
  /// [snapshot] the snapshot of the document to end before.
  ///
  /// Returns the created Query.
  Query endBeforeDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        _boundFromDocumentSnapshot('endBefore', snapshot, /*before:*/ true);
    return Query(query.endAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends before the provided fields relative to the order of the query. The
  /// order of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query before, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query endBefore(List<Object> fieldValues) {
    final Bound bound =
        _boundFromFields('endBefore', fieldValues, /*before:*/ true);
    return Query(query.endAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends at the provided document (inclusive). The end position is relative to
  /// the order of the query. The document must contain all of the fields provided in the [orderBy] of this query.
  ///
  /// [snapshot] the snapshot of the document to end at.
  ///
  /// Returns the created Query.
  Query endAtDocument(DocumentSnapshot snapshot) {
    final Bound bound =
        _boundFromDocumentSnapshot('endAt', snapshot, /*before:*/ false);
    return Query(query.endAt(bound), firestore);
  }

  /// Creates and returns a new [Query] that ends at the provided fields relative to the order of the query. The order
  /// of the field values must match the order of the order by clauses of the query.
  ///
  /// [fieldValues] the field values to end this query at, in order of the query's order by.
  ///
  /// Returns the created Query.
  Query endAt(List<Object> fieldValues) {
    final Bound bound =
        _boundFromFields('endAt', fieldValues, /*before:*/ false);
    return Query(query.endAt(bound), firestore);
  }

  /// Create a [Bound] from a query given the document.
  ///
  /// Note that the [Bound] will always include the key of the document and so only the provided document will compare
  /// equal to the returned position.
  ///
  /// Will throw if the document does not contain all fields of the order by of the query or if any of the fields in the
  /// order by are an uncommitted server timestamp.
  Bound _boundFromDocumentSnapshot(
      String methodName, DocumentSnapshot snapshot, bool before) {
    checkNotNull<DocumentSnapshot>(
        snapshot, 'Provided snapshot must not be null.');
    if (!snapshot.exists) {
      throw ArgumentError(
          'Can\'t use a DocumentSnapshot for a document that doesn\'t exist for $methodName().');
    }
    final Document document = snapshot.document;
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
        final FieldValue value = document.getField(orderBy.field);
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
  Bound _boundFromFields(String methodName, List<Object> values, bool before) {
    // Use explicit order by's because it has to match the query the user made
    final List<OrderBy> explicitOrderBy = query.explicitSortOrder;
    if (values.length > explicitOrderBy.length) {
      throw ArgumentError(
          'Too many arguments provided to $methodName(). The number of arguments must be less than or equal to the '
          'number of orderBy() clauses.');
    }

    final List<FieldValue> components = <FieldValue>[];
    for (int i = 0; i < values.length; i++) {
      final Object rawValue = values[i];
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
            firestore.userDataReader.parseQueryValue(rawValue);
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
  Future<QuerySnapshot> get([Source source = Source.defaultSource]) async {
    if (source == Source.cache) {
      final ViewSnapshot viewSnap =
          await firestore.client.getDocumentsFromLocalCache(query);

      return QuerySnapshot(Query(query, firestore), viewSnap, firestore);
    } else {
      return _getViaSnapshotListener(source);
    }
  }

  Future<QuerySnapshot> _getViaSnapshotListener(Source source) {
    const ListenOptions options = ListenOptions.all();

    return _getSnapshotsInternal(options).map((QuerySnapshot snapshot) {
      if (snapshot.metadata.isFromCache && source == Source.server) {
        throw FirestoreError(
            'Failed to get documents from server. (However, these documents may exist in the local cache. Run again '
            'without setting source to Source.server to retrieve the cached documents.)',
            FirestoreErrorCode.unavailable);
      } else {
        return snapshot;
      }
    }).first;
  }

  /// Return cached results first and then queries the server with resume token
  /// to ensure unnecessary reads are not made.
  Stream<QuerySnapshot> get snapshots {
    final ListenOptions options = _internalOptions(MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  /// Return cached results first and then queries the server with resume token
  /// to ensure unnecessary reads are not made.
  Stream<QuerySnapshot> getSnapshots([MetadataChanges changes]) {
    final ListenOptions options =
        _internalOptions(changes ?? MetadataChanges.exclude);
    return _getSnapshotsInternal(options);
  }

  Stream<QuerySnapshot> _getSnapshotsInternal(ListenOptions options) {
    return Stream<QueryStream>.fromFuture(
            firestore.client.listen(query, options))
        .flatMap((QueryStream it) => it)
        .map((ViewSnapshot snapshot) =>
            QuerySnapshot(this, snapshot, firestore));
  }

  /// Converts the  API options object to the internal options object.
  static ListenOptions _internalOptions(MetadataChanges metadataChanges) {
    return ListenOptions(
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
          firestore == other.firestore;

  @override
  int get hashCode => query.hashCode ^ firestore.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('firestore', firestore))
        .toString();
  }
}
