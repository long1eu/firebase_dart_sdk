import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';

/// A persistence that stores the cache in IndexedDB in the format of the official Firebase JS SDK (schema version 18,
/// database `firestore/<app>/<project>[.<database>]/main`), selected with `IndexedDbCacheSettings`. Web only: the
/// implementation is in `web/indexeddb_persistence_web.dart`, and `createIndexedDbPersistence` of
/// `indexeddb_persistence_platform.dart` makes one.
///
/// **Experimental, first slice**: the mutation queue, the remote documents, the overlays, the targets, the globals and
/// the collection parents are stored; the field indexes, garbage collection, bundles and named queries are not (see
/// the CHANGELOG). One tab at a time: it takes the JS SDK's primary lease as a JS tab without tab synchronization
/// does, and refuses to start while another client (a JS tab or another tab of this SDK) is active.
///
/// NOT IN THE OFFICIAL SDKS: the official Android SDK has no IndexedDB engine; this one shares its format with the JS
/// SDK's `IndexedDbPersistence`, so that an app can switch between the two on the same browser profile.
/// Creates the IndexedDB persistence of the app [persistenceKey] (its name) and [databaseId]: the seam between the core
/// of the SDK and the engine, which only `package:cloud_firestore_dart/indexeddb_cache.dart` imports, so that an app
/// that does not use the engine does not carry its code.
typedef IndexedDbPersistenceFactory =
    IndexedDbPersistence Function({
      required String persistenceKey,
      required DatabaseId databaseId,
      required LocalSerializer serializer,
      required LruGarbageCollectorParams lruParams,
    });

abstract class IndexedDbPersistence extends Persistence {
  /// The name of the IndexedDB database.
  String get databaseName;

  /// The id of this client in the `owner` and `clientMetadata` stores.
  String get clientId;

  /// Whether this client holds the primary lease of the database. A single tab holds it from [start] on, unless
  /// another client takes it over (a JS tab with `forceOwnership`).
  bool get isPrimary;

  /// Called (once) when another client deletes or upgrades the database while this one has it open. The client
  /// terminates.
  void Function()? databaseClearedListener;

  /// Refreshes the row of this client in `clientMetadata` and extends the primary lease, as the JS SDK does every 4 s.
  Future<void> refreshClientMetadata();

  /// Records whether the network of this client is enabled (`networkEnabled` of its client row).
  Future<void> setNetworkEnabled(bool enabled);

  /// The LRU garbage collector of the cache, on the JS SDK's sequence numbers.
  LruGarbageCollector get garbageCollector;

  /// Deletes the database. Only after [shutdown].
  Future<void> clearPersistence();
}
