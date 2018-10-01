// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/index_range.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/nan_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/null_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/relation_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/index_cursor.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_documents_view.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_collection_index.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_collections.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/bool_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:meta/meta.dart';

/// An indexed implementation of [QueryEngine] which performs fairly efficient
/// queries.
///
/// * [IndexedQueryEngine] performs only one index lookup and picks an index to
/// use based on an estimate of a query's [filter] or [orderBy] selectivity.
///
/// * For queries with filters, [IndexedQueryEngine] distinguishes between two
/// categories of query filters: High selectivity filters are expected to return
/// a lower number of results from the index, while low selectivity filters only
/// marginally prune the search space.
///
/// * We determine the best filter to use based on the combination of two static
/// rules, which take into account both the operator and field values type.
///
/// * For operators, this assignment is as follows:
///
/// <ul>
/// <li>HIGH_SELECTIVITY: '='
/// <li>LOW_SELECTIVITY: '<', <=', '>=', '>'
/// </ul>
///
/// * For field value types, this assignment is:
///
/// <ul>
/// <li>HIGH_SELECTIVITY: [BlobValue], [DoubleValue], [GeoPointValue],
/// [NumberValue], [ReferenceValue], [StringValue], [TimestampValue],
/// [NullValue]
/// <li>LOW_SELECTIVITY: [ArrayValue], [ObjectValue], [BoolValue]
/// </ul>
///
/// * Note that we consider [NullValue] a high selectivity filter as we only
/// support equals comparisons against 'null' and expect most data to be
/// non-null.
///
/// * In the absence of filters, [IndexedQueryEngine] performs an index lookup
/// based on the first explicitly specified field in the [orderBy] clause.
/// Fields in an [orderBy] only match documents that contains these fields and
/// can hence optimize our lookups by providing some selectivity.
///
/// * A full collection scan is therefore only needed when no [filters] or
/// [orderBy] constraints are specified.
class IndexedQueryEngine implements QueryEngine {
  static const double highSelectivity = 1.0;
  static const double lowSelectivity = 0.5;

  // [ArrayValue] and [ObjectValue] are currently considered low cardinality
  // because we don't index them uniquely.
  static final List<Type> lowCardinalityTypes = <Type>[
    BoolValue,
    ArrayValue,
    ObjectValue
  ];

  final LocalDocumentsView localDocuments;
  final SQLiteCollectionIndex collectionIndex;

