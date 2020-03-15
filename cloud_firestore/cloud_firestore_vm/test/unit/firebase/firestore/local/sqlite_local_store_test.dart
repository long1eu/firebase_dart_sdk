// File created by
// Lung Razvan <long1eu>
// on 29/09/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'cases/local_store_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  LocalStoreTestCase testCase;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence = await openSQLitePersistence(
        'firebase/firestore/local/local_store_test-${Uuid().v4()}.db');

    testCase = LocalStoreTestCase(persistence, garbageCollectorIsEager: false);
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase?.tearDown()));

  test('testMutationBatchKeys', () => testCase.testMutationBatchKeys());
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
  test('testHoldsBackOnlyNonIdempotentTransforms',
      () => testCase.testHoldsBackOnlyNonIdempotentTransforms());
  test('testHandlesMergeMutationWithTransformThenRemoteEvent',
      () => testCase.testHandlesMergeMutationWithTransformThenRemoteEvent());
  test('testHandlesPatchMutationWithTransformThenRemoteEvent',
      () => testCase.testHandlesPatchMutationWithTransformThenRemoteEvent());
}
