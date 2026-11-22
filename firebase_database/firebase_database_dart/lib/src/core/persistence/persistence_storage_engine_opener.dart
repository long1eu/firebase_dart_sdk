/// How the client opens a storage engine. JS: none; Android: `core/Platform.java`
/// (`createPersistenceManager`), `android/AndroidPlatform.java` (one cache per app and database).
///
/// No I/O library is imported here: a VM engine (SQLite) lives behind `package:firebase_database_dart/io.dart`
/// and only its opener is passed in.
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

  @override
  bool operator ==(Object other) => throw UnimplementedError();

  @override
  int get hashCode => throw UnimplementedError();

  @override
  String toString() => throw UnimplementedError();
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
