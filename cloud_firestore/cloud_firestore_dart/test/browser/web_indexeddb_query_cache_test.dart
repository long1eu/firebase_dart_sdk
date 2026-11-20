// The shared query cache suite of test/unit/firebase/firestore/local (the list of keyvalue_query_cache_test.dart) on the
// IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_query_cache_test.dart

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/indexeddb_persistence_web.dart'
    show WebIndexedDbPersistence;
import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import 'indexeddb_test_persistence.dart';

import '../util/test_util.dart';
import '../unit/firebase/firestore/local/cases/query_cache_test_case.dart';

void main() {
  late QueryCacheTestCase testCase;

  setUp(() async {
    print('setUp');
    final WebIndexedDbPersistence persistence =
        await newIndexedDbTestPersistence();
    testCase = QueryCacheTestCase(persistence)..setUp();
    print('setUpDone');
  });

  tearDown(
    () => Future<void>.delayed(
      const Duration(milliseconds: 250),
      () => testCase.tearDown(),
    ),
  );

  test('testReadQueryNotInCache', () => testCase.testReadQueryNotInCache());
  test('testSetAndReadAQuery', () => testCase.testSetAndReadAQuery());
  test('testCanonicalIdCollision', () => testCase.testCanonicalIdCollision());
  test(
    'testLimitToLastQueriesAreKeyedByTarget',
    () => testCase.testLimitToLastQueriesAreKeyedByTarget(),
  );
  test('testSetQueryToNewValue', () => testCase.testSetQueryToNewValue());
  test('testRemoveQuery', () => testCase.testRemoveQuery());
  test(
    'testRemoveNonExistentQuery',
    () => testCase.testRemoveNonExistentQuery(),
  );
  test(
    'testRemoveQueryRemovesMatchingKeysToo',
    () => testCase.testRemoveQueryRemovesMatchingKeysToo(),
  );
  test(
    'testAddOrRemoveMatchingKeys',
    () => testCase.testAddOrRemoveMatchingKeys(),
  );
  test(
    'testRemoveMatchingKeysForTargetId',
    () => testCase.testRemoveMatchingKeysForTargetId(),
  );
  test(
    'testMatchingKeysForTargetID',
    () => testCase.testMatchingKeysForTargetID(),
  );
  test('testHighestSequenceNumber', () => testCase.testHighestSequenceNumber());
  test('testHighestTargetId', () => testCase.testHighestTargetId());
  test('testSnapshotVersion', () => testCase.testSnapshotVersion());

  // SQLiteTargetCacheTest, on a database that a second persistence opens again.
  test('testMetadataPersistedAcrossRestarts', () async {
    final String key = newIndexedDbPersistenceKey();
    final WebIndexedDbPersistence db1 = await newIndexedDbTestPersistence(
      persistenceKey: key,
    );
    final QueryCache targetCache1 = db1.queryCache;
    expect(targetCache1.highestListenSequenceNumber, 0);

    const int originalSequenceNumber = 1234;
    const int targetId = 5;
    final SnapshotVersion snapshotVersion = SnapshotVersion(Timestamp(1, 2));

    final QueryData targetData = QueryData(
      query('rooms').toTarget(),
      targetId,
      originalSequenceNumber,
      QueryPurpose.listen,
    );
    await db1.runTransaction('add query data', () async {
      await targetCache1.addQueryData(targetData);
      await targetCache1.setLastRemoteSnapshotVersion(snapshotVersion);
    });
    await db1.shutdown();

    final WebIndexedDbPersistence db2 = await newIndexedDbTestPersistence(
      persistenceKey: key,
    );
    await db2.runTransaction('verify sequence number', () async {
      final int newSequenceNumber = db2.referenceDelegate.currentSequenceNumber;
      expect(newSequenceNumber, greaterThan(originalSequenceNumber));
    });
    final QueryCache targetCache2 = db2.queryCache;
    expect(targetCache2.highestTargetId, targetId);
    expect(targetCache2.lastRemoteSnapshotVersion, snapshotVersion);
    expect(targetCache2.targetCount, 1);
    await db2.shutdown();
  });
}
