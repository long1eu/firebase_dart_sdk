// File created by
// Lung Razvan <long1eu>
// on 22/03/2020

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/target_data.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/watch_change_aggregator.dart';
import 'package:meta/meta.dart';

TestTargetMetadataProvider get testTargetMetadataProvider {
  final Map<int, ImmutableSortedSet<DocumentKey>> syncedKeys =
      <int, ImmutableSortedSet<DocumentKey>>{};
  final Map<int, TargetData> queryDataMap = <int, TargetData>{};

  return TestTargetMetadataProvider(
    syncedKeys,
    queryDataMap,
    getQueryDataForTarget: (int targetId) => queryDataMap[targetId],
    getRemoteKeysForTarget: (int targetId) =>
        syncedKeys[targetId] ?? DocumentKey.emptyKeySet,
  );
}

/// An implementation of [TargetMetadataProvider] that provides controlled
/// access to the [TargetMetadataProvider] callbacks. Any target accessed via
/// these callbacks must be registered beforehand via [setSyncedKeys].
class TestTargetMetadataProvider extends TargetMetadataProvider {
  TestTargetMetadataProvider(
      this.syncedKeys,
      this.queryDataMap,
      {@required
          ImmutableSortedSet<DocumentKey> Function(int targetId)
              getRemoteKeysForTarget,
      @required
          TargetData Function(int targetId) getQueryDataForTarget})
      : super(
          getRemoteKeysForTarget: getRemoteKeysForTarget,
          getTargetDataForTarget: getQueryDataForTarget,
        );

  final Map<int, ImmutableSortedSet<DocumentKey>> syncedKeys;

  final Map<int, TargetData> queryDataMap;

  /// Sets or replaces the local state for the provided query data.
  void setSyncedKeys(
      TargetData queryData, ImmutableSortedSet<DocumentKey> keys) {
    queryDataMap[queryData.targetId] = queryData;
    syncedKeys[queryData.targetId] = keys;
  }
}
