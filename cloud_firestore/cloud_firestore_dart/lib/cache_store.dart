/// **Experimental.** A persistent cache in a key-value store that the app brings: implement [CacheStore] (an ordered
/// store of byte keys and byte values, with transactions) and pass it to [keyValueCacheSettings]. The SDK lays the
/// whole cache out in the store; see [KeyValueCacheSettings] for what the cache does and does not do yet.
///
/// A library of its own, so that only the apps that import it carry the code of the cache:
///
/// ```dart
/// import 'package:cloud_firestore_dart/cache_store.dart';
/// import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
///
/// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
///   app: app,
///   settings: Settings(cacheSettings: keyValueCacheSettings(store: myStore)),
/// );
/// ```
///
/// `package:cloud_firestore_dart/cache_store_testing.dart` has the checks of the contract a store must keep, to run
/// in the tests of a store.
library;

export 'package:cloud_firestore_dart/src/firebase/firestore/key_value_cache_settings.dart'
    show keyValueCacheSettings;
export 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
export 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart'
    show IndexBackfillSettings, KeyValueCacheSettings;
