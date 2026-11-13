// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:test/test.dart';

import 'accumulating_stats_collector.dart';
import 'cases/local_store_test_case.dart';
import 'persistence_test_helpers.dart';

/// Upstream runs these with `assumeFalse(garbageCollectorIsEager())`: eager GC removes the documents the test relies on.
const String _needsLruGc =
    'Needs a non-eager garbage collector (upstream assumeFalse(garbageCollectorIsEager())); covered by sqlite_local_store_test.';

void main() {
  late LocalStoreTestCase testCase;

  setUp(() async {
    print('setUp');

    final AccumulatingStatsCollector statsCollector =
        AccumulatingStatsCollector();
    final MemoryPersistence persistence = await createEagerGCMemoryPersistence(
      statsCollector,
    );
    testCase = LocalStoreTestCase(
      persistence,
      statsCollector,
      garbageCollectorIsEager: true,
    );
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(
    () => Future<void>.delayed(
      const Duration(milliseconds: 250),
      () => testCase.tearDown(),
    ),
  );

  test('testMutationBatchKeys', () => testCase.testMutationBatchKeys());
  test(
    'testAllocatesTheSameTargetForMirrorQueries',
    () => testCase.testAllocatesTheSameTargetForMirrorQueries(),
  );
  test(
    'testExecutesLimitToLastQueryInTheQueryOrder',
    () => testCase.testExecutesLimitToLastQueryInTheQueryOrder(),
  );
  test('testHandlesSetMutation', () => testCase.testHandlesSetMutation());
  test(
    'testHandlesSetMutationThenDocument',
    () => testCase.testHandlesSetMutationThenDocument(),
  );
  test(
    'testHandlesSetMutationThenAckThenRelease',
    () => testCase.testHandlesSetMutationThenAckThenRelease(),
  );
  test(
    'testHandlesAckThenRejectThenRemoteEvent',
    () => testCase.testHandlesAckThenRejectThenRemoteEvent(),
  );
  test(
    'testHandlesDeletedDocumentThenSetMutationThenAck',
    () => testCase.testHandlesDeletedDocumentThenSetMutationThenAck(),
  );
  test(
    'testHandlesSetMutationThenDeletedDocument',
    () => testCase.testHandlesSetMutationThenDeletedDocument(),
  );
  test(
    'testHandlesDocumentThenSetMutationThenAckThenDocument',
    () => testCase.testHandlesDocumentThenSetMutationThenAckThenDocument(),
  );
  test(
    'testHandlesPatchWithoutPriorDocument',
    () => testCase.testHandlesPatchWithoutPriorDocument(),
  );
  test(
    'testHandlesPatchMutationThenDocumentThenAck',
    () => testCase.testHandlesPatchMutationThenDocumentThenAck(),
  );
  test(
    'testHandlesPatchMutationThenAckThenDocument',
    () => testCase.testHandlesPatchMutationThenAckThenDocument(),
  );
  test(
    'testHandlesDeleteMutationThenAck',
    () => testCase.testHandlesDeleteMutationThenAck(),
  );
  test(
    'testHandlesDocumentThenDeleteMutationThenAck',
    () => testCase.testHandlesDocumentThenDeleteMutationThenAck(),
  );
  test(
    'testHandlesDeleteMutationThenDocumentThenAck',
    () => testCase.testHandlesDeleteMutationThenDocumentThenAck(),
  );
  test(
    'testHandlesDocumentThenDeletedDocumentThenDocument',
    () => testCase.testHandlesDocumentThenDeletedDocumentThenDocument(),
  );
  test(
    'testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck',
    () => testCase
        .testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck(),
  );
  test(
    'testHandlesSetMutationAndPatchMutationTogether',
    () => testCase.testHandlesSetMutationAndPatchMutationTogether(),
  );
  test(
    'testHandlesSetMutationThenPatchMutationThenReject',
    () => testCase.testHandlesSetMutationThenPatchMutationThenReject(),
  );
  test(
    'testHandlesSetMutationsAndPatchMutationOfJustOneTogether',
    () => testCase.testHandlesSetMutationsAndPatchMutationOfJustOneTogether(),
  );
  test(
    'testHandlesDeleteMutationThenPatchMutationThenAckThenAck',
    () => testCase.testHandlesDeleteMutationThenPatchMutationThenAckThenAck(),
  );
  test(
    'testCollectsGarbageAfterChangeBatchWithNoTargetIDs',
    () => testCase.testCollectsGarbageAfterChangeBatchWithNoTargetIDs(),
  );
  test(
    'testCollectsGarbageAfterChangeBatch',
    () => testCase.testCollectsGarbageAfterChangeBatch(),
  );
  test(
    'testCollectsGarbageAfterAcknowledgedMutation',
    () => testCase.testCollectsGarbageAfterAcknowledgedMutation(),
  );
  test(
    'testCollectsGarbageAfterRejectedMutation',
    () => testCase.testCollectsGarbageAfterRejectedMutation(),
  );
  test(
    'testPinsDocumentsInTheLocalView',
    () => testCase.testPinsDocumentsInTheLocalView(),
  );
  test(
    'testThrowsAwayDocumentsWithUnknownTargetIDsImmediately',
    () => testCase.testThrowsAwayDocumentsWithUnknownTargetIDsImmediately(),
  );
  test(
    'testCanExecuteDocumentQueries',
    () => testCase.testCanExecuteDocumentQueries(),
  );
  test(
    'testCanExecuteCollectionQueries',
    () => testCase.testCanExecuteCollectionQueries(),
  );
  test(
    'testCanExecuteMixedCollectionQueries',
    () => testCase.testCanExecuteMixedCollectionQueries(),
  );
  test(
    'testReadsAllDocumentsForCollectionQueries',
    () => testCase.testReadsAllDocumentsForCollectionQueries(),
  );
  test(
    'testWritesOverlaysAndRemovesThemOnAck',
    () => testCase.testWritesOverlaysAndRemovesThemOnAck(),
  );
  test(
    'testDeviationRejectRemovesOverlayThatNoLongerApplies',
    () => testCase.testDeviationRejectRemovesOverlayThatNoLongerApplies(),
  );
  test(
    'testDeviationRemoteDeleteRemovesPatchOverlay',
    () => testCase.testDeviationRemoteDeleteRemovesPatchOverlay(),
  );
  test(
    'testDeviationEmptyMergeKeepsItsOverlay',
    () => testCase.testDeviationEmptyMergeKeepsItsOverlay(),
  );
  test(
    'testDeviationSetOverlayOfMergeIsRecalculatedWhenDocumentArrives',
    () => testCase
        .testDeviationSetOverlayOfMergeIsRecalculatedWhenDocumentArrives(),
  );
  test(
    'testReadsAllDocumentsForInitialCollectionQueries',
    () => testCase.testReadsAllDocumentsForInitialCollectionQueries(),
  );
  test(
    'testUsesTargetMappingToExecuteQueries',
    () => testCase.testUsesTargetMappingToExecuteQueries(),
    skip: _needsLruGc,
  );
  test(
    'testLastLimboFreeSnapshotIsAdvancedDuringViewProcessing',
    () => testCase.testLastLimboFreeSnapshotIsAdvancedDuringViewProcessing(),
  );
  test(
    'testQueriesIncludeLocallyModifiedDocuments',
    () => testCase.testQueriesIncludeLocallyModifiedDocuments(),
    skip: _needsLruGc,
  );
  test(
    'testQueriesIncludeDocumentsFromOtherQueries',
    () => testCase.testQueriesIncludeDocumentsFromOtherQueries(),
    skip: _needsLruGc,
  );
  test(
    'testQueriesFilterDocumentsThatNoLongerMatch',
    () => testCase.testQueriesFilterDocumentsThatNoLongerMatch(),
    skip: _needsLruGc,
  );
  test(
    'testQueriesIncludeBundledDocumentsReadAfterTheTargetWasSynced',
    () => testCase
        .testQueriesIncludeBundledDocumentsReadAfterTheTargetWasSynced(),
    skip: _needsLruGc,
  );
  test(
    'testIgnoresTargetMappingAfterExistenceFilterMismatch',
    () => testCase.testIgnoresTargetMappingAfterExistenceFilterMismatch(),
    skip: _needsLruGc,
  );
  test(
    'testPersistsResumeTokens',
    () => testCase.testPersistsResumeTokens(),
    skip: _needsLruGc,
  );
  test(
    'testDoesNotReplaceResumeTokenWithEmptyByteString',
    () => testCase.testDoesNotReplaceResumeTokenWithEmptyByteString(),
    skip: _needsLruGc,
  );
  test(
    'testRemoteDocumentKeysForTarget',
    () => testCase.testRemoteDocumentKeysForTarget(),
  );
  test(
    'testHandlesSetMutationThenTransformThenTransform',
    () => testCase.testHandlesSetMutationThenTransformThenTransform(),
  );
  test(
    'testHandlesSetMutationThenAckThenTransformThenAckThenTransform',
    () => testCase
        .testHandlesSetMutationThenAckThenTransformThenAckThenTransform(),
    skip: _needsLruGc,
  );
  test(
    'testHandlesSetMutationThenTransformThenRemoteEventThenTransform',
    () => testCase
        .testHandlesSetMutationThenTransformThenRemoteEventThenTransform(),
  );
  test(
    'testHandlesSetMutationWithFoldedTransformThenAck',
    () => testCase.testHandlesSetMutationWithFoldedTransformThenAck(),
    skip: _needsLruGc,
  );
  test('testHoldsBackTransforms', () => testCase.testHoldsBackTransforms());
  test(
    'testHandlesMergeMutationWithTransformThenRemoteEvent',
    () => testCase.testHandlesMergeMutationWithTransformThenRemoteEvent(),
  );
  test(
    'testHandlesPatchMutationWithTransformThenRemoteEvent',
    () => testCase.testHandlesPatchMutationWithTransformThenRemoteEvent(),
  );
  test(
    'testOnlyPersistsUpdatesForDocumentsWhenVersionChanges',
    () => testCase.testOnlyPersistsUpdatesForDocumentsWhenVersionChanges(),
  );
  test(
    'testRemovesManufacturedNoDocumentsFromTheCache',
    () => testCase.testRemovesManufacturedNoDocumentsFromTheCache(),
  );
  test(
    'testClearsResumeTokenOnExistenceFilterMismatch',
    () => testCase.testClearsResumeTokenOnExistenceFilterMismatch(),
  );
  test(
    'testUpdateOnRemoteDocLeadsToUpdateOverlay',
    () => testCase.testUpdateOnRemoteDocLeadsToUpdateOverlay(),
  );
  test(
    'testAddThenUpdateWhileOffline',
    () => testCase.testAddThenUpdateWhileOffline(),
  );
  test(
    'testGetHighestUnacknowledgedBatchId',
    () => testCase.testGetHighestUnacknowledgedBatchId(),
  );
  // SQLiteLocalStoreTest; the JS SDK runs it on memory persistence as well
  // ("deeply nested server timestamps do not cause stack overflow").
  test(
    'testDeeplyNestedServerTimestamps',
    () => testCase.testDeeplyNestedServerTimestamps(),
  );
}
