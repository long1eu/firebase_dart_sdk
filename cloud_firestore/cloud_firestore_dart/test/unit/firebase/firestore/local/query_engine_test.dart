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

// Port of the Android SDK's QueryEngineTest (pre-indexing version, 979000c^).

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/default_query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

const int _testTargetId = 1;

final Document _matchingDocA = doc('coll/a', 1,
    map(<dynamic>['matches', true, 'order', 1]), DocumentState.synced);
final Document _nonMatchingDocA = doc('coll/a', 1,
    map(<dynamic>['matches', false, 'order', 1]), DocumentState.synced);
final Document _pendingMatchingDocA = doc('coll/a', 1,
    map(<dynamic>['matches', true, 'order', 1]), DocumentState.localMutations);
final Document _pendingNonMatchingDocA = doc('coll/a', 1,
    map(<dynamic>['matches', false, 'order', 1]), DocumentState.localMutations);
final Document _updatedDocA = doc('coll/a', 11,
    map(<dynamic>['matches', true, 'order', 1]), DocumentState.synced);
final Document _matchingDocB = doc('coll/b', 1,
    map(<dynamic>['matches', true, 'order', 2]), DocumentState.synced);
final Document _updatedMatchingDocB = doc('coll/b', 11,
    map(<dynamic>['matches', true, 'order', 2]), DocumentState.synced);

final SnapshotVersion _lastLimboFreeSnapshot = version(10);
const SnapshotVersion _missingLastLimboFreeSnapshot = SnapshotVersion.none;

