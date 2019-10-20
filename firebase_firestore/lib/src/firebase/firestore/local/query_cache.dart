// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/query_data.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/types.dart';

/// Represents cached queries received from the remote backend. This contains both a mapping between
/// queries and the documents that matched them according to the server, but also metadata about the
/// queries.
///
/// The cache is keyed by [Query] and entries in the cache are [QueryData] instances.
abstract class QueryCache {
  /// Returns the highest target id of any query in the cache. Typically called during startup to
  /// seed a target id generator and avoid collisions with existing queries. If there are no queries
  /// in the cache, returns zero.
  int get highestTargetId;

  /// Returns the highest sequence number that the cache has seen. This includes targets that have
  /// been persisted in a previous run of the client.
  int get highestListenSequenceNumber;

  /// Returns the number of targets in the cache.
  int get targetCount;

  /// Call the consumer for each target in the cache.
  Future<void> forEachTarget(Consumer<QueryData> consumer);

  /// A global snapshot version representing the last consistent snapshot we received from the
  /// backend. This is monotonically increasing and any snapshots received from the backend prior to
  /// this version (e.g. for targets resumed with a 'resume_token') should be suppressed (buffered)
  /// until the backend has caught up to this snapshot version again. This prevents our cache from
  /// ever going backwards in time.
  ///
  /// This is updated whenever we get a [TargetChange] with a 'read_time' and empty 'target_ids'.
  SnapshotVersion get lastRemoteSnapshotVersion;

  /// Set the snapshot version representing the last consistent snapshot received from the backend.
  /// (see [lastRemoteSnapshotVersion] for more details).
  Future<void> setLastRemoteSnapshotVersion(SnapshotVersion snapshotVersion);

  /// Adds an entry in the cache. This entry should not already exist.
  ///
  /// The cache key is extracted from [QueryData.query].
  Future<void> addQueryData(QueryData queryData);

  /// Replaces an entry in the cache. An entry with the same key should already exist.
  ///
  /// The cache key is extracted from [QueryData.query].
  Future<void> updateQueryData(QueryData queryData);

  /// Removes the cached entry for the given query data. This entry should already exist in the
  /// cache. This method exists in the interface for testing purposes. Production code should
  /// instead call [ReferenceDelegate.removeTarget].
  Future<void> removeQueryData(QueryData queryData);

  /// Looks up a [QueryData] entry in the cache.
  ///
  /// The [query] corresponding to the entry to look up. Returns the cached [QueryData] entry, or
  /// null if the cache has no entry for the query.
  Future<QueryData> getQueryData(Query query);

  /// Adds the given document [keys] to cached query results of the given [targetId].
  Future<void> addMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId);

  /// Removes the given document [keys] from the cached query results of the given [targetId].
  Future<void> removeMatchingKeys(ImmutableSortedSet<DocumentKey> keys, int targetId);

  Future<ImmutableSortedSet<DocumentKey>> getMatchingKeysForTargetId(int targetId);

  /// Returns true if the document is part of any target
  Future<bool> containsKey(DocumentKey key);
}
