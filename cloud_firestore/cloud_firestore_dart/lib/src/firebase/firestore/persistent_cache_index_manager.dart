import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';

/// Controls the creation and the lifecycle of the persistent cache indexes of
/// a `FirebaseFirestore` instance.
///
/// A persistent cache index speeds up queries that are executed against the
/// local cache (`Source.cache`, offline, and the first results of a
/// listener). It is not the same as a Cloud Firestore index: it only exists
/// inside the SDK, on this device, and does not change what a query returns.
///
/// To get an instance use `FirebaseFirestore.persistentCacheIndexManager`. It is null
/// when the instance does not use the persistent (SQLite) cache.
///
/// ```dart
/// await firestore.persistentCacheIndexManager?.enableIndexAutoCreation();
/// ```
///
/// Indexes are not used for queries with inequality filters on several
/// fields; those scan the cache, as in the JS SDK. This is the JS SDK's
/// `getPersistentCacheIndexManager` with
/// `enablePersistentCacheIndexAutoCreation`,
/// `disablePersistentCacheIndexAutoCreation` and
/// `deleteAllPersistentCacheIndexes`.
class PersistentCacheIndexManager {
  /// Implementation detail of the SDK; not part of the supported API. Use
  /// `FirebaseFirestore.persistentCacheIndexManager`.
  PersistentCacheIndexManager._(this._client);

  final FirestoreClient _client;

  /// Lets the SDK create persistent cache indexes automatically for the
  /// queries it executes against the local cache, when it believes that an
  /// index helps: the query scanned at least 100 documents and less than half
  /// of them were results.
  ///
  /// An index is filled in the background while the app runs, by default 50
  /// documents per minute at most (see `IndexBackfillSettings`), or at once
  /// with [fillIndexes]; queries use it as far as it is filled and scan the
  /// rest.
  ///
  /// This feature is disabled by default. The setting is not persisted: call
  /// this every time the instance is created, or set
  /// `PersistentCacheSettings.indexAutoCreation` (specific to this package),
  /// which turns it on from the start of every instance.
  ///
  /// The returned future fails with a [FirestoreException] with code
  /// `failedPrecondition` if the instance was terminated; the same holds for
  /// the other methods of this class.
  Future<void> enableIndexAutoCreation() {
    return _client.setIndexAutoCreationEnabled(enabled: true);
  }

  /// Stops creating persistent cache indexes automatically. The indexes that
  /// were created by [enableIndexAutoCreation] still take effect.
  Future<void> disableIndexAutoCreation() {
    return _client.setIndexAutoCreationEnabled(enabled: false);
  }

  /// Fills the persistent cache indexes now instead of waiting for the
  /// background runs, for example while a loading screen is shown. Returns the
  /// number of documents indexed.
  ///
  /// The future completes when the indexes are up to date or, when
  /// [maxDocuments] is given, once that many documents were indexed (an index
  /// that is not complete then is filled further in the background). The work
  /// is split into runs of 100 documents; each run holds the instance for
  /// about 5 to 20 ms on a cache without many pending writes, and the other
  /// operations of the instance (queries, writes, snapshots) run between two
  /// runs. Without [maxDocuments] the time grows with the number of cached
  /// documents behind the indexes, about 5 to 20 seconds for 100,000.
  ///
  /// Not in the official SDKs; specific to this package. Throws an
  /// [ArgumentError] when [maxDocuments] is less than 1. If the instance is
  /// terminated meanwhile, the future completes with the count so far.
  Future<int> fillIndexes({int? maxDocuments}) {
    if (maxDocuments != null && maxDocuments < 1) {
      throw ArgumentError.value(
        maxDocuments,
        'maxDocuments',
        'must be at least 1',
      );
    }
    return _client.fillIndexes(maxDocuments: maxDocuments);
  }

  /// Removes all persistent cache indexes. This also deletes the indexes that
  /// were configured with the deprecated `FirebaseFirestore.setIndexConfiguration`.
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