/// A [LocalDocumentsView] that checks whether a query is executed as a full collection scan or from the previous
/// results plus the documents read since the last limbo free snapshot.
class _ExpectingLocalDocumentsView extends LocalDocumentsView {
  _ExpectingLocalDocumentsView(MemoryPersistence persistence)
      : super(
          remoteDocumentCache: persistence.remoteDocumentCache,
          mutationQueue: persistence.getMutationQueue(User.unauthenticated),
          documentOverlayCache:
              persistence.getDocumentOverlayCache(User.unauthenticated),
          indexManager: persistence.indexManager,
        );

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

void main() {
  late MemoryPersistence persistence;
  late RemoteDocumentCache remoteDocumentCache;
  late QueryCache queryCache;
  late QueryEngine queryEngine;
  late _ExpectingLocalDocumentsView localDocuments;

  setUp(() async {
    persistence = await createEagerGCMemoryPersistence();
    queryCache = persistence.queryCache;
    remoteDocumentCache = persistence.remoteDocumentCache;
    localDocuments = _ExpectingLocalDocumentsView(persistence);
    queryEngine = DefaultQueryEngine()..setLocalDocumentsView(localDocuments);
  });

  tearDown(() => persistence.shutdown());

  /// Adds the provided documents to the query target mapping.
  Future<void> persistQueryMapping(List<DocumentKey> documentKeys) {
    return persistence.runTransaction('persistQueryMapping', () async {
      await queryCache.addMatchingKeys(keySet(documentKeys), _testTargetId);
    });
  }

  /// Adds the provided documents to the remote document cache.
  Future<void> addDocument(List<Document> docs) {
    return persistence.runTransaction('addDocument', () async {
      for (Document doc in docs) {
        await remoteDocumentCache.add(doc, doc.version);
      }
    });
  }

  Future<DocumentSet> runQuery(
      Query query, SnapshotVersion lastLimboFreeSnapshotVersion,
      {required bool expectFullCollectionScan}) async {
    localDocuments.expectFullCollectionScan = expectFullCollectionScan;
    try {
      final ImmutableSortedMap<DocumentKey, Document> docs =
          await queryEngine.getDocumentsMatchingQuery(
              query,
              lastLimboFreeSnapshotVersion,
              await queryCache.getMatchingKeysForTargetId(_testTargetId));
      final View view = View(query, DocumentKey.emptyKeySet);
      final ViewDocumentChanges viewDocChanges = view.computeDocChanges(docs);
      return view.applyChanges(viewDocChanges).snapshot!.documents;
    } finally {
      localDocuments.expectFullCollectionScan = null;
    }
  }

  test('usesTargetMappingForInitialView', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(
        <DocumentKey>[_matchingDocA.key, _matchingDocB.key]);

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: false);
    expect(
        docs, docSet(q.comparator, <Document>[_matchingDocA, _matchingDocB]));
  });

  test('filtersNonMatchingInitialResults', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(
        <DocumentKey>[_matchingDocA.key, _matchingDocB.key]);

    // Add a mutated document that is not yet part of query's set of remote keys.
    await addDocument(<Document>[_pendingNonMatchingDocA]);

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: false);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test('includesChangesSinceInitialResults', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));

    await addDocument(<Document>[_matchingDocA, _matchingDocB]);
    await persistQueryMapping(
        <DocumentKey>[_matchingDocA.key, _matchingDocB.key]);

    DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: false);
    expect(
        docs, docSet(q.comparator, <Document>[_matchingDocA, _matchingDocB]));

    await addDocument(<Document>[_updatedMatchingDocB]);

    docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: false);
    expect(docs,
        docSet(q.comparator, <Document>[_matchingDocA, _updatedMatchingDocB]));
  });

  test('doesNotUseInitialResultsWithoutLimboFreeSnapshotVersion', () async {
    final Query q = query('coll').filter(filter('matches', '==', true));
    final DocumentSet docs = await runQuery(q, _missingLastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator));
  });

  test('doesNotUseInitialResultsForUnfilteredCollectionQuery', () async {
    final Query q = query('coll');
    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator));
  });

  test('doesNotUseInitialResultsForLimitQueryWithDocumentRemoval', () async {
    final Query q =
        query('coll').filter(filter('matches', '==', true)).limitToFirst(1);

    // While the backend would never add DocA to the set of remote keys, this allows us to easily simulate what would
    // happen when a document no longer matches due to an out-of-band update.
    await addDocument(<Document>[_nonMatchingDocA]);
    await persistQueryMapping(<DocumentKey>[_nonMatchingDocA.key]);

    await addDocument(<Document>[_matchingDocB]);

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test('doesNotUseInitialResultsForLimitToLastQueryWithDocumentRemoval',
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

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test('doesNotUseInitialResultsForLimitQueryWhenLastDocumentHasPendingWrite',
      () async {
    final Query q = query('coll')
        .filter(filter('matches', '==', true))
        .orderBy(orderBy('order', 'desc'))
        .limitToFirst(1);

    // Add a query mapping for a document that matches, but that sorts below another document due to a pending write.
    await addDocument(<Document>[_pendingMatchingDocA]);
    await persistQueryMapping(<DocumentKey>[_pendingMatchingDocA.key]);

    await addDocument(<Document>[_matchingDocB]);

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test(
      'doesNotUseInitialResultsForLimitToLastQueryWhenLastDocumentHasPendingWrite',
      () async {
    final Query q = query('coll')
        .filter(filter('matches', '==', true))
        .orderBy(orderBy('order', 'asc'))
        .limitToLast(1);

    // Add a query mapping for a document that matches, but that sorts below another document due to a pending write.
    await addDocument(<Document>[_pendingMatchingDocA]);
    await persistQueryMapping(<DocumentKey>[_pendingMatchingDocA.key]);

    await addDocument(<Document>[_matchingDocB]);

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

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

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

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

    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: true);
    expect(docs, docSet(q.comparator, <Document>[_matchingDocB]));
  });

  test('limitQueriesUseInitialResultsIfLastDocumentInLimitIsUnchanged',
      () async {
    final Query q = query('coll').orderBy(orderBy('order')).limitToFirst(2);

    await addDocument(<Document>[
      doc('coll/a', 1, map(<dynamic>['order', 1]))
    ]);
    await addDocument(<Document>[
      doc('coll/b', 1, map(<dynamic>['order', 3]))
    ]);
    await persistQueryMapping(<DocumentKey>[key('coll/a'), key('coll/b')]);

    // Update "coll/a" but make sure it still sorts before "coll/b"
    await addDocument(<Document>[
      doc('coll/a', 1, map(<dynamic>['order', 2]), DocumentState.localMutations)
    ]);

    // Since the last document in the limit didn't change (and hence we know that all documents written prior to query
    // execution still sort after "coll/b"), we should use an Index-Free query.
    final DocumentSet docs = await runQuery(q, _lastLimboFreeSnapshot,
        expectFullCollectionScan: false);
    expect(
        docs,
        docSet(q.comparator, <Document>[
          doc('coll/a', 1, map(<dynamic>['order', 2]),
              DocumentState.localMutations),
          doc('coll/b', 1, map(<dynamic>['order', 3])),
        ]));
  });
}
