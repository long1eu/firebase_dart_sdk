import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_persistence_platform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/web_storage_shared_client_state_storage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';

/// Settings for a cache in IndexedDB, in the format of the official Firebase JS SDK (see [IndexedDbCacheSettings]).
///
/// [sizeBytes] is an approximate cache size threshold, as in [PersistentCacheSettings.sizeBytes]: the size is the one
/// the JS SDK counts (the JSON length of the cached documents). Use [Settings.cacheSizeUnlimited] to disable the
/// collection; the minimum is 1 MB, an [ArgumentError] is thrown otherwise. [indexAutoCreation], [indexBackfill] and
/// [mergeUnsentWrites] are those of [PersistentCacheSettings].
///
/// With [multiTab] the tabs of the app share the cache (see [IndexedDbCacheSettings.multiTab]).
///
/// Throws an [UnsupportedError] on other platforms than the web.
IndexedDbCacheSettings indexedDbCacheSettings({
  int sizeBytes = Settings.defaultCacheSizeBytes,
  bool indexAutoCreation = false,
  IndexBackfillSettings? indexBackfill,
  bool mergeUnsentWrites = false,
  bool multiTab = false,
}) => IndexedDbCacheSettingsInternal.create(
  createIndexedDbPersistence,
  sizeBytes: sizeBytes,
  indexAutoCreation: indexAutoCreation,
  indexBackfill: indexBackfill,
  mergeUnsentWrites: mergeUnsentWrites,
  multiTab: multiTab,
  createSharedClientStateStorage: createWebStorageSharedClientStateStorage,
);
