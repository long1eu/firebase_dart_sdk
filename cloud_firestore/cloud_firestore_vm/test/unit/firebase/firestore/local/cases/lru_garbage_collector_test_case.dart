// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_vm/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/listent_sequence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_delegate.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/mutation_queue.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/reference_set.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

typedef PersistenceBuilder = Future<Persistence> Function(
    LruGarbageCollectorParams params);

class LruGarbageCollectorTestCase {
  LruGarbageCollectorTestCase(this._getPersistence);

  final PersistenceBuilder _getPersistence;

  Persistence _persistence;
  QueryCache _queryCache;
  MutationQueue _mutationQueue;
  RemoteDocumentCache _documentCache;
  LruGarbageCollector _garbageCollector;
  LruGarbageCollectorParams _lruParams;
  int _previousTargetId;
  int _previousDocNum;
  int _initialSequenceNumber;
  ObjectValue _testValue;

  Future<void> setUp() async {
    _previousTargetId = 500;
    _previousDocNum = 10;
    final Map<String, Object> dataMap = <String, Object>{
      'test': 'data',
      'foo': true,
      'bar': 3
    };

    _testValue = wrapMap(dataMap);
    await _newTestResources();
  }

  Future<void> tearDown() => _persistence.shutdown();

  @testMethod
  Future<void> testPickSequenceNumberPercentile() async {
    final List<int> queryCounts = <int>[0, 10, 9, 50, 49];
    final List<int> expectedCounts = <int>[0, 1, 0, 5, 4];

    for (int i = 0; i < queryCounts.length; i++) {
      final int numQueries = queryCounts[i];
      final int expectedTenthPercentile = expectedCounts[i];
      await _newTestResources();
      _garbageCollector = _garbageCollector;
      for (int j = 0; j < numQueries; j++) {
        await _addNextQuery();
      }

      final int tenth = await _garbageCollector.calculateQueryCount(10);
      expect(tenth, expectedTenthPercentile);
    }
  }

  @testMethod
  Future<void> testSequenceNumberNoQueries() async {
    expect(await _garbageCollector.getNthSequenceNumber(0),
        ListenSequence.invalid);
  }

  @testMethod
  Future<void> testSequenceNumberForFiftyQueries() async {
    // Add 50 queries sequentially, aim to collect 10 of them.
    // The sequence number to collect should be 10 past the initial sequence number.
    for (int i = 0; i < 50; i++) {
      await _addNextQuery();
    }

    expect(await _garbageCollector.getNthSequenceNumber(10),
        _initialSequenceNumber + 10);
  }

  @testMethod
  Future<void> testSequenceNumberForMultipleQueriesInATransaction() async {
    // 50 queries, 9 with one transaction, incrementing from there. Should get second sequence number.
    await _persistence.runTransaction('9 queries in a batch', () async {
      for (int i = 0; i < 9; i++) {
        await _addNextQueryInTransaction();
      }
    });
    for (int i = 9; i < 50; i++) {
      await _addNextQuery();
    }
    expect(await _garbageCollector.getNthSequenceNumber(10),
        2 + _initialSequenceNumber);
  }

  @testMethod
  Future<void> testAllCollectedQueriesInSingleTransaction() async {
    // Ensure that even if all of the queries are added in a single transaction, we still pick a sequence number and GC.
    // In this case, the initial transaction contains all of the targets that will get GC'd, since they account for more
    // than the first 10 targets. 50 queries, 11 with one transaction, incrementing from there. Should get first
    // sequence number.
    await _persistence.runTransaction('9 queries in a batch', () async {
      for (int i = 0; i < 11; i++) {
        await _addNextQueryInTransaction();
      }
    });

    for (int i = 11; i < 50; i++) {
      await _addNextQuery();
    }

    expect(await _garbageCollector.getNthSequenceNumber(10),
        1 + _initialSequenceNumber);
  }

