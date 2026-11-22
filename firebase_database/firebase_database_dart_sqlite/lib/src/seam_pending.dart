// SEAM PENDING: types the core commit after dcef96bd adds (core/util/logger.dart and the new opener
// signature in core/persistence/persistence_storage_engine_opener.dart). Declared once here so this
// package analyzes before that commit lands. When it lands: delete this file and import
// `DatabaseLogLevel`, `DatabaseLogger` and `PersistenceStorageEngineOpener` from the core.
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine_opener.dart'
    show PersistenceKey;

/// The level of a log message (core/util/logger.dart, pending).
enum DatabaseLogLevel {
  /// Details for debugging.
  debug,

  /// Normal events.
  info,

  /// Something went wrong and the client worked around it.
  warning,

  /// Something failed.
  error,
}

/// Receives the log messages of the client (core/util/logger.dart, pending). Messages never contain
/// data, tokens or paths of the database tree.
typedef DatabaseLogger = void Function(DatabaseLogLevel level, String message);

/// How the client opens a storage engine (the pending signature of
/// core/persistence/persistence_storage_engine_opener.dart): called once at Repo start with the
/// client's [DatabaseLogger].
typedef PersistenceStorageEngineOpener =
    Future<PersistenceStorageEngine> Function(
      PersistenceKey key, {
      DatabaseLogger? logger,
    });
