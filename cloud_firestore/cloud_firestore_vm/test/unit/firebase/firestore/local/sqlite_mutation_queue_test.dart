// File created by
// Lung Razvan <long1eu>
// on 01/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'cases/mutation_queue_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  MutationQueueTestCase testCase;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence =
        await openSQLitePersistence('firebase/firestore/local/sqlite_mutation_queue_test-${Uuid().v4()}.db');
    testCase = MutationQueueTestCase(persistence);
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(const Duration(milliseconds: 250), () => testCase.tearDown()));
  test('testCountBatches', () => testCase.testCountBatches());
  test('testAcknowledgeThenRemove', () => testCase.testAcknowledgeThenRemove());
  test('testLookupMutationBatch', () => testCase.testLookupMutationBatch());
  test('testNextMutationBatchAfterBatchId', () => testCase.testNextMutationBatchAfterBatchId());
  test('testAllMutationBatchesAffectingDocumentKey', () => testCase.testAllMutationBatchesAffectingDocumentKey());
  test('testAllMutationBatchesAffectingDocumentKeys', () => testCase.testAllMutationBatchesAffectingDocumentKeys());
  test('testAllMutationBatchesAffectingDocumentLotsOfDocumentKeys',
      () => testCase.testAllMutationBatchesAffectingDocumentLotsOfDocumentKeys(),
      timeout: const Timeout(Duration(minutes: 2)));
  test('testAllMutationBatchesAffectingQuery', () => testCase.testAllMutationBatchesAffectingQuery());
  test('testAllMutationBatchesAffectingQuery_withCompoundBatches',
      () => testCase.testAllMutationBatchesAffectingQueryWithCompoundBatches());
  test('testRemoveMutationBatches', () => testCase.testRemoveMutationBatches());
  test('testStreamToken', () => testCase.testStreamToken());
}
