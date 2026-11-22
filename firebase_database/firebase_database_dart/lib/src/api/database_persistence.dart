/// The opaque persistence option and its factory for engine authors. JS: none; Android:
/// `FirebaseDatabase.setPersistenceEnabled`, `setPersistenceCacheSizeBytes`, `core/Context.java`,
/// `core/DatabaseConfig.java`.
library;

import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart';
import 'package:meta/meta.dart';

/// Turns on disk persistence for a `FirebaseDatabase`, passed as its `persistence` argument.
///
/// It is opaque: get one from `sqlitePersistence` of `package:firebase_database_dart_sqlite`, or from
/// [databasePersistence] of `package:firebase_database_dart/storage_engine.dart` for your own engine.
/// Without it the client keeps everything in memory. With it, plain writes survive a restart and cached data
/// answers listeners while offline; transactions and onDisconnect writes stay in memory only.
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(app, persistence: sqlitePersistence('/data/rtdb'));
/// ```
final class DatabasePersistence {
  const DatabasePersistence._(this._open, this._cacheSizeBytes);

  final PersistenceStorageEngineOpener _open;
  final int _cacheSizeBytes;
}

/// Makes a [DatabasePersistence] from an engine opener, for engine authors.
///
/// The client calls [open] once, when the instance starts, with the app name and database URL as a
/// [PersistenceKey]; the engine derives its store from the key. The Future may wait (for a lease held by
/// another owner); an engine that cannot be opened durably still completes, with `isDurable` false, and the
/// client then runs memory only.
///
/// [cacheSizeBytes] bounds the server cache: when it grows past it, unused queries are pruned. It must lie
/// between 1 MiB and 100 MiB (default 10 MiB), else this throws an [ArgumentError].
///
/// ```dart
/// final DatabasePersistence persistence = databasePersistence(
///   (PersistenceKey key) async => MyEngine.open(key.appName, key.databaseUrl),
///   cacheSizeBytes: 20 * 1024 * 1024,
/// );
/// ```
DatabasePersistence databasePersistence(
  Future<PersistenceStorageEngine> Function(PersistenceKey key) open, {
  int cacheSizeBytes = 10 * 1024 * 1024,
}) {
  RangeError.checkValueInInterval(
    cacheSizeBytes,
    minCacheSizeBytes,
    maxCacheSizeBytes,
    'cacheSizeBytes',
  );
  return DatabasePersistence._(open, cacheSizeBytes);
}

/// The smallest accepted cache size, 1 MiB (Android `DatabaseConfig.java`).
@internal
const int minCacheSizeBytes = 1024 * 1024;

/// The largest accepted cache size, 100 MiB (Android `DatabaseConfig.java`).
@internal
const int maxCacheSizeBytes = 100 * 1024 * 1024;

/// The client's view of a [DatabasePersistence]. Not exported.
@internal
extension DatabasePersistenceInternals on DatabasePersistence {
  /// Opens the engine for a key.
  PersistenceStorageEngineOpener get open => _open;

  /// The cache size bound in bytes.
  int get cacheSizeBytes => _cacheSizeBytes;
}
