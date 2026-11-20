// The shared mutation queue suite (cases/mutation_queue_test_case.dart) on the IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_mutation_queue_test.dart

@TestOn('browser')
library;

import 'package:test/test.dart';

import '../unit/firebase/firestore/local/cases/mutation_queue_test_case.dart';
import 'indexeddb_test_persistence.dart';

void main() {
  late MutationQueueTestCase testCase;

  setUp(() async {
    testCase = MutationQueueTestCase(await newIndexedDbTestPersistence());
    await testCase.setUp();
  });

  tearDown(() => testCase.tearDown());

  test('testCountBatches', () => testCase.testCountBatches());
  test('testAcknowledgeThenRemove', () => testCase.testAcknowledgeThenRemove());
  test('testLookupMutationBatch', () => testCase.testLookupMutationBatch());
  test(
    'testNextMutationBatchAfterBatchId',
    () => testCase.testNextMutationBatchAfterBatchId(),
  );
  test(
    'testAllMutationBatchesAffectingDocumentKey',
    () => testCase.testAllMutationBatchesAffectingDocumentKey(),
  );
  test(
    'testAllMutationBatchesAffectingDocumentKeys',
    () => testCase.testAllMutationBatchesAffectingDocumentKeys(),
  );
  test(
    'testAllMutationBatchesAffectingDocumentLotsOfDocumentKeys',
    () => testCase.testAllMutationBatchesAffectingDocumentLotsOfDocumentKeys(),
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'testAllMutationBatchesAffectingQuery',
    () => testCase.testAllMutationBatchesAffectingQuery(),
  );
  test(
    'testAllMutationBatchesAffectingQuery_withCompoundBatches',
    () => testCase.testAllMutationBatchesAffectingQueryWithCompoundBatches(),
  );
  test('testRemoveMutationBatches', () => testCase.testRemoveMutationBatches());
  test('testStreamToken', () => testCase.testStreamToken());
}
