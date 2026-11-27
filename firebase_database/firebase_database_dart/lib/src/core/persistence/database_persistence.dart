/// The persistence option of a database instance: an engine opener plus the cache size. JS:
/// none; Android: `core/DatabaseConfig.java` (`setPersistenceEnabled`, `setPersistenceCacheSizeBytes`,
/// :140-170) and `core/Context.java:37` (`DEFAULT_CACHE_SIZE`).
///
/// The client reads it through [DatabasePersistenceInternal], which no public library exports.
library;

import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:meta/meta.dart';

/// The default cache size, 10 MiB. Android: `core/Context.java:37`.
const int defaultPersistenceCacheSizeBytes = 10 * 1024 * 1024;

/// The smallest cache size, 1 MiB. Android: `core/DatabaseConfig.java:165-167`.
const int minPersistenceCacheSizeBytes = 1024 * 1024;

/// The largest cache size, 100 MiB. Android: `core/DatabaseConfig.java:168-170`.
const int maxPersistenceCacheSizeBytes = 100 * 1024 * 1024;

/// Persistence for one database instance: an opener of a storage engine plus the cache size. Build
/// it with `sqlitePersistence` (package `firebase_database_dart_sqlite`) or, for your own engine,
/// [databasePersistence] of `package:firebase_database_dart/storage_engine.dart`, and pass it as
/// `FirebaseDatabase(persistence: ...)`.
final class DatabasePersistence {
  DatabasePersistence._(
    this._opener,
    this._cacheSizeBytes,
    this._cacheServerData,
  );

  final PersistenceStorageEngineOpener _opener;
  final int _cacheSizeBytes;
  final bool _cacheServerData;
}

/// Makes the persistence option of an engine package: the client opens the engine with [opener]
/// and prunes the server cache above [cacheSizeBytes] (null: 10 MiB).
///
/// With [cacheServerData] false only the pending writes are stored: they survive a restart and
/// are sent again, but no server data is kept, so after a restart a listener waits for the
/// server as it does without persistence. [cacheSizeBytes] then has nothing to prune.
///
/// Throws an [ArgumentError] when [cacheSizeBytes] is below 1 MiB or above 100 MiB.
/// Android: `core/DatabaseConfig.java:162-171` (`DatabaseException` there).
DatabasePersistence databasePersistence({
  required PersistenceStorageEngineOpener opener,
  int? cacheSizeBytes,
  bool cacheServerData = true,
}) {
  final int size = cacheSizeBytes ?? defaultPersistenceCacheSizeBytes;
  if (size < minPersistenceCacheSizeBytes) {
    throw ArgumentError.value(
      cacheSizeBytes,
      'cacheSizeBytes',
      'The minimum cache size must be at least 1 MiB.',
    );
  }
  if (size > maxPersistenceCacheSizeBytes) {
    throw ArgumentError.value(
      cacheSizeBytes,
      'cacheSizeBytes',
      'The maximum cache size must be at most 100 MiB.',
    );
  }
  return DatabasePersistence._(opener, size, cacheServerData);
}

/// What the client reads from a [DatabasePersistence]; package-internal (not exported by any
/// public library).
@internal
extension DatabasePersistenceInternal on DatabasePersistence {
  /// Opens the storage engine of the instance.
  PersistenceStorageEngineOpener get opener => _opener;

  /// The cache size in bytes, already validated.
  int get cacheSizeBytes => _cacheSizeBytes;

  /// Whether server data is cached; false stores the pending writes only.
  bool get cacheServerData => _cacheServerData;
}
