import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';

/// Whether this platform has IndexedDB: only the web.
const bool indexedDbPersistenceSupported = false;

/// There is no IndexedDB here: throws an [UnsupportedError].
IndexedDbPersistence createIndexedDbPersistence({
  required String persistenceKey,
  required DatabaseId databaseId,
  required LocalSerializer serializer,
  required LruGarbageCollectorParams lruParams,
  bool multiTab = false,
}) {
  throw UnsupportedError(
    'IndexedDbCacheSettings select a cache in IndexedDB, which only exists on the web. Use PersistentCacheSettings '
    '(SQLite) or MemoryCacheSettings on this platform.',
  );
}