  const IndexedQueryEngine(this.localDocuments, this.collectionIndex);

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
      Query query) {
    return query.isDocumentQuery
        ? localDocuments.getDocumentsMatchingQuery(query)
        : performCollectionQuery(query);
  }

  /// Executes the query using both indexes and post-filtering.
  Future<ImmutableSortedMap<DocumentKey, Document>> performCollectionQuery(
      Query query) async {
    Assert.hardAssert(!query.isDocumentQuery,
        'matchesCollectionQuery called with document query.');

    final IndexRange indexRange = extractBestIndexRange(query);
    ImmutableSortedMap<DocumentKey, Document> filteredResults;

    if (indexRange != null) {
      filteredResults = await _performQueryUsingIndex(query, indexRange);
    } else {
      Assert.hardAssert(query.filters.isEmpty,
          'If there are any filters, we should be able to use an index.');
      // TODO: Call overlay.getCollectionDocuments(query.path) and filter the
      // results (there may still be startAt/endAt bounds that apply).
      filteredResults = await localDocuments.getDocumentsMatchingQuery(query);
    }

    return filteredResults;
  }

  /// Applies 'filter' to the index cursor, looks up the relevant documents from the local documents
  /// view and returns all matches.
  Future<ImmutableSortedMap<DocumentKey, Document>> _performQueryUsingIndex(
      Query query, IndexRange indexRange) async {
    ImmutableSortedMap<DocumentKey, Document> results =
        DocumentCollections.emptyDocumentMap();
    final IndexCursor cursor =
        collectionIndex.getCursor(query.path, indexRange);
    try {
      while (cursor.next) {
        final Document document =
            await localDocuments.getDocument(cursor.documentKey);
        if (query.matches(document)) {
          results = results.insert(cursor.documentKey, document);
        }
      }
    } finally {
      cursor.close();
    }

    return results;
  }

  /// Determines a single filter's selectivity by multiplying the implied
  /// selectivity of the filter operator and the type of its operand.
  ///
  /// Returns a number from 0.0 to 1.0 (inclusive), where higher numbers
  /// indicate higher selectivity
  static double _estimateFilterSelectivity(Filter filter) {
    if (filter is NullFilter) {
      return highSelectivity;
    } else if (filter is NaNFilter) {
      return highSelectivity;
    } else {
      Assert.hardAssert(filter is RelationFilter,
          'Filter type expected to be RelationFilter');
      final RelationFilter relationFilter = filter;

      final double operatorSelectivity =
          relationFilter.operator == FilterOperator.equal
              ? highSelectivity
              : lowSelectivity;
      final double typeSelectivity =
          lowCardinalityTypes.contains(relationFilter.value.runtimeType)
              ? lowSelectivity
              : highSelectivity;

      return typeSelectivity * operatorSelectivity;
    }
  }

  /// Returns an optimized [IndexRange] for this query. The [IndexRange] is
  /// computed based on the estimated selectivity of the query [filters] and
  /// [orderBy] constraints. If no [filters] or [orderBy] constraints are
  /// specified, it returns null.
  @visibleForTesting
  static IndexRange extractBestIndexRange(Query query) {
    // TODO: consider any startAt/endAt bounds on the query.
    double currentSelectivity = -1.0;

    if (query.filters.isNotEmpty) {
      Filter selectedFilter;
      for (Filter currentFilter in query.filters) {
        final double estimatedSelectivity =
            _estimateFilterSelectivity(currentFilter);
        if (estimatedSelectivity > currentSelectivity) {
          selectedFilter = currentFilter;
          currentSelectivity = estimatedSelectivity;
        }
      }
      Assert.hardAssert(selectedFilter != null, 'Filter should be defined');
      return _convertFilterToIndexRange(selectedFilter);
    } else {
      // If there are no filters, use the first orderBy constraint when performing the index lookup.
      // This index lookup will remove results that do not contain the field we use for ordering.
      final FieldPath orderPath = query.getOrderBy()[0].field;
      if (orderPath != FieldPath.keyPath) {
        return IndexRangeBuilder(fieldPath: query.getOrderBy()[0].field)
            .build();
      }
    }

    return null;
  }

  /// Creates an [IndexRange] that is guaranteed to capture all values that
  /// match the given filter. The determined [IndexRange] is likely
  /// overselective and requires post-filtering.
  static IndexRange _convertFilterToIndexRange(Filter filter) {
    final IndexRangeBuilder indexRange =
        IndexRangeBuilder(fieldPath: filter.field);
    if (filter is RelationFilter) {
      final RelationFilter relationFilter = filter;
      final FieldValue filterValue = relationFilter.value;
      switch (relationFilter.operator) {
        case FilterOperator.equal:
          indexRange.start = filterValue;
          indexRange.end = filterValue;
          break;
        case FilterOperator.lessThanOrEqual:
        case FilterOperator.lessThan:
          indexRange.end = filterValue;
          break;
        case FilterOperator.graterThan:
        case FilterOperator.graterThanOrEqual:
          indexRange.start = filterValue;
          break;
        default:
          // TODO: Add support for ARRAY_CONTAINS.
          throw Assert.fail('Unexpected operator in query filter');
      }
    } else if (filter is NaNFilter) {
      indexRange.start = DoubleValue.nan;
      indexRange.end = DoubleValue.nan;
    } else if (filter is NullFilter) {
      indexRange.start = NullValue.nullValue();
      indexRange.end = NullValue.nullValue();
    }
    return indexRange.build();
  }

  @override
  void handleDocumentChange(
      MaybeDocument oldDocument, MaybeDocument newDocument) {
    // TODO: Determine changed fields and make appropriate
    // addEntry() / removeEntry() on [SQLiteCollectionIndex].
    throw StateError('Not yet implemented.');
  }
}
