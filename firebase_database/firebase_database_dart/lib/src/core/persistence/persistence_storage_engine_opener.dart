/// How the client opens a storage engine. JS: none; Android: `core/Platform.java`
/// (`createPersistenceManager`), `android/AndroidPlatform.java` (one cache per app and database).
///
/// No I/O library is imported here: a VM engine (SQLite) lives in its own package and only its
/// opener reaches the client, wrapped with the cache size in a `DatabasePersistence`
/// (database_persistence.dart); the opener does not carry the cache size.
library;

import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';

/// Identifies the cache of one database of one app: the engine derives its file or store name
/// from it.
final class PersistenceKey {
  /// Creates a key.
  const PersistenceKey({required this.appName, required this.databaseUrl});

  /// The name of the Firebase app.
  final String appName;

  /// The database URL (with `ns` for the emulator).
  final Uri databaseUrl;

  /// Equal when app name and database URL are (Android keys its cache by both,
  /// `AndroidPlatform.createPersistenceManager`).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceKey &&
          other.appName == appName &&
          other.databaseUrl == databaseUrl;

  /// Hash of app name and database URL.
  @override
  int get hashCode => Object.hash(appName, databaseUrl);

  /// The app name and database URL.
  @override
  String toString() => 'PersistenceKey($appName, $databaseUrl)';
}

/// Opens the engine for [key]; called by the client once at Repo start, before the Repo's first
/// operation runs (taking a lease may wait, hence the future). An engine that cannot be opened
/// durably still completes, with `isDurable` false; the future fails only on programming errors.
/// The lease, degraded mode and storage failures are reported through [logger] (null: dropped).
typedef PersistenceStorageEngineOpener =
    Future<PersistenceStorageEngine> Function(
      PersistenceKey key, {
      DatabaseLogger? logger,
    });
