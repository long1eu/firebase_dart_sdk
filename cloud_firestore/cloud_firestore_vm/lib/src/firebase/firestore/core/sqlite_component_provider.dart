// File created by
// Lung Razvan <long1eu>
// on 24/01/2021

import 'package:cloud_firestore_vm/src/firebase/firestore/core/component_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/database_info.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/memory_component_provider.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/garbage_collection_scheduler.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/remote/remote_serializer.dart';

class SQLiteComponentProvider extends MemoryComponentProvider {
  @override
  GarbageCollectionScheduler createGarbageCollectionScheduler(ComponentProviderConfiguration configuration) {
    final SQLiteLruReferenceDelegate lruDelegate = (persistence as SQLitePersistence).referenceDelegate;
    final LruGarbageCollector gc = lruDelegate.garbageCollector;
    return gc.newScheduler(configuration.asyncQueue, localStore);
  }

  @override
  Future<Persistence> createPersistence(ComponentProviderConfiguration configuration) async {
    final DatabaseInfo databaseInfo = configuration.databaseInfo;
    final LocalSerializer serializer = LocalSerializer(RemoteSerializer(databaseInfo.databaseId));
    final LruGarbageCollectorParams params =
        LruGarbageCollectorParams.withCacheSizeBytes(configuration.settings.cacheSizeBytes);

    return SQLitePersistence.create(
      databaseInfo.persistenceKey,
      databaseInfo.databaseId,
      serializer,
      configuration.openDatabase,
      params,
    );
  }
}
