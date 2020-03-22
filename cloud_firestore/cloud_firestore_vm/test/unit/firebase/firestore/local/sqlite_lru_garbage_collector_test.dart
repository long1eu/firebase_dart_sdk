// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'cases/lru_garbage_collector_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  LruGarbageCollectorTestCase testCase;

  setUp(() async {
    print('setUp');

    testCase = LruGarbageCollectorTestCase((LruGarbageCollectorParams param) =>
        createSQLitePersistence(
            'firebase/firestore/local/sqlite_lru_garbage_collector_test-${Uuid().v4()}.db',
            param));
    await testCase.setUp();

    print('setUpDone');
  });

  tearDown(() {
    return Future<void>.delayed(const Duration(milliseconds: 250), () async {
      await testCase.tearDown();
      testCase = null;
    });
  });

  test('testPickSequenceNumberPercentile',
      () => testCase.testPickSequenceNumberPercentile());
  test('testSequenceNumberNoQueries',
      () => testCase.testSequenceNumberNoQueries());
  test('testSequenceNumberForFiftyQueries',
      () => testCase.testSequenceNumberForFiftyQueries());
  test('testSequenceNumberForMultipleQueriesInATransaction',
      () => testCase.testSequenceNumberForMultipleQueriesInATransaction());
  test('testAllCollectedQueriesInSingleTransaction',
      () => testCase.testAllCollectedQueriesInSingleTransaction());
  test('testSequenceNumbersWithMutationAndSequentialQueries',
      () => testCase.testSequenceNumbersWithMutationAndSequentialQueries());
  test('testSequenceNumbersWithMutationsInQueries',
      () => testCase.testSequenceNumbersWithMutationsInQueries());
  test('testRemoveQueriesUpThroughSequenceNumber',
      () => testCase.testRemoveQueriesUpThroughSequenceNumber());
  test('testRemoveOrphanedDocuments',
      () => testCase.testRemoveOrphanedDocuments());
  test('testRemoveTargetsThenGC', () => testCase.testRemoveTargetsThenGC());
  test('testGetsSize', () => testCase.testGetsSize());
  test('testDisabled', () => testCase.testDisabled());
  test('testCacheTooSmall', () => testCase.testCacheTooSmall());
  test('testGCRan', () => testCase.testGCRan());
}