  @testMethod
  Future<void> testSequenceNumbersWithMutationAndSequentialQueries() async {
    // Remove a mutated doc reference, marking it as eligible for GC.
    // Then add 50 queries. Should get 10 past initial (9 queries).
    await _markADocumentEligibleForGc();
    for (int i = 0; i < 50; i++) {
      await _addNextQuery();
    }

    expect(await _garbageCollector.getNthSequenceNumber(10),
        10 + _initialSequenceNumber);
  }

  @testMethod
  Future<void> testSequenceNumbersWithMutationsInQueries() async {
    // Add mutated docs, then add one of them to a query target so it doesn't get GC'd. Expect 3 past the initial value:
    // the mutations not part of a query, and two queries
    final DocumentKey docInQuery = _nextTestDocumentKey();
    await _persistence.runTransaction('mark mutations', () async {
      // Adding 9 doc keys in a transaction. If we remove one of them, we'll have room for two actual queries.
      await _markDocumentEligibleForGcInTransaction(docInQuery);
      for (int i = 0; i < 8; i++) {
        await _markADocumentEligibleForGcInTransaction();
      }
    });
    for (int i = 0; i < 49; i++) {
      await _addNextQuery();
    }
    await _persistence.runTransaction('query with a mutation', () async {
      final QueryData queryData = await _addNextQueryInTransaction();
      await _addDocumentToTarget(docInQuery, queryData.targetId);
    });

    // This should catch the remaining 8 documents, plus the first two queries we added.
    expect(await _garbageCollector.getNthSequenceNumber(10),
        3 + _initialSequenceNumber);
  }

  @testMethod
  Future<void> testRemoveQueriesUpThroughSequenceNumber() async {
    final Map<int, QueryData> activeTargetIds = <int, QueryData>{};
    for (int i = 0; i < 100; i++) {
      final QueryData queryData = await _addNextQuery();
      // Mark odd queries as live so we can test filtering out live queries.
      final int targetId = queryData.targetId;
      if (targetId % 2 == 1) {
        activeTargetIds[targetId] = queryData;
      }
    }

    // GC up through 20th query, which is 20%.
    // Expect to have GC'd 10 targets, since every other target is live
    final int upperBound = 20 + _initialSequenceNumber;
    final int removed =
        await _removeTargets(upperBound, activeTargetIds.keys.toSet());
    expect(removed, 10);

    // Make sure we removed the even targets with targetID <= 20.
    await _persistence
        .runTransaction('verify remaining targets are > 20 or odd', () async {
      return _queryCache.forEachTarget((QueryData queryData) {
        final bool isOdd = queryData.targetId.remainder(2) == 1;
        final bool isOver20 = queryData.targetId > 20;
        expect(isOdd || isOver20, isTrue);
      });
    });
  }

