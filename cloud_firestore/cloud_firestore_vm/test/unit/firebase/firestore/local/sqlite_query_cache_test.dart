// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'cases/query_cache_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  QueryCacheTestCase testCase;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence = await openSQLitePersistence(
        'firebase/firestore/local/sqlite_query_cache_test-${Uuid().v4()}.db');
    testCase = QueryCacheTestCase(persistence)..setUp();
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase.tearDown()));

  test('testReadQueryNotInCache', () => testCase.testReadQueryNotInCache());
  test('testSetAndReadAQuery', () => testCase.testSetAndReadAQuery());
  test('testCanonicalIdCollision', () => testCase.testCanonicalIdCollision());
  test('testSetQueryToNewValue', () => testCase.testSetQueryToNewValue());
  test('testRemoveQuery', () => testCase.testRemoveQuery());
  test('testRemoveNonExistentQuery',
      () => testCase.testRemoveNonExistentQuery());
  test('testRemoveQueryRemovesMatchingKeysToo',
      () => testCase.testRemoveQueryRemovesMatchingKeysToo());
  test('testAddOrRemoveMatchingKeys',
      () => testCase.testAddOrRemoveMatchingKeys());
  test('testRemoveMatchingKeysForTargetId',
      () => testCase.testRemoveMatchingKeysForTargetId());
  test('testMatchingKeysForTargetID',
      () => testCase.testMatchingKeysForTargetID());
  test('testHighestSequenceNumber', () => testCase.testHighestSequenceNumber());
  test('testHighestTargetId', () => testCase.testHighestTargetId());
  test('testSnapshotVersion', () => testCase.testSnapshotVersion());
}
