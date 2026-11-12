import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

const int _testTargetId = 1;

/// Upstream runs the same cases a second time through pipelines; the port only has the query form.
const bool shouldUsePipeline = false;

/// A [LocalDocumentsView] that checks whether a query is executed as a full collection scan or from an index / the
/// previous results plus the documents that changed since.
class _ExpectingLocalDocumentsView extends LocalDocumentsView {
  _ExpectingLocalDocumentsView({
    required super.remoteDocumentCache,
    required super.mutationQueue,
    required super.documentOverlayCache,
    required super.indexManager,
  });

  bool? expectFullCollectionScan;

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>> getDocumentsMatchingQuery(
      Query query, IndexOffset offset,
      [QueryContext? context]) {
    expect(offset == IndexOffset.none, expectFullCollectionScan,
        reason: 'Observed query execution mode did not match expectation');
    return super.getDocumentsMatchingQuery(query, offset, context);
  }
}

/// `TestUtil.docMap` of the Android SDK.
Map<DocumentKey, MaybeDocument?> docMap(List<Document> docs) =>
    <DocumentKey, MaybeDocument?>{for (final Document d in docs) d.key: d};

/// `IndexOffset.fromDocument` for a document that was added with its version as read time (as [addDocument] does).
IndexOffset offsetOf(Document document) => IndexOffset(
    document.version, document.key, FieldIndex.initialLargestBatchId);