  @testMethod
  Future<void> testRemoveOrphanedDocuments() async {
    // Track documents we expect to be retained so we can verify post-GC. This will contain documents associated with
    // targets that survive GC, as well as any documents with pending mutations.
    final Set<DocumentKey> expectedRetained = <DocumentKey>{};
    // we add two mutations later, for now track them in an array.
    final List<Mutation> mutations = <Mutation>[];

    await _persistence
        .runTransaction('add a target and add two documents to it', () async {
      // Add two documents to first target, queue a mutation on the second document
      final QueryData queryData = await _addNextQueryInTransaction();
      final Document doc1 = await _cacheADocumentInTransaction();
      await _addDocumentToTarget(doc1.key, queryData.targetId);
      expectedRetained.add(doc1.key);

      final Document doc2 = await _cacheADocumentInTransaction();
      await _addDocumentToTarget(doc2.key, queryData.targetId);
      expectedRetained.add(doc2.key);
      mutations.add(_mutation(doc2.key));
    });

    // Add a second query and register a third document on it
    await _persistence.runTransaction('second query', () async {
      final QueryData queryData = await _addNextQueryInTransaction();
      final Document doc3 = await _cacheADocumentInTransaction();
      await _addDocumentToTarget(doc3.key, queryData.targetId);
      expectedRetained.add(doc3.key);
    });

    // cache another document and prepare a mutation on it.
    await _persistence.runTransaction('queue a mutation', () async {
      final Document doc4 = await _cacheADocumentInTransaction();
      mutations.add(_mutation(doc4.key));
      expectedRetained.add(doc4.key);
    });

    // Insert the mutations. These operations don't have a sequence number, they just serve to keep the mutated
    // documents from being GC'd while the mutations are outstanding.
    await _persistence.runTransaction('actually register the mutations',
        () async {
      final Timestamp writeTime = Timestamp.now();
      await _mutationQueue.addMutationBatch(writeTime, <Mutation>[], mutations);
    });

    // Mark 5 documents eligible for GC. This simulates documents that were mutated then ack'd. Since they were ack'd,
    // they are no longer in a mutation queue, and there is nothing keeping them alive.
    final Set<DocumentKey> toBeRemoved = <DocumentKey>{};
    await _persistence.runTransaction(
        'add orphaned docs (previously mutated, then ack\'d)', () async {
      for (int i = 0; i < 5; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        toBeRemoved.add(doc.key);
        await _markDocumentEligibleForGcInTransaction(doc.key);
      }
    });

    // We expect only the orphaned documents, those not in a mutation or a target, to be removed. Use a large sequence
    // number to remove as much as possible
    final int removed = await _garbageCollector.removeOrphanedDocuments(1000);
    expect(removed, toBeRemoved.length);
    await _persistence.runTransaction('verify', () async {
      for (DocumentKey key in toBeRemoved) {
        expect(await _documentCache.get(key), isNull);
        expect(await _queryCache.containsKey(key), isFalse);
      }
      for (DocumentKey key in expectedRetained) {
        expect(await _documentCache.get(key), isNotNull);
      }
    });
  }

