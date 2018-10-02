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
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

import '../../../../util/test_util.dart';

class QueryCacheTestCase {
  final Persistence persistence;
  QueryCache queryCache;
  int previousSequenceNumber;

  QueryCacheTestCase(this.persistence);

  void setUp() {
    queryCache = persistence.queryCache;
    previousSequenceNumber = 1000;
  }

  Future<void> tearDown() => persistence.shutdown();

  /// Creates a new [QueryData] object from the the given parameters,
  /// synthesizing a resume token from the snapshot version.
  QueryData newQueryData(Query query, int targetId, int version) {
    final int sequenceNumber = ++previousSequenceNumber;
    return QueryData(query, targetId, sequenceNumber, QueryPurpose.listen,
        TestUtil.version(version), resumeToken(version));
  }

  /// Adds the given query data to the [queryCache] under test, committing
  /// immediately.
  Future<QueryData> addQueryData(QueryData queryData) async {
    await persistence.runTransaction(
        'addQueryData', () => queryCache.addQueryData(queryData));
    return queryData;
  }

  /// Removes the given query data from the queryCache under test, committing
  /// immediately.
  Future<void> removeQueryData(QueryData queryData) async {
    await persistence.runTransaction(
        'removeQueryData', () => queryCache.removeQueryData(queryData));
  }

  Future<void> addMatchingKey(DocumentKey key, int targetId) async {
    final ImmutableSortedSet<DocumentKey> keys =
        DocumentKey.emptyKeySet.insert(key);

    await persistence.runTransaction(
        'addMatchingKeys', () => queryCache.addMatchingKeys(keys, targetId));
  }

  Future<void> removeMatchingKey(DocumentKey key, int targetId) async {
    final ImmutableSortedSet<DocumentKey> keys =
        DocumentKey.emptyKeySet.insert(key);

    await persistence.runTransaction('removeMatchingKeys',
        () => queryCache.removeMatchingKeys(keys, targetId));
  }

  Future<void> removeMatchingKeysForTargetId(int targetId) async {
    await persistence.runTransaction(
        'removeReferencesForTargetId',
        () async => queryCache.removeMatchingKeys(
            await queryCache.getMatchingKeysForTargetId(targetId), targetId));
  }
}

// ignore: always_specify_types
const version = TestUtil.version;
// ignore: always_specify_types
const resumeToken = TestUtil.resumeToken;
