// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'accumulating_stats_collector.dart';
import 'cases/local_store_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  late LocalStoreTestCase testCase;

  setUp(() async {
    print('setUp');

    final AccumulatingStatsCollector statsCollector =
        AccumulatingStatsCollector();

    final SQLitePersistence persistence = await createSQLitePersistence(
      'firebase/firestore/local/local_store_test-${const Uuid().v4()}.db',
      const LruGarbageCollectorParams(),
      statsCollector,
    );

    testCase = LocalStoreTestCase(persistence, statsCollector,
        garbageCollectorIsEager: false);
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase?.tearDown()));

  test('testMutationBatchKeys', () => testCase.testMutationBatchKeys());
  test('testAllocatesTheSameTargetForMirrorQueries',
      () => testCase.testAllocatesTheSameTargetForMirrorQueries());
  test('testExecutesLimitToLastQueryInTheQueryOrder',
      () => testCase.testExecutesLimitToLastQueryInTheQueryOrder());
  test('testHandlesSetMutation', () => testCase.testHandlesSetMutation());
  test('testHandlesSetMutationThenDocument',
      () => testCase.testHandlesSetMutationThenDocument());
  test('testHandlesSetMutationThenAckThenRelease',
      () => testCase.testHandlesSetMutationThenAckThenRelease());
  test('testHandlesAckThenRejectThenRemoteEvent',
      () => testCase.testHandlesAckThenRejectThenRemoteEvent());
  test('testHandlesDeletedDocumentThenSetMutationThenAck',
      () => testCase.testHandlesDeletedDocumentThenSetMutationThenAck());
  test('testHandlesSetMutationThenDeletedDocument',
      () => testCase.testHandlesSetMutationThenDeletedDocument());
  test('testHandlesDocumentThenSetMutationThenAckThenDocument',
      () => testCase.testHandlesDocumentThenSetMutationThenAckThenDocument());
  test('testHandlesPatchWithoutPriorDocument',
      () => testCase.testHandlesPatchWithoutPriorDocument());
  test('testHandlesPatchMutationThenDocumentThenAck',
      () => testCase.testHandlesPatchMutationThenDocumentThenAck());
  test('testHandlesPatchMutationThenAckThenDocument',
      () => testCase.testHandlesPatchMutationThenAckThenDocument());
  test('testHandlesDeleteMutationThenAck',
      () => testCase.testHandlesDeleteMutationThenAck());
  test('testHandlesDocumentThenDeleteMutationThenAck',
      () => testCase.testHandlesDocumentThenDeleteMutationThenAck());
  test('testHandlesDeleteMutationThenDocumentThenAck',
      () => testCase.testHandlesDeleteMutationThenDocumentThenAck());
  test('testHandlesDocumentThenDeletedDocumentThenDocument',
      () => testCase.testHandlesDocumentThenDeletedDocumentThenDocument());
  test(
      'testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck',
      () => testCase
          .testHandlesSetMutationThenPatchMutationThenDocumentThenAckThenAck());
  test('testHandlesSetMutationAndPatchMutationTogether',
      () => testCase.testHandlesSetMutationAndPatchMutationTogether());
  test('testHandlesSetMutationThenPatchMutationThenReject',
      () => testCase.testHandlesSetMutationThenPatchMutationThenReject());
  test(
      'testHandlesSetMutationsAndPatchMutationOfJustOneTogether',
      () =>
          testCase.testHandlesSetMutationsAndPatchMutationOfJustOneTogether());
  test(
      'testHandlesDeleteMutationThenPatchMutationThenAckThenAck',
      () =>
          testCase.testHandlesDeleteMutationThenPatchMutationThenAckThenAck());
  test('testCollectsGarbageAfterChangeBatchWithNoTargetIDs',
      () => testCase.testCollectsGarbageAfterChangeBatchWithNoTargetIDs());
  test('testCollectsGarbageAfterChangeBatch',
      () => testCase.testCollectsGarbageAfterChangeBatch());
  test('testCollectsGarbageAfterAcknowledgedMutation',
      () => testCase.testCollectsGarbageAfterAcknowledgedMutation());
  test('testCollectsGarbageAfterRejectedMutation',
      () => testCase.testCollectsGarbageAfterRejectedMutation());
  test('testPinsDocumentsInTheLocalView',
      () => testCase.testPinsDocumentsInTheLocalView());
  test('testThrowsAwayDocumentsWithUnknownTargetIDsImmediately',
      () => testCase.testThrowsAwayDocumentsWithUnknownTargetIDsImmediately());
  test('testCanExecuteDocumentQueries',
      () => testCase.testCanExecuteDocumentQueries());
  test('testCanExecuteCollectionQueries',
      () => testCase.testCanExecuteCollectionQueries());
  test('testCanExecuteMixedCollectionQueries',
      () => testCase.testCanExecuteMixedCollectionQueries());
  test('testReadsAllDocumentsForCollectionQueries',
      () => testCase.testReadsAllDocumentsForCollectionQueries());
  test('testWritesOverlaysAndRemovesThemOnAck', () => testCase.testWritesOverlaysAndRemovesThemOnAck());
  test('testDeviationRejectRemovesOverlayThatNoLongerApplies', () => testCase.testDeviationRejectRemovesOverlayThatNoLongerApplies());
  test('testDeviationRemoteDeleteRemovesPatchOverlay', () => testCase.testDeviationRemoteDeleteRemovesPatchOverlay());
  test('testDeviationEmptyMergeKeepsItsOverlay', () => testCase.testDeviationEmptyMergeKeepsItsOverlay());
  test('testDeviationSetOverlayOfMergeIsRecalculatedWhenDocumentArrives', () => testCase.testDeviationSetOverlayOfMergeIsRecalculatedWhenDocumentArrives());
  test('testReadsAllDocumentsForInitialCollectionQueries', () => testCase.testReadsAllDocumentsForInitialCollectionQueries());
  test('testUsesTargetMappingToExecuteQueries', () => testCase.testUsesTargetMappingToExecuteQueries());
  test('testLastLimboFreeSnapshotIsAdvancedDuringViewProcessing', () => testCase.testLastLimboFreeSnapshotIsAdvancedDuringViewProcessing());
  test('testQueriesIncludeLocallyModifiedDocuments', () => testCase.testQueriesIncludeLocallyModifiedDocuments());
  test('testQueriesIncludeDocumentsFromOtherQueries', () => testCase.testQueriesIncludeDocumentsFromOtherQueries());
  test('testQueriesFilterDocumentsThatNoLongerMatch', () => testCase.testQueriesFilterDocumentsThatNoLongerMatch());
  test('testQueriesIncludeBundledDocumentsReadAfterTheTargetWasSynced',
      () => testCase.testQueriesIncludeBundledDocumentsReadAfterTheTargetWasSynced());
  test('testClearsLastLimboFreeSnapshotOnExistenceFilterMismatch', () => testCase.testClearsLastLimboFreeSnapshotOnExistenceFilterMismatch());
  test('testPersistsResumeTokens', () => testCase.testPersistsResumeTokens());
  test('testDoesNotReplaceResumeTokenWithEmptyByteString',
      () => testCase.testDoesNotReplaceResumeTokenWithEmptyByteString());
  test('testRemoteDocumentKeysForTarget',
      () => testCase.testRemoteDocumentKeysForTarget());
  test('testRemoteDocumentKeysForTarget',
      () => testCase.testRemoteDocumentKeysForTarget());
  test(
      'testHandlesSetMutationThenTransformMutationThenTransformMutation',
      () => testCase
          .testHandlesSetMutationThenTransformMutationThenTransformMutation());
  test(
      'testHandlesSetMutationThenAckThenTransformMutationThenAckThenTransformMutation',
      () => testCase
          .testHandlesSetMutationThenAckThenTransformMutationThenAckThenTransformMutation());
  test(
      'testHandlesSetMutationThenTransformMutationThenRemoteEventThenTransformMutation',
      () => testCase
          .testHandlesSetMutationThenTransformMutationThenRemoteEventThenTransformMutation());
  test('testHandlesSetMutationWithFoldedTransformThenAck',
      () => testCase.testHandlesSetMutationWithFoldedTransformThenAck());
  test('testHoldsBackOnlyNonIdempotentTransforms',
      () => testCase.testHoldsBackOnlyNonIdempotentTransforms());
  test('testHandlesMergeMutationWithTransformThenRemoteEvent',
      () => testCase.testHandlesMergeMutationWithTransformThenRemoteEvent());
  test('testHandlesPatchMutationWithTransformThenRemoteEvent',
      () => testCase.testHandlesPatchMutationWithTransformThenRemoteEvent());
  test('testOnlyPersistsUpdatesForDocumentsWhenVersionChanges',
      () => testCase.testOnlyPersistsUpdatesForDocumentsWhenVersionChanges());
  test('testRemovesManufacturedNoDocumentsFromTheCache',
      () => testCase.testRemovesManufacturedNoDocumentsFromTheCache());
  test('testClearsResumeTokenOnExistenceFilterMismatch',
      () => testCase.testClearsResumeTokenOnExistenceFilterMismatch());
  test('testGetHighestUnacknowledgedBatchId',
      () => testCase.testGetHighestUnacknowledgedBatchId());

  // The index cases of SQLiteLocalStoreTest of the Android SDK.
  test('testAddsIndexes', () => testCase.testAddsIndexes());
  test('testRemovesIndexes', () => testCase.testRemovesIndexes());
  test('testDoesNotResetIndexWhenSameIndexIsAdded', () => testCase.testDoesNotResetIndexWhenSameIndexIsAdded());
  test('testDeletedDocumentRemovesIndex', () => testCase.testDeletedDocumentRemovesIndex());
  test('testUsesIndexes', () => testCase.testUsesIndexes());
  test('testUsesPartiallyIndexedRemoteDocumentsWhenAvailable', () => testCase.testUsesPartiallyIndexedRemoteDocumentsWhenAvailable());
  test('testUsesPartiallyIndexedOverlaysWhenAvailable', () => testCase.testUsesPartiallyIndexedOverlaysWhenAvailable());
  test('testDoesNotUseLimitWhenIndexIsOutdated', () => testCase.testDoesNotUseLimitWhenIndexIsOutdated());
  test('testUsesIndexForLimitQueryWhenIndexIsUpdated', () => testCase.testUsesIndexForLimitQueryWhenIndexIsUpdated());
  test('testIndexesVectorValues', () => testCase.testIndexesVectorValues());
  test('testIndexesBsonObjectId', () => testCase.testIndexesBsonObjectId());
  test('testIndexesBsonTimestamp', () => testCase.testIndexesBsonTimestamp());
  test('testIndexesBsonBinary', () => testCase.testIndexesBsonBinary());
  test('testIndexesRegex', () => testCase.testIndexesRegex());
  test('testIndexesInt32', () => testCase.testIndexesInt32());
  test('testIndexesDecimal128Value', () => testCase.testIndexesDecimal128Value());
  test('testIndexesDecimal128ValueWithPrecisionLoss', () => testCase.testIndexesDecimal128ValueWithPrecisionLoss());
  test('testIndexesMinKey', () => testCase.testIndexesMinKey());
  test('testIndexesMaxKey', () => testCase.testIndexesMaxKey());
  test('testIndexesAllBsonTypesTogether', () => testCase.testIndexesAllBsonTypesTogether());
  test('testIndexesAllTypesTogether', () => testCase.testIndexesAllTypesTogether());
  test('testIndexesServerTimestamps', () => testCase.testIndexesServerTimestamps());

  // The automatic index creation cases of SQLiteLocalStoreTest of the Android SDK.
  test('testCanAutoCreateIndexes', () => testCase.testCanAutoCreateIndexes());
  test('testCanAutoCreateIndexesWorksWithOrQuery', () => testCase.testCanAutoCreateIndexesWorksWithOrQuery());
  test('testDoesNotAutoCreateIndexesForSmallCollections', () => testCase.testDoesNotAutoCreateIndexesForSmallCollections());
  test('testDoesNotAutoCreateIndexesWhenIndexLookUpIsExpensive', () => testCase.testDoesNotAutoCreateIndexesWhenIndexLookUpIsExpensive());
  test('testIndexAutoCreationWorksWhenBackfillerRunsHalfway', () => testCase.testIndexAutoCreationWorksWhenBackfillerRunsHalfway());
  test('testIndexCreatedByIndexAutoCreationExistsAfterTurnOffAutoCreation', () => testCase.testIndexCreatedByIndexAutoCreationExistsAfterTurnOffAutoCreation());
  test('testDisableIndexAutoCreationWorks', () => testCase.testDisableIndexAutoCreationWorks());
  test('testDeleteAllIndexesWorksWithIndexAutoCreation', () => testCase.testDeleteAllIndexesWorksWithIndexAutoCreation());
  test('testDeleteAllIndexesWorksWithManualAddedIndexes', () => testCase.testDeleteAllIndexesWorksWithManualAddedIndexes());
  test('testIndexAutoCreationWorksWithMutation', () => testCase.testIndexAutoCreationWorksWithMutation());
  test('testIndexAutoCreationDoesnotWorkWithMultipleInequality', () => testCase.testIndexAutoCreationDoesnotWorkWithMultipleInequality());
}
