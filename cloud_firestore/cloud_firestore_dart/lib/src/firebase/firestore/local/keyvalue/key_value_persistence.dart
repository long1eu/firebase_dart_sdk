// What the client needs to know of the key-value cache, without importing its implementation: the implementation is
// only compiled into the apps that import `package:cloud_firestore_dart/cache_store.dart`.

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';

/// Creates the persistence of a key-value cache (given by the entry library through the settings).
typedef KeyValuePersistenceFactory =
    KeyValuePersistence Function({
      required DatabaseId databaseId,
      required LocalSerializer serializer,
      required LruGarbageCollectorParams lruParams,
    });

/// A [Persistence] over a `CacheStore`.
abstract class KeyValuePersistence extends Persistence {
  /// The LRU garbage collector of the cache.
  LruGarbageCollector get garbageCollector;

  /// Removes every key of the store. Only after [shutdown].
  Future<void> clearPersistence();
}
