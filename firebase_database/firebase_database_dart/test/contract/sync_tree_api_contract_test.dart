// Runs the sync tree API contract (sync_tree_api_contract.dart) against SyncTree.
import 'package:firebase_database_dart/src/core/listen_provider.dart';
import 'package:firebase_database_dart/src/core/sync_tree.dart';
import 'package:test/test.dart';

import 'sync_tree_api_contract.dart';

void main() {
  group('SyncTree', () {
    runSyncTreeApiContract(
      (ListenProvider provider) => SyncTree(listenProvider: provider),
    );
  });
}
