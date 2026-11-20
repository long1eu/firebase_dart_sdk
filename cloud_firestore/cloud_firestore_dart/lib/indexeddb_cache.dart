/// The IndexedDB cache engine (web only): the cache in IndexedDB in the format of the official Firebase
/// JS SDK, without SQLite. See [IndexedDbCacheSettings].
///
/// A library of its own, so that only the apps that import it carry the engine's code:
///
/// ```dart
/// import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
/// import 'package:cloud_firestore_dart/indexeddb_cache.dart';
///
/// final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
///   app: app,
///   settings: Settings(cacheSettings: indexedDbCacheSettings()),
/// );
/// ```
library;

export 'package:cloud_firestore_dart/src/firebase/firestore/indexeddb_cache_settings.dart'
    show indexedDbCacheSettings;
export 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart'
    show IndexBackfillSettings, IndexedDbCacheSettings;
