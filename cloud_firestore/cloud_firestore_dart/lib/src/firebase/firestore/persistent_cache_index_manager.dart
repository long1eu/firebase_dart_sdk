import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';

/// Controls the creation and the lifecycle of the persistent cache indexes of
/// a `Firestore` instance.
///
/// A persistent cache index speeds up queries that are executed against the
/// local cache (`Source.cache`, offline, and the first results of a
/// listener). It is not the same as a Cloud Firestore index: it only exists
/// inside the SDK, on this device, and does not change what a query returns.
///
/// To get an instance use `Firestore.persistentCacheIndexManager`. It is null
/// when the instance does not use the persistent (SQLite) cache.
class PersistentCacheIndexManager {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// `Firestore.persistentCacheIndexManager`.
  PersistentCacheIndexManager._(this._client);

  final FirestoreClient _client;

  /// Lets the SDK create persistent cache indexes automatically for the
  /// queries it executes against the local cache, when it believes that an
  /// index helps: the query scanned at least 100 documents and less than half
  /// of them were results.
  ///
  /// An index is filled in the background, 50 documents per minute at most
  /// while the app runs; queries use it as far as it is filled and scan the
  /// rest.
  ///
  /// This feature is disabled by default. The setting is not persisted: call
  /// this every time the instance is created.
  Future<void> enableIndexAutoCreation() {
    return _client.setIndexAutoCreationEnabled(enabled: true);
  }

  /// Stops creating persistent cache indexes automatically. The indexes that
  /// were created by [enableIndexAutoCreation] still take effect.
  Future<void> disableIndexAutoCreation() {
    return _client.setIndexAutoCreationEnabled(enabled: false);
  }

  /// Removes all persistent cache indexes. This also deletes the indexes that
  /// were configured with the deprecated `Firestore.setIndexConfiguration`.
  Future<void> deleteAllIndexes() {
    return _client.deleteAllFieldIndexes();
  }
}

/// Members of [PersistentCacheIndexManager] for the SDK itself. Not exported by the public libraries.
extension PersistentCacheIndexManagerInternal on PersistentCacheIndexManager {
  /// The index manager of the instance that owns [client].
  static PersistentCacheIndexManager create(FirestoreClient client) =>
      PersistentCacheIndexManager._(client);
}
