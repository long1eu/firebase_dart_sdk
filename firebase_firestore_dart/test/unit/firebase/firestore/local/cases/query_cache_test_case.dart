// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_purpose.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';
import '../mock/database_mock.dart';

class QueryCacheTestCase {
  QueryCacheTestCase(this._persistence);

  final Persistence _persistence;

  QueryCache _queryCache;
  int _previousSequenceNumber;

  void setUp() {
    _queryCache = _persistence.queryCache;
    _previousSequenceNumber = 1000;
  }

  Future<void> tearDown() => _persistence.shutdown();

  @testMethod
  Future<void> testReadQueryNotInCache() async {
    expect(await _queryCache.getQueryData(query('rooms')), isNull);
  }

  @testMethod
  Future<void> testSetAndReadAQuery() async {
    final QueryData queryData = _newQueryData(query('rooms'), 1, 1);
    await _addQueryData(queryData);

    final QueryData result = await _queryCache.getQueryData(query('rooms'));
    expect(result, isNotNull);
    expect(result.query, queryData.query);
    expect(result.targetId, queryData.targetId);
    expect(result.resumeToken, queryData.resumeToken);
  }

  @testMethod
  Future<void> testCanonicalIdCollision() async {
    // Type information is currently lost in our canonicalID implementations so this currently an easy way to force
    // colliding canonicalIDs
    final Query q1 = query('a').filter(filter('foo', '==', 1));
    final Query q2 = query('a').filter(filter('foo', '==', '1'));
    expect(q2.canonicalId, q1.canonicalId);

    final QueryData data1 = _newQueryData(q1, 1, 1);
    await _addQueryData(data1);

    // Using the other query should not return the query cache entry despite equal canonicalIDs.
    expect(await _queryCache.getQueryData(q2), isNull);
    expect(await _queryCache.getQueryData(q1), data1);

    final QueryData data2 = _newQueryData(q2, 2, 1);
    await _addQueryData(data2);
    expect(_queryCache.targetCount, 2);

    expect(await _queryCache.getQueryData(q1), data1);
    expect(await _queryCache.getQueryData(q2), data2);

    await _removeQueryData(data1);
    expect(await _queryCache.getQueryData(q1), isNull);
    expect(await _queryCache.getQueryData(q2), data2);
    expect(_queryCache.targetCount, 1);

    await _removeQueryData(data2);
    expect(await _queryCache.getQueryData(q1), isNull);
    expect(await _queryCache.getQueryData(q2), isNull);
    expect(_queryCache.targetCount, 0);
  }

  @testMethod
  Future<void> testSetQueryToNewValue() async {
    final QueryData queryData1 = _newQueryData(query('rooms'), 1, 1);
    await _addQueryData(queryData1);

    final QueryData queryData2 = _newQueryData(query('rooms'), 1, 2);
    await _addQueryData(queryData2);

    final QueryData result = await _queryCache.getQueryData(query('rooms'));

    // There's no assertArrayNotEquals
    expect(queryData2.resumeToken, isNot(queryData1.resumeToken));
    expect(queryData2.snapshotVersion, isNot(queryData1.snapshotVersion));
    expect(result, isNotNull);
    expect(result.resumeToken, queryData2.resumeToken);
    expect(result.snapshotVersion, queryData2.snapshotVersion);
  }

  @testMethod
  Future<void> testRemoveQuery() async {
    final QueryData queryData1 = _newQueryData(query('rooms'), 1, 1);
    await _addQueryData(queryData1);

    await _removeQueryData(queryData1);

    final QueryData result = await _queryCache.getQueryData(query('rooms'));
    expect(result, isNull);
  }

  @testMethod
  Future<void> testRemoveNonExistentQuery() async {
    // no-op, but make sure it doesn't throw.
    try {
      await _queryCache.getQueryData(query('rooms'));
      expect(true, true);
    } catch (e) {
      assert(false, 'This should not thow');
    }
  }

