// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'cases/lru_garbage_collector_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  LruGarbageCollectorTestCase testCase;

  setUp(() async {
    print('setUp');

    testCase = LruGarbageCollectorTestCase(
        () => openSQLitePersistence('firebase/firestore/local/sqlite_lru_garbage_collector_test-${Uuid().v4()}.db'));
    await testCase.setUp();

    print('setUpDone');
  });

  tearDown(() {
    return Future<void>.delayed(const Duration(milliseconds: 250), () async {
      await testCase.tearDown();
      testCase = null;
    });
  });

  test('testPickSequenceNumberPercentile', () => testCase.testPickSequenceNumberPercentile());
  test('testSequenceNumberNoQueries', () => testCase.testSequenceNumberNoQueries());
  test('testSequenceNumberForFiftyQueries', () => testCase.testSequenceNumberForFiftyQueries());
  test('testSequenceNumberForMultipleQueriesInATransaction',
      () => testCase.testSequenceNumberForMultipleQueriesInATransaction());
  test('testAllCollectedQueriesInSingleTransaction', () => testCase.testAllCollectedQueriesInSingleTransaction());
  test('testSequenceNumbersWithMutationAndSequentialQueries',
      () => testCase.testSequenceNumbersWithMutationAndSequentialQueries());
  test('testSequenceNumbersWithMutationsInQueries', () => testCase.testSequenceNumbersWithMutationsInQueries());
  test('testRemoveQueriesUpThroughSequenceNumber', () => testCase.testRemoveQueriesUpThroughSequenceNumber());
  test('testRemoveOrphanedDocuments', () => testCase.testRemoveOrphanedDocuments());
  test('testRemoveTargetsThenGC', () => testCase.testRemoveTargetsThenGC());
}
