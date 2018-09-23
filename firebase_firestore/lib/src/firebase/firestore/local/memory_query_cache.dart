// File created by
// Lung Razvan <int1eu>
// on 21/09/2018

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_set.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// An implementation of the [QueryCache] protocol that merely keeps queries in
/// memory, suitable for online only clients with persistence disabled.
class MemoryQueryCache implements QueryCache {
  /// Maps a query to the data about that query.
  final Map<Query, QueryData> queries = <Query, QueryData>{};

  /// A ordered bidirectional mapping between documents and the remote target
  /// ids.
  final ReferenceSet references = new ReferenceSet();

  /// The highest numbered target id encountered.
  @override
  int highestTargetId;

  /// The last received snapshot version.
  SnapshotVersion lastRemoteSnapshotVersion = SnapshotVersion.none;

  int highestSequenceNumber = 0;

  final MemoryPersistence persistence;

  MemoryQueryCache(this.persistence);

  @override
  int get targetCount => queries.length;

  @override
  void forEachTarget(Consumer<QueryData> consumer) {
    for (QueryData queryData in queries.values) {
      consumer(queryData);
    }
  }

  @override
  int get highestListenSequenceNumber => highestSequenceNumber;

  @override
  void setLastRemoteSnapshotVersion(SnapshotVersion snapshotVersion) {
    lastRemoteSnapshotVersion = snapshotVersion;
  }

  // Query tracking

  @override
  void addQueryData(QueryData queryData) {
    queries[queryData.query] = queryData;
    int targetId = queryData.targetId;
    if (targetId > highestTargetId) {
      highestTargetId = targetId;
    }
    if (queryData.sequenceNumber > highestSequenceNumber) {
      highestSequenceNumber = queryData.sequenceNumber;
    }
  }

  @override
  void updateQueryData(QueryData queryData) {
    // Memory persistence doesn't need to do anything different between add and
    // remove.
    addQueryData(queryData);
  }

  @override
  void removeQueryData(QueryData queryData) {
    queries.remove(queryData.query);
    references.removeReferencesForId(queryData.targetId);
  }

  /// Drops any targets with sequence number less than or equal to the upper
  /// bound, excepting those present in [activeTargetIds]. Document associations
  /// for the removed targets are also removed.
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
    });

    return removed;
  }

  @override
  QueryData getQueryData(Query query) => queries[query];

  // Reference tracking

  @override
  void addMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) {
    references.addReferences(keys, targetId);
    ReferenceDelegate referenceDelegate = persistence.referenceDelegate;
    for (DocumentKey key in keys) {
      referenceDelegate.addReference(key);
    }
  }

  @override
  void removeMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId) {
    references.removeReferences(keys, targetId);
    ReferenceDelegate referenceDelegate = persistence.referenceDelegate;
    for (DocumentKey key in keys) {
      referenceDelegate.removeReference(key);
    }
  }

  void _removeMatchingKeysForTargetId(int targetId) {
    references.removeReferencesForId(targetId);
  }

  @override
  ImmutableSortedSet<DocumentKey> getMatchingKeysForTargetId(int targetId) {
    return references.referencesForId(targetId);
  }

  @override
  bool containsKey(DocumentKey key) => references.containsKey(key);
}