  @testMethod
  Future<void> testRemoveQueryRemovesMatchingKeysToo() async {
    final QueryData rooms = _newQueryData(query('rooms'), 1, 1);
    await _addQueryData(rooms);

    final DocumentKey key1 = key('rooms/foo');
    final DocumentKey key2 = key('rooms/bar');
    await _addMatchingKey(key1, rooms.targetId);
    await _addMatchingKey(key2, rooms.targetId);

    expect(await _queryCache.containsKey(key1), isTrue);
    expect(await _queryCache.containsKey(key2), isTrue);

    await _removeQueryData(rooms);
    expect(await _queryCache.containsKey(key1), isFalse);
    expect(await _queryCache.containsKey(key2), isFalse);
  }

  @testMethod
  Future<void> testAddOrRemoveMatchingKeys() async {
    final DocumentKey _key = key('foo/bar');

    expect(await _queryCache.containsKey(_key), isFalse);

    await _addMatchingKey(_key, 1);
    expect(await _queryCache.containsKey(_key), isTrue);

    await _addMatchingKey(_key, 2);
    expect(await _queryCache.containsKey(_key), isTrue);

    await _removeMatchingKey(_key, 1);
    expect(await _queryCache.containsKey(_key), isTrue);

    await _removeMatchingKey(_key, 2);
    expect(await _queryCache.containsKey(_key), isFalse);
  }

  @testMethod
  Future<void> testRemoveMatchingKeysForTargetId() async {
    final DocumentKey key1 = key('foo/bar');
    final DocumentKey key2 = key('foo/baz');
    final DocumentKey key3 = key('foo/blah');

    await _addMatchingKey(key1, 1);
    await _addMatchingKey(key2, 1);
    await _addMatchingKey(key3, 2);
    expect(await _queryCache.containsKey(key1), isTrue);
    expect(await _queryCache.containsKey(key2), isTrue);
    expect(await _queryCache.containsKey(key3), isTrue);

    await _removeMatchingKeysForTargetId(1);
    expect(await _queryCache.containsKey(key1), isFalse);
    expect(await _queryCache.containsKey(key2), isFalse);
    expect(await _queryCache.containsKey(key3), isTrue);

    await _removeMatchingKeysForTargetId(2);
    expect(await _queryCache.containsKey(key1), isFalse);
    expect(await _queryCache.containsKey(key2), isFalse);
    expect(await _queryCache.containsKey(key3), isFalse);
  }

  @testMethod
  Future<void> testMatchingKeysForTargetID() async {
    final DocumentKey key1 = key('foo/bar');
    final DocumentKey key2 = key('foo/baz');
    final DocumentKey key3 = key('foo/blah');

    await _addMatchingKey(key1, 1);
    await _addMatchingKey(key2, 1);
    await _addMatchingKey(key3, 2);

    expect(await _queryCache.getMatchingKeysForTargetId(1), <DocumentKey>[key1, key2]);
    expect(await _queryCache.getMatchingKeysForTargetId(2), <DocumentKey>[key3]);

    await _addMatchingKey(key1, 2);
    expect(await _queryCache.getMatchingKeysForTargetId(1), <DocumentKey>[key1, key2]);
    expect(await _queryCache.getMatchingKeysForTargetId(2), <DocumentKey>[key1, key3]);
  }

  @testMethod
  Future<void> testHighestSequenceNumber() async {
    final Query rooms = query('rooms');
    final Query halls = query('halls');
    final Query garages = query('garages');

    final QueryData query1 = QueryData.init(rooms, 1, 10, QueryPurpose.listen);
    await _addQueryData(query1);
    final QueryData query2 = QueryData.init(halls, 2, 20, QueryPurpose.listen);
    await _addQueryData(query2);
    expect(_queryCache.highestListenSequenceNumber, 20);

    // Sequence numbers never come down
    await _removeQueryData(query2);
    expect(_queryCache.highestListenSequenceNumber, 20);

    final QueryData query3 = QueryData.init(garages, 42, 100, QueryPurpose.listen);
    await _addQueryData(query3);
    expect(_queryCache.highestListenSequenceNumber, 100);

    await _removeQueryData(query1);
    expect(_queryCache.highestListenSequenceNumber, 100);
    await _removeQueryData(query3);
    expect(_queryCache.highestListenSequenceNumber, 100);
  }

