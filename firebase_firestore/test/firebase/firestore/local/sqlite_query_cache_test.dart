// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';
import 'cases/query_cache_test_case.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

void main() {
  QueryCacheTestCase testCase;
  QueryCache queryCache;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence =
        await PersistenceTestHelpers.openSQLitePersistence(
            'firebase/firestore/local/sqlite_query_cache_${PersistenceTestHelpers.nextSQLiteDatabaseName()}.db');

    testCase = QueryCacheTestCase(persistence);
    testCase.setUp();

    queryCache = testCase.queryCache;
    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase.tearDown()));

  test('testReadQueryNotInCache', () async {
    expect(await queryCache.getQueryData(query('rooms')), isNull);
  });

  test('testSetAndReadAQuery', () async {
    final QueryData queryData = testCase.newQueryData(query('rooms'), 1, 1);
    await testCase.addQueryData(queryData);

    final QueryData result = await queryCache.getQueryData(query('rooms'));
    expect(result, isNotNull);
    expect(result.query, queryData.query);
    expect(result.targetId, queryData.targetId);
    expect(result.resumeToken, queryData.resumeToken);
  });

  test('testCanonicalIdCollision', () async {
    // Type information is currently lost in our canonicalID implementations so
    // this currently an easy way to force colliding canonicalIDs
    final Query q1 = query('a').filter(filter('foo', '==', 1));
    final Query q2 = query('a').filter(filter('foo', '==', '1'));
    expect(q2.canonicalId, q1.canonicalId);

    final QueryData data1 = testCase.newQueryData(q1, 1, 1);
    await testCase.addQueryData(data1);

    // Using the other query should not return the query cache entry despite
    // equal canonicalIDs.
    expect(await queryCache.getQueryData(q2), isNull);
    expect(await queryCache.getQueryData(q1), data1);

    final QueryData data2 = testCase.newQueryData(q2, 2, 1);
    await testCase.addQueryData(data2);
    expect(queryCache.targetCount, 2);

    expect(await queryCache.getQueryData(q1), data1);
    expect(await queryCache.getQueryData(q2), data2);

    await testCase.removeQueryData(data1);
    expect(await queryCache.getQueryData(q1), isNull);
    expect(await queryCache.getQueryData(q2), data2);
    expect(queryCache.targetCount, 1);

    await testCase.removeQueryData(data2);
    expect(await queryCache.getQueryData(q1), isNull);
    expect(await queryCache.getQueryData(q2), isNull);
    expect(queryCache.targetCount, 0);
  });

  test('testSetQueryToNewValue', () async {
    final QueryData queryData1 = testCase.newQueryData(query('rooms'), 1, 1);
    await testCase.addQueryData(queryData1);

    final QueryData queryData2 = testCase.newQueryData(query('rooms'), 1, 2);
    await testCase.addQueryData(queryData2);

    final QueryData result = await queryCache.getQueryData(query('rooms'));

    // There's no assertArrayNotEquals
    expect(queryData2.resumeToken, isNot(queryData1.resumeToken));
    expect(queryData2.snapshotVersion, isNot(queryData1.snapshotVersion));
    expect(result, isNotNull);
    expect(result.resumeToken, queryData2.resumeToken);
    expect(result.snapshotVersion, queryData2.snapshotVersion);
  });

  test('testRemoveQuery', () async {
    final QueryData queryData1 = testCase.newQueryData(query('rooms'), 1, 1);
    await testCase.addQueryData(queryData1);

    await testCase.removeQueryData(queryData1);

    final QueryData result = await queryCache.getQueryData(query('rooms'));
    expect(result, isNull);
  });

  test('testRemoveNonExistentQuery', () {
    // no-op, but make sure it doesn't throw.
    try {
      queryCache.getQueryData(query('rooms'));
      expect(true, true);
    } catch (e) {
      assert(false, 'This should not thow');
    }
  });

  test('testRemoveQueryRemovesMatchingKeysToo', () async {
    final QueryData rooms = testCase.newQueryData(query('rooms'), 1, 1);
    await testCase.addQueryData(rooms);

    final DocumentKey key1 = key('rooms/foo');
    final DocumentKey key2 = key('rooms/bar');
    await testCase.addMatchingKey(key1, rooms.targetId);
    await testCase.addMatchingKey(key2, rooms.targetId);

    expect(await queryCache.containsKey(key1), isTrue);
    expect(await queryCache.containsKey(key2), isTrue);

    await testCase.removeQueryData(rooms);
    expect(await queryCache.containsKey(key1), isFalse);
    expect(await queryCache.containsKey(key2), isFalse);
  });

  test('testAddOrRemoveMatchingKeys', () async {
    final DocumentKey key = TestUtil.key('foo/bar');

    expect(await queryCache.containsKey(key), isFalse);

    await testCase.addMatchingKey(key, 1);
    expect(await queryCache.containsKey(key), isTrue);

    await testCase.addMatchingKey(key, 2);
    expect(await queryCache.containsKey(key), isTrue);

    await testCase.removeMatchingKey(key, 1);
    expect(await queryCache.containsKey(key), isTrue);

    await testCase.removeMatchingKey(key, 2);
    expect(await queryCache.containsKey(key), isFalse);
  });

  test('testRemoveMatchingKeysForTargetId', () async {
    final DocumentKey key1 = key('foo/bar');
    final DocumentKey key2 = key('foo/baz');
    final DocumentKey key3 = key('foo/blah');

    await testCase.addMatchingKey(key1, 1);
    await testCase.addMatchingKey(key2, 1);
    await testCase.addMatchingKey(key3, 2);
    expect(await queryCache.containsKey(key1), isTrue);
    expect(await queryCache.containsKey(key2), isTrue);
    expect(await queryCache.containsKey(key3), isTrue);

    await testCase.removeMatchingKeysForTargetId(1);
    expect(await queryCache.containsKey(key1), isFalse);
    expect(await queryCache.containsKey(key2), isFalse);
    expect(await queryCache.containsKey(key3), isTrue);

    await testCase.removeMatchingKeysForTargetId(2);
    expect(await queryCache.containsKey(key1), isFalse);
    expect(await queryCache.containsKey(key2), isFalse);
    expect(await queryCache.containsKey(key3), isFalse);
  });

  test('testMatchingKeysForTargetID', () async {
    final DocumentKey key1 = key('foo/bar');
    final DocumentKey key2 = key('foo/baz');
    final DocumentKey key3 = key('foo/blah');

    await testCase.addMatchingKey(key1, 1);
    await testCase.addMatchingKey(key2, 1);
    await testCase.addMatchingKey(key3, 2);

    expect(await queryCache.getMatchingKeysForTargetId(1),
        <DocumentKey>[key1, key2]);
    expect(await queryCache.getMatchingKeysForTargetId(2), <DocumentKey>[key3]);

    await testCase.addMatchingKey(key1, 2);
    expect(await queryCache.getMatchingKeysForTargetId(1),
        <DocumentKey>[key1, key2]);
    expect(await queryCache.getMatchingKeysForTargetId(2),
        <DocumentKey>[key1, key3]);
  });

  test('testHighestSequenceNumber', () async {
    final Query rooms = query('rooms');
    final Query halls = query('halls');
    final Query garages = query('garages');

    final QueryData query1 = QueryData.init(rooms, 1, 10, QueryPurpose.listen);
    await testCase.addQueryData(query1);
    final QueryData query2 = QueryData.init(halls, 2, 20, QueryPurpose.listen);
    await testCase.addQueryData(query2);
    expect(queryCache.highestListenSequenceNumber, 20);

    // Sequence numbers never come down
    await testCase.removeQueryData(query2);
    expect(queryCache.highestListenSequenceNumber, 20);

    final QueryData query3 =
        QueryData.init(garages, 42, 100, QueryPurpose.listen);
    await testCase.addQueryData(query3);
    expect(queryCache.highestListenSequenceNumber, 100);

    await testCase.removeQueryData(query1);
    expect(queryCache.highestListenSequenceNumber, 100);
    await testCase.removeQueryData(query3);
    expect(queryCache.highestListenSequenceNumber, 100);
  });

  test('testHighestTargetId', () async {
    expect(queryCache.highestTargetId, 0);

    final QueryData query1 =
        QueryData.init(query('rooms'), 1, 10, QueryPurpose.listen);
    await testCase.addQueryData(query1);

    final DocumentKey key1 = key('rooms/bar');
    final DocumentKey key2 = key('rooms/foo');
    await testCase.addMatchingKey(key1, 1);
    await testCase.addMatchingKey(key2, 1);

    final QueryData query2 =
        QueryData.init(query('halls'), 2, 20, QueryPurpose.listen);
    await testCase.addQueryData(query2);
    final DocumentKey key3 = key('halls/foo');
    await testCase.addMatchingKey(key3, 2);
    expect(queryCache.highestTargetId, 2);

    // TargetIDs never come down.
    await testCase.removeQueryData(query2);
    expect(queryCache.highestTargetId, 2);

    // A query with an empty result set still counts.
    final QueryData query3 =
        QueryData.init(query('garages'), 42, 100, QueryPurpose.listen);
    await testCase.addQueryData(query3);
    expect(queryCache.highestTargetId, 42);

    await testCase.removeQueryData(query1);
    expect(queryCache.highestTargetId, 42);

    await testCase.removeQueryData(query3);
    expect(queryCache.highestTargetId, 42);

    // Verify that the highestTargetID even survives restarts.
    final SQLitePersistence sqLitePersistence = testCase.persistence;
    final DatabaseMock databaseMock = sqLitePersistence.database;

    databaseMock.renamePath = false;
    await testCase.persistence.shutdown();
    databaseMock.renamePath = true;
    await testCase.persistence.start();

    queryCache = testCase.persistence.queryCache;
    expect(queryCache.highestTargetId, 42);
  });

  test('testSnapshotVersion', () async {
    expect(queryCache.lastRemoteSnapshotVersion, SnapshotVersion.none);

    // Can set the snapshot version.
    await queryCache.setLastRemoteSnapshotVersion(version(42));
    expect(queryCache.lastRemoteSnapshotVersion, version(42));

    // Snapshot version persists restarts.

    final SQLitePersistence sqLitePersistence = testCase.persistence;
    final DatabaseMock databaseMock = sqLitePersistence.database;

    databaseMock.renamePath = false;
    await testCase.persistence.shutdown();
    databaseMock.renamePath = true;
    await testCase.persistence.start();
    queryCache = testCase.persistence.queryCache;
    expect(queryCache.lastRemoteSnapshotVersion, version(42));
  });
}

// ignore: always_specify_types
const query = TestUtil.query;
// ignore: always_specify_types
const filter = TestUtil.filter;
// ignore: always_specify_types
const key = TestUtil.key;
