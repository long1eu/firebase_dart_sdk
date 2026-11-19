import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';

/// **Experimental.** Settings for a persistent cache in [store], a key-value store the app brings (see
/// [KeyValueCacheSettings] and [CacheStore]).
///
/// [sizeBytes] is an approximate cache size threshold, as in [PersistentCacheSettings.sizeBytes]: the size is that of
/// the cached documents as the SDK writes them to the store. Use [Settings.cacheSizeUnlimited] to disable the
/// collection; the minimum is 1 MB, an [ArgumentError] is thrown otherwise. [mergeUnsentWrites] is that of
/// [PersistentCacheSettings].
///
/// The store holds the cache of one instance at a time: an instance whose store is the cache of another instance that
/// is still running fails to start.
KeyValueCacheSettings keyValueCacheSettings({
  required CacheStore store,
  int sizeBytes = Settings.defaultCacheSizeBytes,
  bool mergeUnsentWrites = false,
}) => KeyValueCacheSettingsInternal.create(
  store,
  CacheStorePersistence.factoryFor(store),
  sizeBytes: sizeBytes,
  mergeUnsentWrites: mergeUnsentWrites,
);
