// Copyright 2019 Google LLC
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

// Port of the Android SDK's QueryEngineTestCase, which MemoryQueryEngineTest and SQLiteQueryEngineTest extend, plus
// the "query with ins and not-ins on the same field" case of the JS SDK's query_engine.test.ts (genericQueryEngineTest
// without client side indexing).

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

const int _testTargetId = 1;

/// Upstream runs the same cases a second time through pipelines; the port only has the query form.
const bool _shouldUsePipeline = false;

final Document _matchingDocA = doc(
  'coll/a',
  1,
  map(<dynamic>['matches', true, 'order', 1]),
  DocumentState.synced,
);
final Document _nonMatchingDocA = doc(
  'coll/a',
  1,
  map(<dynamic>['matches', false, 'order', 1]),
  DocumentState.synced,
);
final Document _pendingMatchingDocA = doc(
  'coll/a',
  1,
  map(<dynamic>['matches', true, 'order', 1]),
  DocumentState.localMutations,
);
final Document _pendingNonMatchingDocA = doc(
  'coll/a',
  1,
  map(<dynamic>['matches', false, 'order', 1]),
  DocumentState.localMutations,
);
final Document _updatedDocA = doc(
  'coll/a',
  11,
  map(<dynamic>['matches', true, 'order', 1]),
  DocumentState.synced,
);
final Document _matchingDocB = doc(
  'coll/b',
  1,
  map(<dynamic>['matches', true, 'order', 2]),
  DocumentState.synced,
);
final Document _updatedMatchingDocB = doc(
  'coll/b',
  11,
  map(<dynamic>['matches', true, 'order', 2]),
  DocumentState.synced,
);

final PatchMutation _docAEmptyPatch = PatchMutation(
  key('coll/a'),
  ObjectValue.empty,
  FieldMask.empty,
  Precondition.none,
);

final SnapshotVersion _lastLimboFreeSnapshot = version(10);
const SnapshotVersion _missingLastLimboFreeSnapshot = SnapshotVersion.none;

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
    Query query,
    IndexOffset offset, [
    QueryContext? context,
  ]) {
    expect(
      offset == IndexOffset.none,
      expectFullCollectionScan,
      reason: 'Observed query execution mode did not match expectation',
    );
    return super.getDocumentsMatchingQuery(query, offset, context);
  }
}