/// Port of SQLiteQueryEngineTest of the Android SDK and of the OR / IN cases of QueryEngineTestCase that it inherits
/// (the older cases of QueryEngineTestCase are in query_engine_test.dart, on memory persistence).
void main() {
  late SQLitePersistence persistence;
  late RemoteDocumentCache remoteDocumentCache;
  late MutationQueue mutationQueue;
  late DocumentOverlayCache documentOverlayCache;
  late QueryCache queryCache;
  late IndexManager indexManager;
  late QueryEngine queryEngine;
  late _ExpectingLocalDocumentsView localDocuments;

  setUp(() async {
    persistence = await createSQLitePersistence(
        'firebase/firestore/local/sqlite_query_engine_test-${const Uuid().v4()}.db');
    indexManager = persistence.getIndexManager(User.unauthenticated);
    mutationQueue = persistence.getMutationQueue(User.unauthenticated);
    documentOverlayCache =
        persistence.getDocumentOverlayCache(User.unauthenticated);
    remoteDocumentCache = persistence.remoteDocumentCache;
    queryCache = persistence.queryCache;
    await indexManager.start();
    await mutationQueue.start();
    localDocuments = _ExpectingLocalDocumentsView(
      remoteDocumentCache: remoteDocumentCache,
      mutationQueue: mutationQueue,
      documentOverlayCache: documentOverlayCache,
      indexManager: indexManager,
    );
    queryEngine = DefaultQueryEngine()..setLocalDocumentsView(localDocuments);
  });

  tearDown(() => persistence.shutdown());

  /// Adds the provided documents to the remote document cache.
  Future<void> addDocument(List<Document> docs) {
    return persistence.runTransaction('addDocument', () async {
      for (final Document doc in docs) {
        await remoteDocumentCache.add(doc, doc.version);
      }
    });
  }

  /// Adds a mutation to the mutation queue.
  Future<void> addMutation(Mutation mutation) {
    return persistence.runTransaction('addMutation', () async {
      final MutationBatch batch = await mutationQueue.addMutationBatch(
          Timestamp.now(), <Mutation>[], <Mutation>[mutation]);
      await documentOverlayCache.saveOverlays(
          batch.batchId, <DocumentKey, Mutation>{mutation.key: mutation});
    });
  }

  Future<T> expectOptimizedCollectionScan<T>(Future<T> Function() c) async {
    try {
      localDocuments.expectFullCollectionScan = false;
      return await c();
    } finally {
      localDocuments.expectFullCollectionScan = null;
    }
  }

  Future<T> expectFullCollectionScan<T>(Future<T> Function() c) async {
    try {
      localDocuments.expectFullCollectionScan = true;
      return await c();
    } finally {
      localDocuments.expectFullCollectionScan = null;
    }
  }

  Future<DocumentSet> runQuery(
      Query query, SnapshotVersion lastLimboFreeSnapshotVersion) async {
    expect(localDocuments.expectFullCollectionScan, isNotNull,
        reason:
            'Encountered runQuery() call not wrapped in expectOptimizedCollectionScan()/expectFullCollectionScan()');
    final ImmutableSortedMap<DocumentKey, Document> docs =
        await queryEngine.getDocumentsMatchingQuery(
            query,
            lastLimboFreeSnapshotVersion,
            await queryCache.getMatchingKeysForTargetId(_testTargetId));
    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);
    return view.applyChanges(viewDocChanges).snapshot!.documents;
  }

  test('testCombinesIndexedWithNonIndexedResults', () async {
    final Document doc1 = doc('coll/a', 1, map(<dynamic>['foo', true]));
    final Document doc2 = doc('coll/b', 2, map(<dynamic>['foo', true]));
    final Document doc3 = doc('coll/c', 3, map(<dynamic>['foo', true]));
    // PORTING NOTE: version 3 upstream. A document that only exists as a local set has no version in the port.
    final Document doc4 = doc(
        'coll/d', 0, map(<dynamic>['foo', true]), DocumentState.localMutations);

    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['foo', SegmentKind.ascending]));

    await addDocument(<Document>[doc1]);
    await addDocument(<Document>[doc2]);
    await indexManager.updateIndexEntries(docMap(<Document>[doc1, doc2]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc2));

    await addDocument(<Document>[doc3]);
    await addMutation(setMutation('coll/d', map(<dynamic>['foo', true])));

    final Query queryWithFilter =
        query('coll').filter(filter('foo', '==', true));
    final DocumentSet results = await expectOptimizedCollectionScan(
        () => runQuery(queryWithFilter, SnapshotVersion.none));

    expect(results,
        docSet(queryWithFilter.comparator, <Document>[doc1, doc2, doc3, doc4]));
  });

  test('testUsesPartialIndexForLimitQueries', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['a', 1, 'b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 1, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 2, 'b', 3]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5]);

    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager
        .updateIndexEntries(docMap(<Document>[doc1, doc2, doc3, doc4, doc5]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc5));

    final Query qry = query('coll')
        .filter(filter('a', '==', 1))
        .filter(filter('b', '==', 1))
        .limitToFirst(3);
    final DocumentSet result = await expectOptimizedCollectionScan(
        () => runQuery(qry, SnapshotVersion.none));
    expect(result, docSet(qry.comparator, <Document>[doc2]));
  });

  test('testRefillsIndexedLimitQueries', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['a', 2]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 4]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4]);

    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager
        .updateIndexEntries(docMap(<Document>[doc1, doc2, doc3, doc4]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc4));

    await addMutation(patchMutation('coll/3', map(<dynamic>['a', 5])));

    final Query qry = query('coll').orderBy(orderBy('a')).limitToFirst(3);
    final DocumentSet result = await expectOptimizedCollectionScan(
        () => runQuery(qry, SnapshotVersion.none));
    expect(result, docSet(qry.comparator, <Document>[doc1, doc2, doc4]));
  });

  test('canPerformOrQueriesUsingIndexes', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['a', 2, 'b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1, 'b', 1]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.descending]));
    await indexManager
        .updateIndexEntries(docMap(<Document>[doc1, doc2, doc3, doc4, doc5]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc5));

    // Two equalities: a==1 || b==1.
    final Query query1 = query('coll').filter(
        orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(
        result1, docSet(query1.comparator, <Document>[doc1, doc2, doc4, doc5]));

    // with one inequality: a>2 || b==1.
    final Query query2 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '>', 2), filter('b', '==', 1)]));
    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc2, doc3, doc5]));

    // (a==1 && b==0) || (a==3 && b==2)
    final Query query3 = query('coll').filter(orFilters(<Filter>[
      andFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 0)]),
      andFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 2)])
    ]));
    final DocumentSet result3 = await expectOptimizedCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    expect(result3, docSet(query3.comparator, <Document>[doc1, doc3]));

    // a==1 && (b==0 || b==3).
    final Query query4 = query('coll').filter(andFilters(<Filter>[
      filter('a', '==', 1),
      orFilters(<Filter>[filter('b', '==', 0), filter('b', '==', 3)])
    ]));
    final DocumentSet result4 = await expectOptimizedCollectionScan(
        () => runQuery(query4, SnapshotVersion.none));
    expect(result4, docSet(query4.comparator, <Document>[doc1, doc4]));

    // (a==2 || b==2) && (a==3 || b==3)
    final Query query5 = query('coll').filter(andFilters(<Filter>[
      orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 2)]),
      orFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 3)])
    ]));
    final DocumentSet result5 = await expectOptimizedCollectionScan(
        () => runQuery(query5, SnapshotVersion.none));
    expect(result5, docSet(query5.comparator, <Document>[doc3]));

    // Test with limits (implicit order by ASC): (a==1) || (b > 0) LIMIT 2
    final Query query6 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '>', 0)]))
        .limitToFirst(2);
    final DocumentSet result6 = await expectOptimizedCollectionScan(
        () => runQuery(query6, SnapshotVersion.none));
    expect(result6, docSet(query6.comparator, <Document>[doc1, doc2]));

    // Test with limits (implicit order by DESC): (a==1) || (b > 0) LIMIT_TO_LAST 2
    final Query query7 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '>', 0)]))
        .limitToLast(2);
    final DocumentSet result7 = await expectOptimizedCollectionScan(
        () => runQuery(query7, SnapshotVersion.none));
    expect(result7, docSet(query7.comparator, <Document>[doc3, doc4]));

    // Test with limits (explicit order by ASC): (a==2) || (b == 1) ORDER BY a LIMIT 1
    final Query query8 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToFirst(1)
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result8 = await expectOptimizedCollectionScan(
        () => runQuery(query8, SnapshotVersion.none));
    expect(result8, docSet(query8.comparator, <Document>[doc5]));

    // Test with limits (explicit order by DESC): (a==2) || (b == 1) ORDER BY a LIMIT_TO_LAST 1
    final Query query9 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToLast(1)
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result9 = await expectOptimizedCollectionScan(
        () => runQuery(query9, SnapshotVersion.none));
    expect(result9, docSet(query9.comparator, <Document>[doc2]));

    // Test with limits without orderBy (the __name__ ordering is the tie breaker).
    final Query query10 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToFirst(1);
    final DocumentSet result10 = await expectOptimizedCollectionScan(
        () => runQuery(query10, SnapshotVersion.none));
    expect(result10, docSet(query10.comparator, <Document>[doc2]));
  });

  test('orQueryWithInAndNotInUsingIndexes', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.descending]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    // Two equalities: a==1 || b==1.
    final Query query1 = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 2),
      filter('b', 'in', <Object?>[2, 3])
    ]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    // a==2 || (b != 2 && b != 3)
    // Has implicit 'orderBy b'
    final Query query2 = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 2),
      filter('b', 'not-in', <Object?>[2, 3])
    ]));
    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc1, doc2]));
  });

  test('orQueryWithArrayMembershipUsingIndexes', () async {
    final Document doc1 = doc(
        'coll/1',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[0]
        ]));
    final Document doc2 = doc(
        'coll/2',
        1,
        map(<dynamic>[
          'b',
          <Object?>[1]
        ]));
    final Document doc3 = doc(
        'coll/3',
        1,
        map(<dynamic>[
          'a',
          3,
          'b',
          <Object?>[2, 7]
        ]));
    final Document doc4 = doc(
        'coll/4',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[3, 7]
        ]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.contains]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    final Query query1 = query('coll').filter(orFilters(
        <Filter>[filter('a', '==', 2), filter('b', 'array-contains', 7)]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    final Query query2 = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 2),
      filter('b', 'array-contains-any', <Object?>[0, 3])
    ]));
    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc1, doc4, doc6]));
  });

  test('queryWithMultipleInsOnTheSameField', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.descending]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    // a IN [1,2,3] && a IN [0,1,4] should result in 'a==1'.
    final Query query1 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[1, 2, 3]),
      filter('a', 'in', <Object?>[0, 1, 4])
    ]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc4, doc5]));

    // a IN [2,3] && a IN [0,1,4] is never true and so the result should be an empty set.
    final Query query2 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('a', 'in', <Object?>[0, 1, 4])
    ]));

    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[]));

    // a IN [0,3] || a IN [0,2] should union them (similar to: a IN [0,2,3]).
    final Query query3 = query('coll').filter(orFilters(<Filter>[
      filter('a', 'in', <Object?>[0, 3]),
      filter('a', 'in', <Object?>[0, 2])
    ]));

    final DocumentSet result3 = await expectOptimizedCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    expect(result3, docSet(query3.comparator, <Document>[doc3, doc6]));

    // Nested composite filter: (a IN [0,1,2,3] && (a IN [0,2] || (b>1 && a IN [1,3]))
    final Query query4 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[0, 1, 2, 3]),
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[0, 2]),
        andFilters(<Filter>[
          filter('b', '>=', 1),
          filter('a', 'in', <Object?>[1, 3])
        ])
      ])
    ]));

    final DocumentSet result4 = await expectOptimizedCollectionScan(
        () => runQuery(query4, SnapshotVersion.none));
    expect(result4, docSet(query4.comparator, <Document>[doc3, doc4]));
  });

  test('queryWithMultipleInsOnDifferentFields', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.descending]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    final Query query1 = query('coll').filter(orFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('b', 'in', <Object?>[0, 2])
    ]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc3, doc6]));

    final Query query2 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('b', 'in', <Object?>[0, 2])
    ]));

    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc3]));

    // Nested composite filter: (b in [0,3] && (b IN [1] || (b in [2,3] && a IN [1,3]))
    final Query query3 = query('coll').filter(andFilters(<Filter>[
      filter('b', 'in', <Object?>[0, 3]),
      orFilters(<Filter>[
        filter('b', 'in', <Object?>[1]),
        andFilters(<Filter>[
          filter('b', 'in', <Object?>[2, 3]),
          filter('a', 'in', <Object?>[1, 3])
        ])
      ])
    ]));

    final DocumentSet result3 = await expectOptimizedCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    expect(result3, docSet(query3.comparator, <Document>[doc4]));
  });

  test('queryInWithArrayContainsAny', () async {
    final Document doc1 = doc(
        'coll/1',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[0]
        ]));
    final Document doc2 = doc(
        'coll/2',
        1,
        map(<dynamic>[
          'b',
          <Object?>[1]
        ]));
    final Document doc3 = doc(
        'coll/3',
        1,
        map(<dynamic>[
          'a',
          3,
          'b',
          <Object?>[2, 7],
          'c',
          10
        ]));
    final Document doc4 = doc(
        'coll/4',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[3, 7]
        ]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2, 'c', 20]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.contains]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    final Query query1 = query('coll').filter(orFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('b', 'array-contains-any', <Object?>[0, 7])
    ]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(
        result1, docSet(query1.comparator, <Document>[doc1, doc3, doc4, doc6]));

    final Query query2 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('b', 'array-contains-any', <Object?>[0, 7])
    ]));

    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc3]));

    final Query query3 = query('coll').filter(orFilters(<Filter>[
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('c', '==', 10)
      ]),
      filter('b', 'array-contains-any', <Object?>[0, 7])
    ]));
    final DocumentSet result3 = await expectOptimizedCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    expect(result3, docSet(query3.comparator, <Document>[doc1, doc3, doc4]));

    final Query query4 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      orFilters(<Filter>[
        filter('b', 'array-contains-any', <Object?>[0, 7]),
        filter('c', '==', 20)
      ])
    ]));
    final DocumentSet result4 = await expectOptimizedCollectionScan(
        () => runQuery(query4, SnapshotVersion.none));
    expect(result4, docSet(query4.comparator, <Document>[doc3, doc6]));
  });

  test('queryInWithArrayContains', () async {
    final Document doc1 = doc(
        'coll/1',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[0]
        ]));
    final Document doc2 = doc(
        'coll/2',
        1,
        map(<dynamic>[
          'b',
          <Object?>[1]
        ]));
    final Document doc3 = doc(
        'coll/3',
        1,
        map(<dynamic>[
          'a',
          3,
          'b',
          <Object?>[2, 7],
          'c',
          10
        ]));
    final Document doc4 = doc(
        'coll/4',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[3, 7]
        ]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2, 'c', 20]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.contains]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    final Query query1 = query('coll').filter(orFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('b', 'array-contains', 3)
    ]));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    final Query query2 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      filter('b', 'array-contains', 7)
    ]));

    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc3]));

    final Query query3 = query('coll').filter(orFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      andFilters(
          <Filter>[filter('b', 'array-contains', 3), filter('a', '==', 1)])
    ]));
    final DocumentSet result3 = await expectOptimizedCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    expect(result3, docSet(query3.comparator, <Document>[doc3, doc4, doc6]));

    final Query query4 = query('coll').filter(andFilters(<Filter>[
      filter('a', 'in', <Object?>[2, 3]),
      orFilters(
          <Filter>[filter('b', 'array-contains', 7), filter('a', '==', 1)])
    ]));
    final DocumentSet result4 = await expectOptimizedCollectionScan(
        () => runQuery(query4, SnapshotVersion.none));
    expect(result4, docSet(query4.comparator, <Document>[doc3]));
  });

  test('orderByEquality', () async {
    final Document doc1 = doc(
        'coll/1',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[0]
        ]));
    final Document doc2 = doc(
        'coll/2',
        1,
        map(<dynamic>[
          'b',
          <Object?>[1]
        ]));
    final Document doc3 = doc(
        'coll/3',
        1,
        map(<dynamic>[
          'a',
          3,
          'b',
          <Object?>[2, 7],
          'c',
          10
        ]));
    final Document doc4 = doc(
        'coll/4',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[3, 7]
        ]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2, 'c', 20]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['a', SegmentKind.descending]));
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['b', SegmentKind.contains]));
    await indexManager.updateIndexEntries(
        docMap(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]));
    await indexManager.updateCollectionGroup('coll', offsetOf(doc6));

    final Query query1 =
        query('coll').filter(filter('a', '==', 1)).orderBy(orderBy('a'));
    final DocumentSet result1 = await expectOptimizedCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc4, doc5]));

    final Query query2 = query('coll')
        .filter(filter('a', 'in', <Object?>[2, 3]))
        .orderBy(orderBy('a'));
    final DocumentSet result2 = await expectOptimizedCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc6, doc3]));
  });

  test('canPerformOrQueriesUsingFullCollectionScan', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['a', 2, 'b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1, 'b', 1]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5]);

    // Two equalities: a==1 || b==1.
    final Query query1 = query('coll').filter(
        orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]));
    final DocumentSet result1 = await expectFullCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(
        result1, docSet(query1.comparator, <Document>[doc1, doc2, doc4, doc5]));

    // with one inequality: a>2 || b==1.
    final Query query2 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '>', 2), filter('b', '==', 1)]));
    final DocumentSet result2 = await expectFullCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc2, doc3, doc5]));

    // (a==1 && b==0) || (a==3 && b==2)
    final Query query3 = query('coll').filter(orFilters(<Filter>[
      andFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 0)]),
      andFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 2)])
    ]));
    final DocumentSet result3 = await expectFullCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    expect(result3, docSet(query3.comparator, <Document>[doc1, doc3]));

    // a==1 && (b==0 || b==3).
    final Query query4 = query('coll').filter(andFilters(<Filter>[
      filter('a', '==', 1),
      orFilters(<Filter>[filter('b', '==', 0), filter('b', '==', 3)])
    ]));
    final DocumentSet result4 = await expectFullCollectionScan(
        () => runQuery(query4, SnapshotVersion.none));
    expect(result4, docSet(query4.comparator, <Document>[doc1, doc4]));

    // (a==2 || b==2) && (a==3 || b==3)
    final Query query5 = query('coll').filter(andFilters(<Filter>[
      orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 2)]),
      orFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 3)])
    ]));
    final DocumentSet result5 = await expectFullCollectionScan(
        () => runQuery(query5, SnapshotVersion.none));
    expect(result5, docSet(query5.comparator, <Document>[doc3]));

    // Test with limits (implicit order by ASC): (a==1) || (b > 0) LIMIT 2
    final Query query6 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '>', 0)]))
        .limitToFirst(2);
    final DocumentSet result6 = await expectFullCollectionScan(
        () => runQuery(query6, SnapshotVersion.none));
    expect(result6, docSet(query6.comparator, <Document>[doc1, doc2]));

    // Test with limits (order by b ASC): (a==1) || (b > 0) LIMIT_TO_LAST 2
    final Query query7 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '>', 0)]))
        .orderBy(orderBy('b', 'asc'))
        .limitToLast(2);
    final DocumentSet result7 = await expectFullCollectionScan(
        () => runQuery(query7, SnapshotVersion.none));
    expect(result7, docSet(query7.comparator, <Document>[doc3, doc4]));

    // Test with limits (explicit order by ASC): (a==2) || (b == 1) ORDER BY a LIMIT 1
    final Query query8 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToFirst(1)
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result8 = await expectFullCollectionScan(
        () => runQuery(query8, SnapshotVersion.none));
    expect(result8, docSet(query8.comparator, <Document>[doc5]));

    // Test with limits (explicit order by DESC): (a==2) || (b == 1) ORDER BY a LIMIT_TO_LAST 1
    final Query query9 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToLast(1)
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result9 = await expectFullCollectionScan(
        () => runQuery(query9, SnapshotVersion.none));
    expect(result9, docSet(query9.comparator, <Document>[doc2]));

    // Test with limits without orderBy (the __name__ ordering is the tie breaker).
    final Query query10 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToFirst(1);
    final DocumentSet result10 = await expectFullCollectionScan(
        () => runQuery(query10, SnapshotVersion.none));
    expect(result10, docSet(query10.comparator, <Document>[doc2]));
  });

  test('orQueryDoesNotIncludeDocumentsWithMissingFields', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    // Query: a==1 || b==1 order by a.
    // doc2 should not be included because it's missing the field 'a', and we have 'orderBy a'.
    final Query query1 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]))
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result1 = await expectFullCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc4, doc5]));

    // Query: a==1 || b==1 order by b.
    // doc5 should not be included because it's missing the field 'b', and we have 'orderBy b'.
    final Query query2 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]))
        .orderBy(orderBy('b', 'asc'));
    final DocumentSet result2 = await expectFullCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc1, doc2, doc4]));

    // Query: a>2 || b==1.
    final Query query3 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '>', 2), filter('b', '==', 1)]));
    final DocumentSet result3 = await expectFullCollectionScan(
        () => runQuery(query3, SnapshotVersion.none));
    if (shouldUsePipeline) {
      expect(result3, docSet(query3.comparator, <Document>[doc2, doc3]));
    } else {
      // This qry has an implicit 'order by a' with standard edition.
      // doc2 should not be included because it's missing the field 'a'.
      expect(result3, docSet(query3.comparator, <Document>[doc3]));
    }

    // Query: a>1 || b==1 order by a order by b.
    // doc6 should not be included because it's missing the field 'b'.
    // doc2 should not be included because it's missing the field 'a'.
    final Query query4 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '>', 1), filter('b', '==', 1)]))
        .orderBy(orderBy('a', 'asc'))
        .orderBy(orderBy('b', 'asc'));
    final DocumentSet result4 = await expectFullCollectionScan(
        () => runQuery(query4, SnapshotVersion.none));
    expect(result4, docSet(query4.comparator, <Document>[doc3]));

    // Query: a==1 || b==1
    // There's no explicit nor implicit orderBy. Documents with missing 'a' or missing 'b' should be
    // allowed if the document matches at least one disjunction term.
    final Query query5 = query('coll').filter(
        orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]));
    final DocumentSet result5 = await expectFullCollectionScan(
        () => runQuery(query5, SnapshotVersion.none));
    expect(
        result5, docSet(query5.comparator, <Document>[doc1, doc2, doc4, doc5]));
  });

  test('orQueryWithInAndNotIn', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 2),
      filter('b', 'in', <Object?>[2, 3])
    ]));
    final DocumentSet result1 = await expectFullCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    // a==2 || (b != 2 && b != 3)
    final Query query2 = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 2),
      filter('b', 'not-in', <Object?>[2, 3])
    ]));
    final DocumentSet result2 = await expectFullCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    if (shouldUsePipeline) {
      // Has implicit 'orderBy b' but no 'b exists' when converting to pipelines
      expect(result2, docSet(query2.comparator, <Document>[doc6, doc1, doc2]));
    } else {
      // Has implicit 'orderBy b' and 'b exists' with standard edition
      expect(result2, docSet(query2.comparator, <Document>[doc1, doc2]));
    }
  });

  test('orQueryWithArrayMembership', () async {
    final Document doc1 = doc(
        'coll/1',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[0]
        ]));
    final Document doc2 = doc(
        'coll/2',
        1,
        map(<dynamic>[
          'b',
          <Object?>[1]
        ]));
    final Document doc3 = doc(
        'coll/3',
        1,
        map(<dynamic>[
          'a',
          3,
          'b',
          <Object?>[2, 7]
        ]));
    final Document doc4 = doc(
        'coll/4',
        1,
        map(<dynamic>[
          'a',
          1,
          'b',
          <Object?>[3, 7]
        ]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(orFilters(
        <Filter>[filter('a', '==', 2), filter('b', 'array-contains', 7)]));
    final DocumentSet result1 = await expectFullCollectionScan(
        () => runQuery(query1, SnapshotVersion.none));
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    final Query query2 = query('coll').filter(orFilters(<Filter>[
      filter('a', '==', 2),
      filter('b', 'array-contains-any', <Object?>[0, 3])
    ]));
    final DocumentSet result2 = await expectFullCollectionScan(
        () => runQuery(query2, SnapshotVersion.none));
    expect(result2, docSet(query2.comparator, <Document>[doc1, doc4, doc6]));
  });

  // Not upstream: the cases below pin where the port deliberately reads more than upstream does, see
  // LocalDocumentsView._getDocumentsMatchingCollectionQuery.
  group('documents read after the index offset', () {
    Future<void> backfill() async {
      await IndexBackfiller.forTesting(
          persistence, () => indexManager, () => localDocuments).backfill();
    }

    test('keep the overlay of a batch that was already indexed', () async {
      await indexManager.addFieldIndex(fieldIndex('coll',
          fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
      await addDocument(<Document>[
        doc('coll/doc', 1, map(<dynamic>['a', 1, 'x', 0]))
      ]);
      await addMutation(patchMutation('coll/doc', map(<dynamic>['x', 1])));
      await backfill();
      expect(indexManager.getMinOffset('coll').largestBatchId,
          greaterThanOrEqualTo(0));

      // The backend sends a new version; the patch is still pending.
      await addDocument(<Document>[
        doc('coll/doc', 5, map(<dynamic>['a', 2, 'x', 0]))
      ]);

      final Query q = query('coll').filter(filter('a', '==', 2));
      final DocumentSet result = await expectOptimizedCollectionScan(
          () => runQuery(q, SnapshotVersion.none));
      expect(result.length, 1);
      final Document found = result.first;
      expect(found.key, key('coll/doc'));
      expect(found.getField(field('x'))!.value, 1);
      expect(found.hasLocalMutations, isTrue);
    });

    test(
        'match the query through the overlay of a batch that was already indexed',
        () async {
      // The index only covers `a`: it is a partial index for the query below.
      await indexManager.addFieldIndex(fieldIndex('coll',
          fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
      await addDocument(<Document>[
        doc('coll/doc', 1, map(<dynamic>['a', 1, 'x', 0]))
      ]);
      await addMutation(patchMutation('coll/doc', map(<dynamic>['x', 1])));
      await backfill();

      // The new remote version alone does not match `x == 1`; with the pending patch it does.
      await addDocument(<Document>[
        doc('coll/doc', 5, map(<dynamic>['a', 2, 'x', 0]))
      ]);

      final Query q = query('coll')
          .filter(filter('a', '==', 2))
          .filter(filter('x', '==', 1));
      final DocumentSet result = await expectOptimizedCollectionScan(
          () => runQuery(q, SnapshotVersion.none));
      expect(result.map((Document d) => d.key).toList(),
          <DocumentKey>[key('coll/doc')]);
    });

    test('stop matching the query through such an overlay', () async {
      await indexManager.addFieldIndex(fieldIndex('coll',
          fieldsAndKinds: <Object>['a', SegmentKind.ascending]));
      await addDocument(<Document>[
        doc('coll/doc', 1, map(<dynamic>['a', 1, 'x', 0]))
      ]);
      await addMutation(patchMutation('coll/doc', map(<dynamic>['x', 1])));
      await backfill();

      // The new remote version matches `x == 0`, the local view (x is patched to 1) does not.
      await addDocument(<Document>[
        doc('coll/doc', 5, map(<dynamic>['a', 2, 'x', 0]))
      ]);

      final Query q = query('coll')
          .filter(filter('a', '==', 2))
          .filter(filter('x', '==', 0));
      final DocumentSet result = await expectOptimizedCollectionScan(
          () => runQuery(q, SnapshotVersion.none));
      expect(result, isEmpty);
    });
  });
}