  @testMethod
  Future<void> testRemoveTargetsThenGC() async {
    // * Create 3 targets, add docs to all of them
    // * Leave oldest target alone, it is still live
    // * Remove newest target
    // * Blind write 2 documents
    // * Add one of the blind write docs to oldest target (preserves it)
    // * Remove some documents from middle target (bumps sequence number)
    // * Add some documents from newest target to oldest target (preserves them)
    // * Update a doc from middle target
    // * Remove middle target
    // * Do a blind write
    // * GC up to but not including the removal of the middle target
    //
    // Expect:
    // * All docs in oldest target are still around
    // * One blind write is gone, the first one not added to oldest target
    // * Documents removed from middle target are gone, except ones added to oldest target
    // * Documents from newest target are gone, except those added to the old target as well

    // Through the various steps, track which documents we expect to be removed vs documents we expect to be retained.
    final Set<DocumentKey> expectedRetained = <DocumentKey>{};
    final Set<DocumentKey> expectedRemoved = <DocumentKey>{};

    // Add oldest target, 5 documents, and add those documents to the target. This target will not be removed, so all
    // documents that are part of it will be retained.
    final QueryData oldestTarget = await _persistence
        .runTransactionAndReturn('Add oldest target and docs', () async {
      final QueryData queryData = await _addNextQueryInTransaction();
      for (int i = 0; i < 5; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await _addDocumentToTarget(doc.key, queryData.targetId);
      }
      return queryData;
    });

    // Add middle target and docs. Some docs will be removed from this target later, which we track here.
    final Set<DocumentKey> middleDocsToRemove = <DocumentKey>{};
    // This will be the document in this target that gets an update later.
    DocumentKey middleDocToUpdateHolder;
    final QueryData middleTarget = await _persistence
        .runTransactionAndReturn('Add middle target and docs', () async {
      final QueryData queryData = await _addNextQueryInTransaction();
      // These docs will be removed from this target later, triggering a bump to their sequence numbers. Since they will
      // not be a part of the target, we expect them to be removed.
      for (int i = 0; i < 2; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        await _addDocumentToTarget(doc.key, queryData.targetId);
        expectedRemoved.add(doc.key);
        middleDocsToRemove.add(doc.key);
      }
      // These docs stay in this target and only this target. There presence in this target prevents them from being
      // GC'd, so they are also expected to be retained.
      for (int i = 2; i < 4; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await _addDocumentToTarget(doc.key, queryData.targetId);
      }
      // This doc stays in this target, but gets updated.
      {
        final Document doc = await _cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await _addDocumentToTarget(doc.key, queryData.targetId);
        middleDocToUpdateHolder = doc.key;
      }
      return queryData;
    });
    final DocumentKey middleDocToUpdate = middleDocToUpdateHolder;

    // Add the newest target and add 5 documents to it. Some of those documents will additionally be added to the oldest
    // target, which will cause those documents to be retained. The remaining documents are expected to be removed,
    // since this target will be removed.
    final Set<DocumentKey> newestDocsToAddToOldest = <DocumentKey>{};
    await _persistence.runTransaction('Add newest target and docs', () async {
      final QueryData queryData = await _addNextQueryInTransaction();
      // These documents are only in this target. They are expected to be removed because this target will also be
      // removed.
      for (int i = 0; i < 3; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        expectedRemoved.add(doc.key);
        await _addDocumentToTarget(doc.key, queryData.targetId);
      }

      // Docs to add to the oldest target in addition to this target. They will be retained
      for (int i = 3; i < 5; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await _addDocumentToTarget(doc.key, queryData.targetId);
        newestDocsToAddToOldest.add(doc.key);
      }
    });

    // 2 doc writes, add one of them to the oldest target.
    await _persistence.runTransaction(
        '2 doc writes, add one of them to the oldest target', () async {
      // Write two docs and have them ack'd by the server. can skip mutation queue and set them in document cache. Add
      // potentially orphaned first, also add one doc to a target.
      final Document doc1 = await _cacheADocumentInTransaction();
      await _markDocumentEligibleForGcInTransaction(doc1.key);
      await _updateTargetInTransaction(oldestTarget);
      await _addDocumentToTarget(doc1.key, oldestTarget.targetId);
      // doc1 should be retained by being added to oldestTarget
      expectedRetained.add(doc1.key);

      final Document doc2 = await _cacheADocumentInTransaction();
      await _markDocumentEligibleForGcInTransaction(doc2.key);
      // nothing is keeping doc2 around, it should be removed
      expectedRemoved.add(doc2.key);
    });

    // Remove some documents from the middle target.
    await _persistence.runTransaction(
        'Remove some documents from the middle target', () async {
      await _updateTargetInTransaction(middleTarget);
      for (DocumentKey key in middleDocsToRemove) {
        await _removeDocumentFromTarget(key, middleTarget.targetId);
      }
    });

    // Add a couple docs from the newest target to the oldest (preserves them past the point where newest was removed)
    // upperBound is the sequence number right before middleTarget is updated, then removed.
    final int upperBound = await _persistence.runTransactionAndReturn(
        'Add a couple docs from the newest target to the oldest', () async {
      await _updateTargetInTransaction(oldestTarget);
      for (DocumentKey key in newestDocsToAddToOldest) {
        await _addDocumentToTarget(key, oldestTarget.targetId);
      }
      return _persistence.referenceDelegate.currentSequenceNumber;
    });

    // Update a doc in the middle target
    await _persistence.runTransaction('Update a doc in the middle target',
        () async {
      final SnapshotVersion newVersion = version(3);
      final Document doc = Document(
          middleDocToUpdate, newVersion, _testValue, DocumentState.synced);
      await _documentCache.add(doc);
      await _updateTargetInTransaction(middleTarget);
    });

    // Remove the middle target
    await _persistence.runTransaction('remove middle target',
        () => _persistence.referenceDelegate.removeTarget(middleTarget));

    // Write a doc and get an ack, not part of a target
    await _persistence.runTransaction(
        'Write a doc and get an ack, not part of a target', () async {
      final Document doc = await _cacheADocumentInTransaction();
      // Mark it as eligible for GC, but this is after our upper bound for what we will collect.
      await _markDocumentEligibleForGcInTransaction(doc.key);
      // This should be retained, it's too new to get removed.
      expectedRetained.add(doc.key);
    });

    // Finally, do the garbage collection, up to but not including the removal of middleTarget
    final Set<int> activeTargetIds = <int>{oldestTarget.targetId};
    final int targetsRemoved =
        await _garbageCollector.removeTargets(upperBound, activeTargetIds);
    // Expect to remove newest target
    expect(targetsRemoved, 1);
    final int docsRemoved =
        await _garbageCollector.removeOrphanedDocuments(upperBound);
    expect(docsRemoved, expectedRemoved.length);
    await _persistence.runTransaction('verify results', () async {
      for (DocumentKey key in expectedRemoved) {
        expect(await _documentCache.get(key), isNull);
        expect(await _queryCache.containsKey(key), isFalse);
      }
      for (DocumentKey key in expectedRetained) {
        expect(await _documentCache.get(key), isNotNull);
      }
    });
  }