  @testMethod
  Future<void> testHighestTargetId() async {
    expect(_queryCache.highestTargetId, 0);

    final QueryData query1 = QueryData.init(query('rooms'), 1, 10, QueryPurpose.listen);
    await _addQueryData(query1);

    final DocumentKey key1 = key('rooms/bar');
    final DocumentKey key2 = key('rooms/foo');
    await _addMatchingKey(key1, 1);
    await _addMatchingKey(key2, 1);

    final QueryData query2 = QueryData.init(query('halls'), 2, 20, QueryPurpose.listen);
    await _addQueryData(query2);
    final DocumentKey key3 = key('halls/foo');
    await _addMatchingKey(key3, 2);
    expect(_queryCache.highestTargetId, 2);

    // TargetIDs never come down.
    await _removeQueryData(query2);
    expect(_queryCache.highestTargetId, 2);

    // A query with an empty result set still counts.
    final QueryData query3 = QueryData.init(query('garages'), 42, 100, QueryPurpose.listen);
    await _addQueryData(query3);
    expect(_queryCache.highestTargetId, 42);

    await _removeQueryData(query1);
    expect(_queryCache.highestTargetId, 42);

    await _removeQueryData(query3);
    expect(_queryCache.highestTargetId, 42);

    if (_persistence is SQLitePersistence) {
      // Verify that the highestTargetID even survives restarts.
      final SQLitePersistence sqLitePersistence = _persistence;
      final DatabaseMock databaseMock = sqLitePersistence.database;

      // ignore: cascade_invocations
      databaseMock.renamePath = false;
      await _persistence.shutdown();
      databaseMock.renamePath = true;
      await _persistence.start();
    } else {
      await _persistence.shutdown();
      await _persistence.start();
    }

    _queryCache = _persistence.queryCache;
    expect(_queryCache.highestTargetId, 42);
  }

  @testMethod
  Future<void> testSnapshotVersion() async {
    expect(_queryCache.lastRemoteSnapshotVersion, SnapshotVersion.none);

    // Can set the snapshot version.
    await _queryCache.setLastRemoteSnapshotVersion(version(42));
    expect(_queryCache.lastRemoteSnapshotVersion, version(42));

    // Snapshot version persists restarts.
    if (_persistence is SQLitePersistence) {
      final SQLitePersistence sqLitePersistence = _persistence;
      final DatabaseMock databaseMock = sqLitePersistence.database;

      // ignore: cascade_invocations
      databaseMock.renamePath = false;
      await _persistence.shutdown();
      databaseMock.renamePath = true;
      await _persistence.start();
    } else {
      await _persistence.shutdown();
      await _persistence.start();
    }

    _queryCache = _persistence.queryCache;
    expect(_queryCache.lastRemoteSnapshotVersion, version(42));
  }

  /// Creates a new [QueryData] object from the the given parameters, synthesizing a resume token from the snapshot
  /// version.
  QueryData _newQueryData(Query query, int targetId, int theVersion) {
    final int sequenceNumber = ++_previousSequenceNumber;
    return QueryData(
        query, targetId, sequenceNumber, QueryPurpose.listen, version(theVersion), resumeToken(theVersion));
  }

  /// Adds the given query data to the [_queryCache] under test, committing immediately.
  Future<QueryData> _addQueryData(QueryData queryData) async {
    await _persistence.runTransaction('addQueryData', () => _queryCache.addQueryData(queryData));
    return queryData;
  }

  /// Removes the given query data from the queryCache under test, committing immediately.
  Future<void> _removeQueryData(QueryData queryData) async {
    await _persistence.runTransaction('removeQueryData', () => _queryCache.removeQueryData(queryData));
  }

  Future<void> _addMatchingKey(DocumentKey key, int targetId) async {
    final ImmutableSortedSet<DocumentKey> keys = DocumentKey.emptyKeySet.insert(key);

    await _persistence.runTransaction('addMatchingKeys', () => _queryCache.addMatchingKeys(keys, targetId));
  }

  Future<void> _removeMatchingKey(DocumentKey key, int targetId) async {
    final ImmutableSortedSet<DocumentKey> keys = DocumentKey.emptyKeySet.insert(key);

    await _persistence.runTransaction('removeMatchingKeys', () => _queryCache.removeMatchingKeys(keys, targetId));
  }

  Future<void> _removeMatchingKeysForTargetId(int targetId) async {
    await _persistence.runTransaction('removeReferencesForTargetId',
        () async => _queryCache.removeMatchingKeys(await _queryCache.getMatchingKeysForTargetId(targetId), targetId));
  }
}
