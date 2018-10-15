// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/listent_sequence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'cases/lru_garbage_collector_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  LruGarbageCollectorTestCase testCase;
  LruGarbageCollector garbageCollector;

  setUp(() async {
    print('setUp');
    testCase = LruGarbageCollectorTestCase(
        () => PersistenceTestHelpers.createLRUMemoryPersistence());
    await testCase.setUp();

    garbageCollector = testCase.garbageCollector;
    print('setUpDone');
  });

  tearDown(() {
    return Future<void>.delayed(const Duration(milliseconds: 250), () async {
      await testCase.tearDown();
      testCase = null;
      garbageCollector = null;
    });
  });

  test('testPickSequenceNumberPercentile', () async {
    final List<int> queryCounts = <int>[0, 10, 9, 50, 49];
    final List<int> expectedCounts = <int>[0, 1, 0, 5, 4];

    for (int i = 0; i < queryCounts.length; i++) {
      final int numQueries = queryCounts[i];
      final int expectedTenthPercentile = expectedCounts[i];
      await testCase.newTestResources();
      garbageCollector = testCase.garbageCollector;
      for (int j = 0; j < numQueries; j++) {
        await testCase.addNextQuery();
      }

      final int tenth = garbageCollector.calculateQueryCount(10);
      expect(tenth, expectedTenthPercentile);
    }
  });

  test('testSequenceNumberNoQueries', () async {
    expect(await garbageCollector.nthSequenceNumber(0), ListenSequence.invalid);
  });

  test('testSequenceNumberForFiftyQueries', () async {
    // Add 50 queries sequentially, aim to collect 10 of them.
    // The sequence number to collect should be 10 past the initial sequence
    // number.
    for (int i = 0; i < 50; i++) {
      await testCase.addNextQuery();
    }

    expect(await garbageCollector.nthSequenceNumber(10),
        testCase.initialSequenceNumber + 10);
  });

  test('testSequenceNumberForMultipleQueriesInATransaction', () async {
    // 50 queries, 9 with one transaction, incrementing from there. Should get
    // second sequence number.
    await testCase.persistence.runTransaction('9 queries in a batch', () async {
      for (int i = 0; i < 9; i++) {
        await testCase.addNextQueryInTransaction();
      }
    });
    for (int i = 9; i < 50; i++) {
      await testCase.addNextQuery();
    }
    expect(await garbageCollector.nthSequenceNumber(10),
        2 + testCase.initialSequenceNumber);
  });

  test('testAllCollectedQueriesInSingleTransaction', () async {
    // Ensure that even if all of the queries are added in a single transaction,
    // we still pick a sequence number and GC. In this case, the initial
    // transaction contains all of the targets that will get GC'd, since they
    // account for more than the first 10 targets. 50 queries, 11 with one
    // transaction, incrementing from there. Should get first sequence
    // number.
    await testCase.persistence.runTransaction('9 queries in a batch', () async {
      for (int i = 0; i < 11; i++) {
        await testCase.addNextQueryInTransaction();
      }
    });

    for (int i = 11; i < 50; i++) {
      await testCase.addNextQuery();
    }

    expect(await garbageCollector.nthSequenceNumber(10),
        1 + testCase.initialSequenceNumber);
  });

  test('testSequenceNumbersWithMutationAndSequentialQueries', () async {
    // Remove a mutated doc reference, marking it as eligible for GC.
    // Then add 50 queries. Should get 10 past initial (9 queries).
    await testCase.markADocumentEligibleForGc();
    for (int i = 0; i < 50; i++) {
      await testCase.addNextQuery();
    }

    expect(await garbageCollector.nthSequenceNumber(10),
        10 + testCase.initialSequenceNumber);
  });

  test('testSequenceNumbersWithMutationsInQueries', () async {
    // Add mutated docs, then add one of them to a query target so it doesn't
    // get GC'd. Expect 3 past the initial value: the mutations not part of a
    // query, and two queries
    final DocumentKey docInQuery = testCase.nextTestDocumentKey();
    await testCase.persistence.runTransaction('mark mutations', () async {
      // Adding 9 doc keys in a transaction. If we remove one of them, we'll
      // have room for two actual queries.
      await testCase.markDocumentEligibleForGcInTransaction(docInQuery);
      for (int i = 0; i < 8; i++) {
        await testCase.markADocumentEligibleForGcInTransaction();
      }
    });
    for (int i = 0; i < 49; i++) {
      await testCase.addNextQuery();
    }
    await testCase.persistence.runTransaction('query with a mutation',
        () async {
      final QueryData queryData = await testCase.addNextQueryInTransaction();
      await testCase.addDocumentToTarget(docInQuery, queryData.targetId);
    });

    // This should catch the remaining 8 documents, plus the first two queries
    // we added.
    expect(await garbageCollector.nthSequenceNumber(10),
        3 + testCase.initialSequenceNumber);
  });

  test('testRemoveQueriesUpThroughSequenceNumber', () async {
    final Map<int, QueryData> activeTargetIds = <int, QueryData>{};
    for (int i = 0; i < 100; i++) {
      final QueryData queryData = await testCase.addNextQuery();
      // Mark odd queries as live so we can test filtering out live queries.
      final int targetId = queryData.targetId;
      if (targetId % 2 == 1) {
        activeTargetIds[targetId] = queryData;
      }
    }

    // GC up through 20th query, which is 20%.
    // Expect to have GC'd 10 targets, since every other target is live
    final int upperBound = 20 + testCase.initialSequenceNumber;
    final int removed =
        await testCase.removeTargets(upperBound, activeTargetIds.keys.toSet());
    expect(removed, 10);

    // Make sure we removed the even targets with targetID <= 20.
    await testCase.persistence
        .runTransaction('verify remaining targets are > 20 or odd', () async {
      return testCase.queryCache.forEachTarget((QueryData queryData) {
        final bool isOdd = queryData.targetId.remainder(2) == 1;
        final bool isOver20 = queryData.targetId > 20;
        expect(isOdd || isOver20, isTrue);
      });
    });
  });

  test('testRemoveOrphanedDocuments', () async {
    // Track documents we expect to be retained so we can verify post-GC. This
    // will contain documents associated with targets that survive GC, as well
    // as any documents with pending mutations.
    final Set<DocumentKey> expectedRetained = Set<DocumentKey>();
    // we add two mutations later, for now track them in an array.
    final List<Mutation> mutations = <Mutation>[];

    await testCase.persistence
        .runTransaction('add a target and add two documents to it', () async {
      // Add two documents to first target, queue a mutation on the second
      // document
      final QueryData queryData = await testCase.addNextQueryInTransaction();
      final Document doc1 = await testCase.cacheADocumentInTransaction();
      await testCase.addDocumentToTarget(doc1.key, queryData.targetId);
      expectedRetained.add(doc1.key);

      final Document doc2 = await testCase.cacheADocumentInTransaction();
      await testCase.addDocumentToTarget(doc2.key, queryData.targetId);
      expectedRetained.add(doc2.key);
      mutations.add(testCase.mutation(doc2.key));
    });

    // Add a second query and register a third document on it
    await testCase.persistence.runTransaction('second query', () async {
      final QueryData queryData = await testCase.addNextQueryInTransaction();
      final Document doc3 = await testCase.cacheADocumentInTransaction();
      await testCase.addDocumentToTarget(doc3.key, queryData.targetId);
      expectedRetained.add(doc3.key);
    });

    // cache another document and prepare a mutation on it.
    await testCase.persistence.runTransaction('queue a mutation', () async {
      final Document doc4 = await testCase.cacheADocumentInTransaction();
      mutations.add(testCase.mutation(doc4.key));
      expectedRetained.add(doc4.key);
    });

    // Insert the mutations. These operations don't have a sequence number, they
    // just serve to keep the mutated documents from being GC'd while the
    // mutations are outstanding.
    await testCase.persistence.runTransaction('actually register the mutations',
        () async {
      final Timestamp writeTime = Timestamp.now();
      await testCase.mutationQueue.addMutationBatch(writeTime, mutations);
    });

    // Mark 5 documents eligible for GC. This simulates documents that were
    // mutated then ack'd. Since they were ack'd, they are no longer in a
    // mutation queue, and there is nothing keeping them alive.
    final Set<DocumentKey> toBeRemoved = Set<DocumentKey>();
    await testCase.persistence.runTransaction(
        'add orphaned docs (previously mutated, then ack\'d)', () async {
      for (int i = 0; i < 5; i++) {
        final Document doc = await testCase.cacheADocumentInTransaction();
        toBeRemoved.add(doc.key);
        await testCase.markDocumentEligibleForGcInTransaction(doc.key);
      }
    });

    // We expect only the orphaned documents, those not in a mutation or a
    // target, to be removed. Use a large sequence number to remove as much as
    // possible
    final int removed = await garbageCollector.removeOrphanedDocuments(1000);
    expect(removed, toBeRemoved.length);
    await testCase.persistence.runTransaction('verify', () async {
      for (DocumentKey key in toBeRemoved) {
        expect(await testCase.documentCache.get(key), isNull);
        expect(await testCase.queryCache.containsKey(key), isFalse);
      }
      for (DocumentKey key in expectedRetained) {
        expect(await testCase.documentCache.get(key), isNotNull);
      }
    });
  });

  test('testRemoveTargetsThenGC', () async {
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
    // * Documents removed from middle target are gone, except ones added to
    //   oldest target
    // * Documents from newest target are gone, except

    // Through the various steps, track which documents we expect to be removed
    // vs documents we expect to be retained.
    final Set<DocumentKey> expectedRetained = Set<DocumentKey>();
    final Set<DocumentKey> expectedRemoved = Set<DocumentKey>();

    // Add oldest target, 5 documents, and add those documents to the target.
    // This target will not be removed, so all documents that are part of it
    // will be retained.
    final QueryData oldestTarget = await testCase.persistence
        .runTransactionAndReturn('Add oldest target and docs', () async {
      final QueryData queryData = await testCase.addNextQueryInTransaction();
      for (int i = 0; i < 5; i++) {
        final Document doc = await testCase.cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await testCase.addDocumentToTarget(doc.key, queryData.targetId);
      }
      return queryData;
    });

    // Add middle target and docs. Some docs will be removed from this target
    // later, which we track here.
    final Set<DocumentKey> middleDocsToRemove = Set<DocumentKey>();
    // This will be the document in this target that gets an update later.
    DocumentKey middleDocToUpdateHolder;
    final QueryData middleTarget = await testCase.persistence
        .runTransactionAndReturn('Add middle target and docs', () async {
      final QueryData queryData = await testCase.addNextQueryInTransaction();
      // these docs will be removed from this target later, triggering a bump
      // to their sequence numbers. Since they will not be a part of the target,
      // we expect them to be removed.
      for (int i = 0; i < 2; i++) {
        final Document doc = await testCase.cacheADocumentInTransaction();
        await testCase.addDocumentToTarget(doc.key, queryData.targetId);
        expectedRemoved.add(doc.key);
        middleDocsToRemove.add(doc.key);
      }
      // these docs stay in this target and only this target. There presence in
      // this target prevents them from being GC'd, so they are also expected to
      // be retained.
      for (int i = 2; i < 4; i++) {
        final Document doc = await testCase.cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await testCase.addDocumentToTarget(doc.key, queryData.targetId);
      }
      // This doc stays in this target, but gets updated.
      {
        final Document doc = await testCase.cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await testCase.addDocumentToTarget(doc.key, queryData.targetId);
        middleDocToUpdateHolder = doc.key;
      }
      return queryData;
    });
    final DocumentKey middleDocToUpdate = middleDocToUpdateHolder;

    // Add the newest target and add 5 documents to it. Some of those documents
    // will additionally be added to the oldest target, which will cause those
    // documents to be retained. The remaining documents are expected to be
    // removed, since this target will be removed.
    final Set<DocumentKey> newestDocsToAddToOldest = Set<DocumentKey>();
    await testCase.persistence.runTransaction('Add newest target and docs',
        () async {
      final QueryData queryData = await testCase.addNextQueryInTransaction();
      // These documents are only in this target. They are expected to be
      // removed because this target will also be removed.
      for (int i = 0; i < 3; i++) {
        final Document doc = await testCase.cacheADocumentInTransaction();
        expectedRemoved.add(doc.key);
        await testCase.addDocumentToTarget(doc.key, queryData.targetId);
      }

      // docs to add to the oldest target in addition to this target. They will
      // be retained
      for (int i = 3; i < 5; i++) {
        final Document doc = await testCase.cacheADocumentInTransaction();
        expectedRetained.add(doc.key);
        await testCase.addDocumentToTarget(doc.key, queryData.targetId);
        newestDocsToAddToOldest.add(doc.key);
      }
    });

    // 2 doc writes, add one of them to the oldest target.
    await testCase.persistence.runTransaction(
        '2 doc writes, add one of them to the oldest target', () async {
      // write two docs and have them ack'd by the server. can skip mutation
      // queue and set them in document cache. Add potentially orphaned first,
      // also add one doc to a target.
      final Document doc1 = await testCase.cacheADocumentInTransaction();
      await testCase.markDocumentEligibleForGcInTransaction(doc1.key);
      await testCase.updateTargetInTransaction(oldestTarget);
      await testCase.addDocumentToTarget(doc1.key, oldestTarget.targetId);
      // doc1 should be retained by being added to oldestTarget
      expectedRetained.add(doc1.key);

      final Document doc2 = await testCase.cacheADocumentInTransaction();
      await testCase.markDocumentEligibleForGcInTransaction(doc2.key);
      // nothing is keeping doc2 around, it should be removed
      expectedRemoved.add(doc2.key);
    });

    // Remove some documents from the middle target.
    await testCase.persistence.runTransaction(
        'Remove some documents from the middle target', () async {
      await testCase.updateTargetInTransaction(middleTarget);
      for (DocumentKey key in middleDocsToRemove) {
        await testCase.removeDocumentFromTarget(key, middleTarget.targetId);
      }
    });

    // Add a couple docs from the newest target to the oldest (preserves them
    // past the point where newest was removed) upperBound is the sequence
    // number right before middleTarget is updated, then removed.
    final int upperBound = await testCase.persistence.runTransactionAndReturn(
        'Add a couple docs from the newest target to the oldest', () async {
      await testCase.updateTargetInTransaction(oldestTarget);
      for (DocumentKey key in newestDocsToAddToOldest) {
        await testCase.addDocumentToTarget(key, oldestTarget.targetId);
      }
      return testCase.persistence.referenceDelegate.currentSequenceNumber;
    });

    // Update a doc in the middle target
    await testCase.persistence
        .runTransaction('Update a doc in the middle target', () async {
      final SnapshotVersion newVersion = TestUtil.version(3);
      final Document doc =
          Document(middleDocToUpdate, newVersion, testCase.testValue, false);
      await testCase.documentCache.add(doc);
      await testCase.updateTargetInTransaction(middleTarget);
    });

    // Remove the middle target
    await testCase.persistence.runTransaction(
        'remove middle target',
        () =>
            testCase.persistence.referenceDelegate.removeTarget(middleTarget));

    // Write a doc and get an ack, not part of a target
    await testCase.persistence.runTransaction(
        'Write a doc and get an ack, not part of a target', () async {
      final Document doc = await testCase.cacheADocumentInTransaction();
      // Mark it as eligible for GC, but this is after our upper bound for what
      // we will collect.
      await testCase.markDocumentEligibleForGcInTransaction(doc.key);
      // This should be retained, it's too new to get removed.
      expectedRetained.add(doc.key);
    });

    // Finally, do the garbage collection, up to but not including the removal
    // of middleTarget
    final Set<int> activeTargetIds = Set<int>();
    activeTargetIds.add(oldestTarget.targetId);
    final int targetsRemoved = await testCase.garbageCollector
        .removeTargets(upperBound, activeTargetIds);
    // Expect to remove newest target
    expect(targetsRemoved, 1);
    final int docsRemoved =
        await testCase.garbageCollector.removeOrphanedDocuments(upperBound);
    expect(docsRemoved, expectedRemoved.length);
    await testCase.persistence.runTransaction('verify results', () async {
      for (DocumentKey key in expectedRemoved) {
        expect(await testCase.documentCache.get(key), isNull);
        expect(await testCase.queryCache.containsKey(key), isFalse);
      }
      for (DocumentKey key in expectedRetained) {
        expect(await testCase.documentCache.get(key), isNotNull);
      }
    });
  });
}

// ignore: always_specify_types
const query = TestUtil.query;
// ignore: always_specify_types
const filter = TestUtil.filter;
// ignore: always_specify_types
const key = TestUtil.key;