  Future<void> testGetsSize() async {
    final LruGarbageCollector garbageCollector = _garbageCollector;
    final int initialSize = await garbageCollector.byteSize;

    await _persistence.runTransaction('fill cache', () async {
      // Simulate a bunch of ack'd mutations
      for (int i = 0; i < 50; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        await _markDocumentEligibleForGcInTransaction(doc.key);
      }
    });

    final int finalSize = await garbageCollector.byteSize;
    expect(finalSize, greaterThan(initialSize));
  }

  Future<void> testDisabled() async {
    final LruGarbageCollectorParams params =
        LruGarbageCollectorParams.disabled();

    // Switch out the test resources for ones with a disabled GC.
    await _persistence.shutdown();
    await _newTestResources(params);

    await _persistence.runTransaction('Fill cache', () async {
      // Simulate a bunch of ack'd mutations
      for (int i = 0; i < 500; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        await _markDocumentEligibleForGcInTransaction(doc.key);
      }
    });

    final LruGarbageCollectorResults results =
        await _persistence.runTransactionAndReturn(
            'GC', () => _garbageCollector.collect(<int>{}));

    expect(results.hasRun, isFalse);
  }

  Future<void> testCacheTooSmall() async {
    // Default LRU Params are ok for this test.

    await _persistence.runTransaction('Fill cache', () async {
      // Simulate a bunch of ack'd mutations
      for (int i = 0; i < 50; i++) {
        final Document doc = await _cacheADocumentInTransaction();
        await _markDocumentEligibleForGcInTransaction(doc.key);
      }
    });

    // Make sure we're under the target size
    final int cacheSize = await _garbageCollector.byteSize;
    expect(cacheSize, lessThan(_lruParams.minBytesThreshold));

    final LruGarbageCollectorResults results =
        await _persistence.runTransactionAndReturn(
            'GC', () => _garbageCollector.collect(<int>{}));

    expect(results.hasRun, isFalse);
  }

  Future<void> testGCRan() async {
    // Set a low byte threshold so we can guarantee that GC will run.
    final LruGarbageCollectorParams params =
        LruGarbageCollectorParams.withCacheSizeBytes(100);

    // Switch to persistence using our new params.
    await _persistence.shutdown();
    await _newTestResources(params);

    // Add 100 targets and 10 documents to each
    for (int i = 0; i < 100; i++) {
      // Use separate transactions so that each target and associated documents get their own sequence number.
      await _persistence.runTransaction('Add a target and some documents',
          () async {
        final QueryData queryData = await _addNextQueryInTransaction();
        for (int j = 0; j < 10; j++) {
          final Document doc = await _cacheADocumentInTransaction();
          await _addDocumentToTarget(doc.key, queryData.targetId);
        }
      });
    }

    // Mark nothing as live, so everything is eligible.
    final LruGarbageCollectorResults results =
        await _persistence.runTransactionAndReturn(
            'GC', () => _garbageCollector.collect(<int>{}));

    // By default, we collect 10% of the sequence numbers. Since we added 100 targets, that should be 10 targets with
    // 10 documents each, for a total of 100 documents.
    expect(results.hasRun, isTrue);
    expect(results.targetsRemoved, 10);
    expect(results.documentsRemoved, 100);
  }

