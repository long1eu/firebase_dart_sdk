// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/query_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import 'cases/query_cache_test_case.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

void main() {
  late QueryCacheTestCase testCase;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence = await createSQLitePersistence(
      'firebase/firestore/local/sqlite_query_cache_test-${const Uuid().v4()}.db',
    );
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

  // SQLiteTargetCacheTest
  test('testMetadataPersistedAcrossRestarts', () async {
    final String name =
        'firebase/firestore/local/test-targetCache-restarts-${const Uuid().v4()}.db';

    final SQLitePersistence db1 = await createSQLitePersistence(name);
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

    // Keep the database file for the second instance.
    (db1.database as DatabaseMock).renamePath = false;
    await db1.shutdown();

    final SQLitePersistence db2 = await createSQLitePersistence(name);
    (db2.database as DatabaseMock).renamePath = false;
    await db2.runTransaction('verify sequence number', () async {
      final int newSequenceNumber = db2.referenceDelegate.currentSequenceNumber;
      expect(newSequenceNumber, greaterThan(originalSequenceNumber));
    });
    final QueryCache targetCache2 = db2.queryCache;
    expect(targetCache2.highestTargetId, targetId);
    expect(targetCache2.lastRemoteSnapshotVersion, snapshotVersion);
    expect(targetCache2.targetCount, 1);
    await db2.shutdown();
    DatabaseMock.deleteDatabaseFiles(name);
  });
}
