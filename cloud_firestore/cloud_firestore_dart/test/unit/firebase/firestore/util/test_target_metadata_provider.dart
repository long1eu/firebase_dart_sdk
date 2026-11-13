// File created by
// Lung Razvan <long1eu>
// on 22/03/2020

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change_aggregator.dart';

TestTargetMetadataProvider get testTargetMetadataProvider {
  final Map<int, ImmutableSortedSet<DocumentKey>> syncedKeys =
      <int, ImmutableSortedSet<DocumentKey>>{};
  final Map<int, QueryData> queryDataMap = <int, QueryData>{};

  late final TestTargetMetadataProvider provider;
  provider = TestTargetMetadataProvider(
    syncedKeys,
    queryDataMap,
    getQueryDataForTarget: (int targetId) => queryDataMap[targetId],
    getRemoteKeysForTarget: (int targetId) =>
        syncedKeys[targetId] ?? DocumentKey.emptyKeySet,
    getDatabaseId: () => provider.databaseId,
  );
  return provider;
}

/// An implementation of [TargetMetadataProvider] that provides controlled
/// access to the [TargetMetadataProvider] callbacks. Any target accessed via
/// these callbacks must be registered beforehand via [setSyncedKeys].
class TestTargetMetadataProvider extends TargetMetadataProvider {
  TestTargetMetadataProvider(this.syncedKeys, this.queryDataMap,
      {required super.getRemoteKeysForTarget,
      required super.getQueryDataForTarget,
      required super.getDatabaseId});

  /// The database id reported to the aggregator.
  DatabaseId databaseId = DatabaseId.forDatabase('p', 'd');

  /// Overrides the database id reported to the aggregator.
  void setDatabaseId(String projectId, String databaseId) {
    this.databaseId = DatabaseId.forDatabase(projectId, databaseId);
  }

  final Map<int, ImmutableSortedSet<DocumentKey>> syncedKeys;

  final Map<int, QueryData> queryDataMap;

  /// Sets or replaces the local state for the provided query data.
  void setSyncedKeys(
      QueryData queryData, ImmutableSortedSet<DocumentKey> keys) {
    queryDataMap[queryData.targetId] = queryData;
    syncedKeys[queryData.targetId] = keys;
  }
}