  Future<void> _newTestResources(
      [LruGarbageCollectorParams params =
          const LruGarbageCollectorParams()]) async {
    _persistence = await _getPersistence(params);

    _persistence.referenceDelegate.inMemoryPins = ReferenceSet();
    _queryCache = _persistence.queryCache;
    _documentCache = _persistence.remoteDocumentCache;
    const User user = User('user');
    _mutationQueue = _persistence.getMutationQueue(user);
    await _mutationQueue.start();

    _initialSequenceNumber = _queryCache.highestListenSequenceNumber;
    // ignore: avoid_as
    final LruDelegate delegate = _persistence.referenceDelegate as LruDelegate;
    _garbageCollector = delegate.garbageCollector;
    _lruParams = params;
  }

  Future<QueryData> _nextQueryData() async {
    final int targetId = ++_previousTargetId;
    final int sequenceNumber =
        _persistence.referenceDelegate.currentSequenceNumber;
    final Query _query = query('path$targetId');
    return QueryData(_query, targetId, sequenceNumber, QueryPurpose.listen);
  }

  Future<void> _updateTargetInTransaction(QueryData queryData) async {
    final SnapshotVersion _version = version(2);
    final Uint8List _resumeToken = resumeToken(2);
    final QueryData updated = queryData.copyWith(
      sequenceNumber: _persistence.referenceDelegate.currentSequenceNumber,
      snapshotVersion: _version,
      resumeToken: _resumeToken,
    );
    await _queryCache.updateQueryData(updated);
  }

  Future<QueryData> _addNextQueryInTransaction() async {
    final QueryData queryData = await _nextQueryData();
    await _queryCache.addQueryData(queryData);
    return queryData;
  }

  Future<QueryData> _addNextQuery() {
    return _persistence.runTransactionAndReturn(
        'Add query', _addNextQueryInTransaction);
  }

  DocumentKey _nextTestDocumentKey() {
    return DocumentKey.fromPathString('docs/doc_${++_previousDocNum}');
  }

  Document _nextTestDocument() {
    final DocumentKey key = _nextTestDocumentKey();
    const int version = 1;
    final Map<String, Object> data = <String, Object>{
      'baz': true,
      'ok': 'fine',
    };

    return doc(key, version, data);
  }

  Future<Document> _cacheADocumentInTransaction() async {
    final Document doc = _nextTestDocument();
    await _documentCache.add(doc);
    return doc;
  }

  Future<void> _markDocumentEligibleForGcInTransaction(DocumentKey key) async {
    await _persistence.referenceDelegate.removeMutationReference(key);
  }

  Future<void> _markDocumentEligibleForGc(DocumentKey key) async {
    await _persistence.runTransaction('Removing mutation reference',
        () => _markDocumentEligibleForGcInTransaction(key));
  }

  Future<void> _markADocumentEligibleForGc() async {
    final DocumentKey key = _nextTestDocumentKey();
    await _markDocumentEligibleForGc(key);
  }

  Future<void> _markADocumentEligibleForGcInTransaction() async {
    final DocumentKey key = _nextTestDocumentKey();
    await _markDocumentEligibleForGcInTransaction(key);
  }

  Future<void> _addDocumentToTarget(DocumentKey key, int targetId) async {
    await _queryCache.addMatchingKeys(keySet(<DocumentKey>[key]), targetId);
  }

  Future<void> _removeDocumentFromTarget(DocumentKey key, int targetId) async {
    await _queryCache.removeMatchingKeys(keySet(<DocumentKey>[key]), targetId);
  }

  Future<int> _removeTargets(int upperBound, Set<int> activeTargetIds) {
    return _persistence.runTransactionAndReturn('Remove queries',
        () => _garbageCollector.removeTargets(upperBound, activeTargetIds));
  }

  SetMutation _mutation(DocumentKey key) {
    return SetMutation(key, _testValue, Precondition.none);
  }
}
