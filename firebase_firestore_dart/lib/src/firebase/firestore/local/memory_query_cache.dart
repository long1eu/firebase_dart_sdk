// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/local_serializer.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// An implementation of the [QueryCache] protocol that merely keeps queries in memory, suitable for online only clients
/// with persistence disabled.
class MemoryQueryCache implements QueryCache {
  MemoryQueryCache(this.persistence);

  /// Maps a query to the data about that query.
  final Map<Query, QueryData> queries = <Query, QueryData>{};

  /// A ordered bidirectional mapping between documents and the remote target ids.
  final ReferenceSet references = ReferenceSet();

  /// The highest numbered target id encountered.
  @override
  int highestTargetId = 0;

  /// The last received snapshot version.
  @override
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  int highestSequenceNumber = 0;

  final MemoryPersistence persistence;

  @override
  int get targetCount => queries.length;

  @override
  Future<void> forEachTarget(Consumer<QueryData> consumer) async {
    queries.values.forEach(consumer);
  }

  @override
  int get highestListenSequenceNumber => highestSequenceNumber;

  @override
  Future<void> setLastRemoteSnapshotVersion(SnapshotVersion snapshotVersion) async {
    lastRemoteSnapshotVersion = snapshotVersion;
  }

  // Query tracking

  @override
  Future<void> addQueryData(QueryData queryData) async {
    queries[queryData.query] = queryData;
    final int targetId = queryData.targetId;
    if (targetId > highestTargetId) {
      highestTargetId = targetId;
    }
    if (queryData.sequenceNumber > highestSequenceNumber) {
      highestSequenceNumber = queryData.sequenceNumber;
    }
  }

  @override
  Future<void> updateQueryData(QueryData queryData) async {
    // Memory persistence doesn't need to do anything different between add and remove.
    return addQueryData(queryData);
  }

  @override
  Future<void> removeQueryData(QueryData queryData) async {
    queries.remove(queryData.query);
    references.removeReferencesForId(queryData.targetId);
  }

  /// Drops any targets with sequence number less than or equal to the upper bound, excepting those present in
  /// [activeTargetIds]. Document associations for the removed targets are also removed.
  int removeQueries(int upperBound, Set<int> activeTargetIds) {
    int removed = 0;
    queries.removeWhere((Query query, QueryData queryData) {
      final int targetId = queryData.targetId;
      final int sequenceNumber = queryData.sequenceNumber;

      if (sequenceNumber <= upperBound && !activeTargetIds.contains(targetId)) {
        _removeMatchingKeysForTargetId(targetId);
        removed++;
        return true;
      }
      return false;
    });

    return removed;
  }

  @override
  Future<QueryData> getQueryData(Query query) async => queries[query];

  // Reference tracking

  @override
  Future<void> addMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    references.addReferences(keys, targetId);
    final ReferenceDelegate referenceDelegate = persistence.referenceDelegate;

    for (DocumentKey key in keys) {
      await referenceDelegate.addReference(key);
    }
  }

  @override
  Future<void> removeMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) async {
    references.removeReferences(keys, targetId);
    final ReferenceDelegate referenceDelegate = persistence.referenceDelegate;

    for (DocumentKey key in keys) {
      await referenceDelegate.removeReference(key);
    }
  }

  void _removeMatchingKeysForTargetId(int targetId) {
    references.removeReferencesForId(targetId);
  }

  @override
  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(int targetId) async {
    return references.referencesForId(targetId);
  }

  @override
  Future<bool> containsKey(DocumentKey key) async => references.containsKey(key);

  int getByteSize(LocalSerializer serializer) {
    int count = 0;
    for (QueryData value in queries.values) {
      count += serializer.encodeQueryData(value).writeToBuffer().length;
    }
    return count;
  }
}