/// Registers the cases of QueryEngineTestCase against the persistence that [createPersistence] returns (started).
///
/// [overriddenTests] are the names of the cases that the caller registers itself in another form, as the subclasses
/// of QueryEngineTestCase override them upstream (SQLiteQueryEngineTest runs the IN cases against field indexes).
void queryEngineTestCase(
  Future<Persistence> Function() createPersistence, {
  Set<String> overriddenTests = const <String>{},
}) {
  late Persistence persistence;
  late RemoteDocumentCache remoteDocumentCache;
  late MutationQueue mutationQueue;
  late DocumentOverlayCache documentOverlayCache;
  late QueryCache queryCache;
  late IndexManager indexManager;
  late QueryEngine queryEngine;
  late _ExpectingLocalDocumentsView localDocuments;

  setUp(() async {
    persistence = await createPersistence();
    indexManager = persistence.getIndexManager(User.unauthenticated);
    mutationQueue = persistence.getMutationQueue(User.unauthenticated);
    documentOverlayCache = persistence.getDocumentOverlayCache(
      User.unauthenticated,
    );
    remoteDocumentCache = persistence.remoteDocumentCache;
    queryCache = persistence.queryCache;

    await indexManager.start();
    await mutationQueue.start();

    remoteDocumentCache.indexManager = indexManager;

    localDocuments = _ExpectingLocalDocumentsView(
      remoteDocumentCache: remoteDocumentCache,
      mutationQueue: mutationQueue,
      documentOverlayCache: documentOverlayCache,
      indexManager: indexManager,
    );
    queryEngine = DefaultQueryEngine()..setLocalDocumentsView(localDocuments);
  });

  tearDown(() => persistence.shutdown());

  void test(String name, Future<void> Function() body) {
    if (!overriddenTests.contains(name)) {
      _test(name, body);
    }
  }

  /// Adds the provided documents to the query target mapping.
  Future<void> persistQueryMapping(List<DocumentKey> documentKeys) {
    return persistence.runTransaction('persistQueryMapping', () async {
      await queryCache.addMatchingKeys(keySet(documentKeys), _testTargetId);
    });
  }

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
        Timestamp.now(),
        <Mutation>[],
        <Mutation>[mutation],
      );
      await documentOverlayCache.saveOverlays(
        batch.batchId,
        <DocumentKey, Mutation>{mutation.key: mutation},
      );
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
    Query query,
    SnapshotVersion lastLimboFreeSnapshotVersion,
  ) async {
    expect(
      localDocuments.expectFullCollectionScan,
      isNotNull,
      reason:
          'Encountered runQuery() call not wrapped in expectOptimizedCollectionScan()/expectFullCollectionScan()',
    );
    final ImmutableSortedMap<DocumentKey, Document> docs = await queryEngine
        .getDocumentsMatchingQuery(
          query,
          lastLimboFreeSnapshotVersion,
          await queryCache.getMatchingKeysForTargetId(_testTargetId),
        );
    final View view = View(query, DocumentKey.emptyKeySet);
    final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);
    return view.applyChanges(viewDocChanges).snapshot!.documents;
  }

  test('usesTargetMappingForInitialView', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(<DocumentKey>[
      _matchingDocA.key,
      _matchingDocB.key,
    ]);

    final DocumentSet docs = await expectOptimizedCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(
      docs,
      docSet(q.comparator, <Document>[_matchingDocA, _matchingDocB]),
    );
  });

  test('filtersNonMatchingInitialResults', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(<DocumentKey>[
      _matchingDocA.key,
      _matchingDocB.key,
    ]);

    // Add a mutated document that is not yet part of query's set of remote keys.
    await addDocument(<Document>[_pendingNonMatchingDocA]);

    final DocumentSet docs = await expectOptimizedCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test('includesChangesSinceInitialResults', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(<DocumentKey>[
      _matchingDocA.key,
      _matchingDocB.key,
    ]);

    DocumentSet docs = await expectOptimizedCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(
      docs,
      docSet(q.comparator, <Document>[_matchingDocA, _matchingDocB]),
    );

    await addDocument(<Document>[_updatedMatchingDocB]);

    docs = await expectOptimizedCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(
      docs,
      docSet(q.comparator, <Document>[_matchingDocA, _updatedMatchingDocB]),
    );
  });

  test('doesNotUseInitialResultsWithoutLimboFreeSnapshotVersion', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));
    final DocumentSet docs = await expectFullCollectionScan(
      () => runQuery(q, _missingLastLimboFreeSnapshot),
    );
    expect(docs, docSet(q.comparator));
  });

  test('doesNotUseInitialResultsForUnfilteredCollectionQuery', () async {
    final Query q = query('coll');
    final DocumentSet docs = await expectFullCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(docs, docSet(q.comparator));
  });

  test('doesNotUseInitialResultsForLimitQueryWithDocumentRemoval', () async {
    final Query q = query(
      'coll',
    ).filter(filter('matches', '==', true)).limitToFirst(1);

    // While the backend would never add DocA to the set of remote keys, this allows us to easily simulate what would
    // happen when a document no longer matches due to an out-of-band update.
    await addDocument(<Document>[_nonMatchingDocA]);
    await persistQueryMapping(<DocumentKey>[_nonMatchingDocA.key]);

    await addDocument(<Document>[_matchingDocB]);

    final DocumentSet docs = await expectFullCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test(
    'doesNotUseInitialResultsForLimitToLastQueryWithDocumentRemoval',
    () async {
      final Query q = query('coll')
          .filter(filter('matches', '==', true))
          .orderBy(orderBy('order', 'desc'))
          .limitToLast(1);

      // While the backend would never add DocA to the set of remote keys, this allows us to easily simulate what would
      // happen when a document no longer matches due to an out-of-band update.
      await addDocument(<Document>[_nonMatchingDocA]);
      await persistQueryMapping(<DocumentKey>[_nonMatchingDocA.key]);

      await addDocument(<Document>[_matchingDocB]);

      final DocumentSet docs = await expectFullCollectionScan(
        () => runQuery(q, _lastLimboFreeSnapshot),
      );
      expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
    },
  );

  test(
    'doesNotUseInitialResultsForLimitQueryWhenLastDocumentHasPendingWrite',
    () async {
      final Query q = query('coll')
          .filter(filter('matches', '==', true))
          .orderBy(orderBy('order', 'desc'))
          .limitToFirst(1);

      // Add a query mapping for a document that matches, but that sorts below another document due to a pending write.
      await addDocument(<Document>[_pendingMatchingDocA]);
      await addMutation(_docAEmptyPatch);
      await persistQueryMapping(<DocumentKey>[_pendingMatchingDocA.key]);

      await addDocument(<Document>[_matchingDocB]);

      final DocumentSet docs = await expectFullCollectionScan(
        () => runQuery(q, _lastLimboFreeSnapshot),
      );
      expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
    },
  );

  test(
    'doesNotUseInitialResultsForLimitToLastQueryWhenLastDocumentHasPendingWrite',
    () async {
      final Query q = query('coll')
          .filter(filter('matches', '==', true))
          .orderBy(orderBy('order', 'asc'))
          .limitToLast(1);

      // Add a query mapping for a document that matches, but that sorts below another document due to a pending write.
      await addDocument(<Document>[_pendingMatchingDocA]);
      await addMutation(_docAEmptyPatch);
      await persistQueryMapping(<DocumentKey>[_pendingMatchingDocA.key]);

      await addDocument(<Document>[_matchingDocB]);

      final DocumentSet docs = await expectFullCollectionScan(
        () => runQuery(q, _lastLimboFreeSnapshot),
      );
      expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
    },
  );

  test(
    'doesNotUseInitialResultsForLimitQueryWhenLastDocumentHasBeenUpdatedOutOfBand',
    () async {
      final Query q = query('coll')
          .filter(filter('matches', '==', true))
          .orderBy(orderBy('order', 'desc'))
          .limitToFirst(1);

      // Add a query mapping for a document that matches, but that sorts below another document based due to an update
      // that the SDK received after the query's snapshot was persisted.
      await addDocument(<Document>[_updatedDocA]);
      await persistQueryMapping(<DocumentKey>[_updatedDocA.key]);

      await addDocument(<Document>[_matchingDocB]);

      final DocumentSet docs = await expectFullCollectionScan(
        () => runQuery(q, _lastLimboFreeSnapshot),
      );
      expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
    },
  );

  test(
    'doesNotUseInitialResultsForLimitToLastQueryWhenFirstDocumentHasBeenUpdatedOutOfBand',
    () async {
      final Query q = query('coll')
          .filter(filter('matches', '==', true))
          .orderBy(orderBy('order', 'asc'))
          .limitToLast(1);

      // Add a query mapping for a document that matches, but that sorts below another document based due to an update
      // that the SDK received after the query's snapshot was persisted.
      await addDocument(<Document>[_updatedDocA]);
      await persistQueryMapping(<DocumentKey>[_updatedDocA.key]);

      await addDocument(<Document>[_matchingDocB]);

      final DocumentSet docs = await expectFullCollectionScan(
        () => runQuery(q, _lastLimboFreeSnapshot),
      );
      expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
    },
  );

  test('limitQueriesUseInitialResultsIfLastDocumentInLimitIsUnchanged', () async {
    final Query q = query('coll').orderBy(orderBy('order')).limitToFirst(2);

    await addDocument(<Document>[
      doc('coll/a', 1, map(<dynamic>['order', 1])),
    ]);
    await addDocument(<Document>[
      doc('coll/b', 1, map(<dynamic>['order', 3])),
    ]);
    await persistQueryMapping(<DocumentKey>[key('coll/a'), key('coll/b')]);

    // Update "coll/a" but make sure it still sorts before "coll/b"
    await addDocument(<Document>[
      doc('coll/a', 1, map(<dynamic>['order', 2])),
    ]);
    await addMutation(_docAEmptyPatch);

    // Since the last document in the limit didn't change (and hence we know that all documents written prior to query
    // execution still sort after "coll/b"), we should use an Index-Free query.
    final DocumentSet docs = await expectOptimizedCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(
      docs,
      docSet(q.comparator, <Document>[
        // `doc("coll/a", 1, ...).setHasLocalMutations()` upstream, which also resets the version to none.
        doc(
          'coll/a',
          0,
          map(<dynamic>['order', 2]),
          DocumentState.localMutations,
        ),
        doc('coll/b', 1, map(<dynamic>['order', 3])),
      ]),
    );
  });

  test('doesNotIncludeDocumentsDeletedByMutation', () async {
    final Query q = query('coll');

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(<DocumentKey>[
      _matchingDocA.key,
      _matchingDocB.key,
    ]);

    // Add an unacknowledged mutation
    await addMutation(deleteMutation('coll/b'));

    final DocumentSet docs = await expectFullCollectionScan(
      () => runQuery(q, _lastLimboFreeSnapshot),
    );
    expect(docs, docSet(q.comparator, <Document>[_matchingDocA]));
  });

  test('canPerformOrQueriesUsingFullCollectionScan', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['a', 2, 'b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1, 'b', 1]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5]);

    // Two equalities: a==1 || b==1.
    final Query query1 = query(
      'coll',
    ).filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]));
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, SnapshotVersion.none),
    );
    expect(
      result1,
      docSet(query1.comparator, <Document>[doc1, doc2, doc4, doc5]),
    );

    // with one inequality: a>2 || b==1.
    final Query query2 = query(
      'coll',
    ).filter(orFilters(<Filter>[filter('a', '>', 2), filter('b', '==', 1)]));
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, SnapshotVersion.none),
    );
    expect(result2, docSet(query2.comparator, <Document>[doc2, doc3, doc5]));

    // (a==1 && b==0) || (a==3 && b==2)
    final Query query3 = query('coll').filter(
      orFilters(<Filter>[
        andFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 0)]),
        andFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 2)]),
      ]),
    );
    final DocumentSet result3 = await expectFullCollectionScan(
      () => runQuery(query3, SnapshotVersion.none),
    );
    expect(result3, docSet(query3.comparator, <Document>[doc1, doc3]));

    // a==1 && (b==0 || b==3).
    final Query query4 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', '==', 1),
        orFilters(<Filter>[filter('b', '==', 0), filter('b', '==', 3)]),
      ]),
    );
    final DocumentSet result4 = await expectFullCollectionScan(
      () => runQuery(query4, SnapshotVersion.none),
    );
    expect(result4, docSet(query4.comparator, <Document>[doc1, doc4]));

    // (a==2 || b==2) && (a==3 || b==3)
    final Query query5 = query('coll').filter(
      andFilters(<Filter>[
        orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 2)]),
        orFilters(<Filter>[filter('a', '==', 3), filter('b', '==', 3)]),
      ]),
    );
    final DocumentSet result5 = await expectFullCollectionScan(
      () => runQuery(query5, SnapshotVersion.none),
    );
    expect(result5, docSet(query5.comparator, <Document>[doc3]));

    // Test with limits (implicit order by ASC): (a==1) || (b > 0) LIMIT 2
    final Query query6 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '>', 0)]))
        .limitToFirst(2);
    final DocumentSet result6 = await expectFullCollectionScan(
      () => runQuery(query6, SnapshotVersion.none),
    );
    expect(result6, docSet(query6.comparator, <Document>[doc1, doc2]));

    // Test with limits (order by b ASC): (a==1) || (b > 0) LIMIT_TO_LAST 2
    final Query query7 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '>', 0)]))
        .orderBy(orderBy('b', 'asc'))
        .limitToLast(2);
    final DocumentSet result7 = await expectFullCollectionScan(
      () => runQuery(query7, SnapshotVersion.none),
    );
    expect(result7, docSet(query7.comparator, <Document>[doc3, doc4]));

    // Test with limits (explicit order by ASC): (a==2) || (b == 1) ORDER BY a LIMIT 1
    final Query query8 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToFirst(1)
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result8 = await expectFullCollectionScan(
      () => runQuery(query8, SnapshotVersion.none),
    );
    expect(result8, docSet(query8.comparator, <Document>[doc5]));

    // Test with limits (explicit order by DESC): (a==2) || (b == 1) ORDER BY a LIMIT_TO_LAST 1
    final Query query9 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToLast(1)
        .orderBy(orderBy('a', 'asc'));
    final DocumentSet result9 = await expectFullCollectionScan(
      () => runQuery(query9, SnapshotVersion.none),
    );
    expect(result9, docSet(query9.comparator, <Document>[doc2]));

    // Test with limits without orderBy (the __name__ ordering is the tie breaker).
    final Query query10 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 2), filter('b', '==', 1)]))
        .limitToFirst(1);
    final DocumentSet result10 = await expectFullCollectionScan(
      () => runQuery(query10, SnapshotVersion.none),
    );
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
      () => runQuery(query1, SnapshotVersion.none),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc4, doc5]));

    // Query: a==1 || b==1 order by b.
    // doc5 should not be included because it's missing the field 'b', and we have 'orderBy b'.
    final Query query2 = query('coll')
        .filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]))
        .orderBy(orderBy('b', 'asc'));
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, SnapshotVersion.none),
    );
    expect(result2, docSet(query2.comparator, <Document>[doc1, doc2, doc4]));

    // Query: a>2 || b==1.
    final Query query3 = query(
      'coll',
    ).filter(orFilters(<Filter>[filter('a', '>', 2), filter('b', '==', 1)]));
    final DocumentSet result3 = await expectFullCollectionScan(
      () => runQuery(query3, SnapshotVersion.none),
    );
    if (_shouldUsePipeline) {
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
      () => runQuery(query4, SnapshotVersion.none),
    );
    expect(result4, docSet(query4.comparator, <Document>[doc3]));

    // Query: a==1 || b==1
    // There's no explicit nor implicit orderBy. Documents with missing 'a' or missing 'b' should be
    // allowed if the document matches at least one disjunction term.
    final Query query5 = query(
      'coll',
    ).filter(orFilters(<Filter>[filter('a', '==', 1), filter('b', '==', 1)]));
    final DocumentSet result5 = await expectFullCollectionScan(
      () => runQuery(query5, SnapshotVersion.none),
    );
    expect(
      result5,
      docSet(query5.comparator, <Document>[doc1, doc2, doc4, doc5]),
    );
  });

  test('orQueryWithInAndNotIn', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', '==', 2),
        filter('b', 'in', <Object?>[2, 3]),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, SnapshotVersion.none),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    // a==2 || (b != 2 && b != 3)
    final Query query2 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', '==', 2),
        filter('b', 'not-in', <Object?>[2, 3]),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, SnapshotVersion.none),
    );
    if (_shouldUsePipeline) {
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
        <Object?>[0],
      ]),
    );
    final Document doc2 = doc(
      'coll/2',
      1,
      map(<dynamic>[
        'b',
        <Object?>[1],
      ]),
    );
    final Document doc3 = doc(
      'coll/3',
      1,
      map(<dynamic>[
        'a',
        3,
        'b',
        <Object?>[2, 7],
      ]),
    );
    final Document doc4 = doc(
      'coll/4',
      1,
      map(<dynamic>[
        'a',
        1,
        'b',
        <Object?>[3, 7],
      ]),
    );
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', '==', 2),
        filter('b', 'array-contains', 7),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, SnapshotVersion.none),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    final Query query2 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', '==', 2),
        filter('b', 'array-contains-any', <Object?>[0, 3]),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, SnapshotVersion.none),
    );
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

    // a IN [1,2,3] && a IN [0,1,4] should result in "a==1".
    final Query query1 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[1, 2, 3]),
        filter('a', 'in', <Object?>[0, 1, 4]),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, _missingLastLimboFreeSnapshot),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc4, doc5]));

    // a IN [2,3] && a IN [0,1,4] is never true and so the result should be an empty set.
    final Query query2 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('a', 'in', <Object?>[0, 1, 4]),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, _missingLastLimboFreeSnapshot),
    );
    expect(result2, docSet(query2.comparator));

    // a IN [0,3] || a IN [0,2] should union them (similar to: a IN [0,2,3]).
    final Query query3 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[0, 3]),
        filter('a', 'in', <Object?>[0, 2]),
      ]),
    );
    final DocumentSet result3 = await expectFullCollectionScan(
      () => runQuery(query3, _missingLastLimboFreeSnapshot),
    );
    expect(result3, docSet(query3.comparator, <Document>[doc3, doc6]));
  });

  // From the JS SDK (query_engine.test.ts); Android has no such case.
  test('queryWithInsAndNotInsOnTheSameField', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    // a IN [1,2,3] && a IN [0,1,3,4] && a NOT-IN [1] should result in "a==1 && a!=1 || a==3 && a!=1" or just
    // "a == 3"
    final Query query1 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[1, 2, 3]),
        filter('a', 'in', <Object?>[0, 1, 3, 4]),
        filter('a', 'not-in', <Object?>[1]),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, _missingLastLimboFreeSnapshot),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc3]));

    // a IN [2,3] && a IN [0,1,2,4] && a NOT-IN [1,2] is never true and so the result should be an empty set.
    final Query query2 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('a', 'in', <Object?>[0, 1, 2, 4]),
        filter('a', 'not-in', <Object?>[1, 2]),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, _missingLastLimboFreeSnapshot),
    );
    expect(result2, docSet(query2.comparator));

    // a IN [] || a NOT-IN [0,1,2] should union them (similar to: a NOT-IN [0,1,2]).
    final Query query3 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[]),
        filter('a', 'not-in', <Object?>[0, 1, 2]),
      ]),
    );
    final DocumentSet result3 = await expectFullCollectionScan(
      () => runQuery(query3, _missingLastLimboFreeSnapshot),
    );
    expect(result3, docSet(query3.comparator, <Document>[doc3]));

    final Query query4 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', '<=', 1),
        filter('a', 'in', <Object?>[1, 2, 3, 4]),
        filter('a', 'not-in', <Object?>[0, 2]),
      ]),
    );
    final DocumentSet result4 = await expectFullCollectionScan(
      () => runQuery(query4, _missingLastLimboFreeSnapshot),
    );
    expect(result4, docSet(query4.comparator, <Document>[doc1, doc4, doc5]));
  });

  test('queryWithMultipleInsOnDifferentFields', () async {
    final Document doc1 = doc('coll/1', 1, map(<dynamic>['a', 1, 'b', 0]));
    final Document doc2 = doc('coll/2', 1, map(<dynamic>['b', 1]));
    final Document doc3 = doc('coll/3', 1, map(<dynamic>['a', 3, 'b', 2]));
    final Document doc4 = doc('coll/4', 1, map(<dynamic>['a', 1, 'b', 3]));
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('b', 'in', <Object?>[0, 2]),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, _missingLastLimboFreeSnapshot),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc3, doc6]));

    final Query query2 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('b', 'in', <Object?>[0, 2]),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, _missingLastLimboFreeSnapshot),
    );
    expect(result2, docSet(query2.comparator, <Document>[doc3]));
  });

  test('queryInWithArrayContainsAny', () async {
    final Document doc1 = doc(
      'coll/1',
      1,
      map(<dynamic>[
        'a',
        1,
        'b',
        <Object?>[0],
      ]),
    );
    final Document doc2 = doc(
      'coll/2',
      1,
      map(<dynamic>[
        'b',
        <Object?>[1],
      ]),
    );
    final Document doc3 = doc(
      'coll/3',
      1,
      map(<dynamic>[
        'a',
        3,
        'b',
        <Object?>[2, 7],
        'c',
        10,
      ]),
    );
    final Document doc4 = doc(
      'coll/4',
      1,
      map(<dynamic>[
        'a',
        1,
        'b',
        <Object?>[3, 7],
      ]),
    );
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2, 'c', 20]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('b', 'array-contains-any', <Object?>[0, 7]),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, _missingLastLimboFreeSnapshot),
    );
    expect(
      result1,
      docSet(query1.comparator, <Document>[doc1, doc3, doc4, doc6]),
    );

    final Query query2 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('b', 'array-contains-any', <Object?>[0, 7]),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, _missingLastLimboFreeSnapshot),
    );
    expect(result2, docSet(query2.comparator, <Document>[doc3]));

    final Query query3 = query('coll').filter(
      orFilters(<Filter>[
        andFilters(<Filter>[
          filter('a', 'in', <Object?>[2, 3]),
          filter('c', '==', 10),
        ]),
        filter('b', 'array-contains-any', <Object?>[0, 7]),
      ]),
    );
    final DocumentSet result3 = await expectFullCollectionScan(
      () => runQuery(query3, _missingLastLimboFreeSnapshot),
    );
    expect(result3, docSet(query3.comparator, <Document>[doc1, doc3, doc4]));

    final Query query4 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        orFilters(<Filter>[
          filter('b', 'array-contains-any', <Object?>[0, 7]),
          filter('c', '==', 20),
        ]),
      ]),
    );
    final DocumentSet result4 = await expectFullCollectionScan(
      () => runQuery(query4, _missingLastLimboFreeSnapshot),
    );
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
        <Object?>[0],
      ]),
    );
    final Document doc2 = doc(
      'coll/2',
      1,
      map(<dynamic>[
        'b',
        <Object?>[1],
      ]),
    );
    final Document doc3 = doc(
      'coll/3',
      1,
      map(<dynamic>[
        'a',
        3,
        'b',
        <Object?>[2, 7],
        'c',
        10,
      ]),
    );
    final Document doc4 = doc(
      'coll/4',
      1,
      map(<dynamic>[
        'a',
        1,
        'b',
        <Object?>[3, 7],
      ]),
    );
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2, 'c', 20]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('b', 'array-contains', 3),
      ]),
    );
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, _missingLastLimboFreeSnapshot),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc3, doc4, doc6]));

    final Query query2 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        filter('b', 'array-contains', 7),
      ]),
    );
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, _missingLastLimboFreeSnapshot),
    );
    expect(result2, docSet(query2.comparator, <Document>[doc3]));

    final Query query3 = query('coll').filter(
      orFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        andFilters(<Filter>[
          filter('b', 'array-contains', 3),
          filter('a', '==', 1),
        ]),
      ]),
    );
    final DocumentSet result3 = await expectFullCollectionScan(
      () => runQuery(query3, _missingLastLimboFreeSnapshot),
    );
    expect(result3, docSet(query3.comparator, <Document>[doc3, doc4, doc6]));

    final Query query4 = query('coll').filter(
      andFilters(<Filter>[
        filter('a', 'in', <Object?>[2, 3]),
        orFilters(<Filter>[
          filter('b', 'array-contains', 7),
          filter('a', '==', 1),
        ]),
      ]),
    );
    final DocumentSet result4 = await expectFullCollectionScan(
      () => runQuery(query4, _missingLastLimboFreeSnapshot),
    );
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
        <Object?>[0],
      ]),
    );
    final Document doc2 = doc(
      'coll/2',
      1,
      map(<dynamic>[
        'b',
        <Object?>[1],
      ]),
    );
    final Document doc3 = doc(
      'coll/3',
      1,
      map(<dynamic>[
        'a',
        3,
        'b',
        <Object?>[2, 7],
        'c',
        10,
      ]),
    );
    final Document doc4 = doc(
      'coll/4',
      1,
      map(<dynamic>[
        'a',
        1,
        'b',
        <Object?>[3, 7],
      ]),
    );
    final Document doc5 = doc('coll/5', 1, map(<dynamic>['a', 1]));
    final Document doc6 = doc('coll/6', 1, map(<dynamic>['a', 2, 'c', 20]));
    await addDocument(<Document>[doc1, doc2, doc3, doc4, doc5, doc6]);

    final Query query1 = query(
      'coll',
    ).filter(filter('a', '==', 1)).orderBy(orderBy('a'));
    final DocumentSet result1 = await expectFullCollectionScan(
      () => runQuery(query1, _missingLastLimboFreeSnapshot),
    );
    expect(result1, docSet(query1.comparator, <Document>[doc1, doc4, doc5]));

    final Query query2 = query(
      'coll',
    ).filter(filter('a', 'in', <Object?>[2, 3])).orderBy(orderBy('a'));
    final DocumentSet result2 = await expectFullCollectionScan(
      () => runQuery(query2, _missingLastLimboFreeSnapshot),
    );
    expect(result2, docSet(query2.comparator, <Document>[doc6, doc3]));
  });
}

void _test(String name, Future<void> Function() body) => test(name, body);
