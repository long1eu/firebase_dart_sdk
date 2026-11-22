// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/compound_write.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/path.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/snap/node.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/user_write_record.dart';
// switch to storage_engine.dart (DatabaseLogger: the main library if it is not there)
import 'package:firebase_database_dart/src/core/util/logger.dart';
// switch to storage_engine.dart
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart_sqlite/src/server_cache_rows.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/tracked_query_rows.dart';
import 'package:firebase_database_dart_sqlite/src/user_write_rows.dart';

/// The storage engine over one [SqliteConnection]: Android's `SqlPersistenceStorageEngine` with
/// the nested-row layout of the design (16 KiB child split, no leaf parts).
///
/// One engine transaction is one SQLite transaction: [beginTransaction] is
/// [SqliteConnection.begin], [endTransaction] commits when [setTransactionSuccessful] was called
/// and rolls back otherwise. Every mutation outside a transaction is a [StateError] (Android's
/// `verifyInsideTransaction`), whether or not the store is durable.
///
/// Storage never throws into the application: the connection turns every SQLite failure into a
/// degraded (or fenced) store whose statements do nothing and whose reads are empty, and a stored
/// row that does not decode is skipped with a warning through the logger.
final class SqliteStorageEngine implements PersistenceStorageEngine {
  /// An engine over [connection], whose server cache is pruned above [cacheSizeBytes]. Warnings
  /// about stored data go to [logger] (dropped when null).
  // MERGE: builder A: engineOverConnection (lib/src/sqlite_persistence.dart) should pass
  // `logger: options.log` here, so that undecodable rows and prune warnings reach the client's
  // logger; it has the options in both of its call sites.
  SqliteStorageEngine(
    SqliteConnection connection, {
    required this.cacheSizeBytes,
    DatabaseLogger? logger,
  }) : _connection = connection {
    final DatabaseLogger log = logger ?? _dropLog;
    _serverCache = ServerCacheRows(connection, log);
    _userWrites = UserWriteRows(connection, log);
    _trackedQueries = TrackedQueryRows(connection, log);
  }

  final SqliteConnection _connection;
  late final ServerCacheRows _serverCache;
  late final UserWriteRows _userWrites;
  late final TrackedQueryRows _trackedQueries;

  /// The size above which the server cache is pruned, in bytes.
  ///
  /// The engine does not prune by itself: the persistence manager's cache policy compares
  /// [serverCacheEstimatedSizeInBytes] with its own limit. Kept for the opener's signature.
  final int cacheSizeBytes;

  bool _successful = false;
  int _sizeAtBegin = 0;

  static void _dropLog(DatabaseLogLevel level, String message) {}

  void _requireTransaction() {
    if (!_connection.inTransaction) {
      throw StateError('Transaction expected to already be in progress.');
    }
  }

  @override
  bool get isDurable => _connection.isDurable;

  @override
  void close() => _connection.close();

  @override
  void beginTransaction() {
    if (_connection.inTransaction) {
      throw StateError(
        'beginTransaction called while a storage transaction is already in progress.',
      );
    }
    _connection.begin();
    _successful = false;
    _sizeAtBegin = _serverCache.size;
  }

  @override
  void setTransactionSuccessful() {
    _requireTransaction();
    _successful = true;
  }

  @override
  void endTransaction() {
    _requireTransaction();
    if (_successful) {
      _connection.commit();
    } else {
      _connection.rollback();
      _serverCache.size = _sizeAtBegin;
    }
    _successful = false;
  }

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) {
    _requireTransaction();
    _userWrites.saveOverwrite(path, node, writeId);
  }

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) {
    _requireTransaction();
    _userWrites.saveMerge(path, children, writeId);
  }

  @override
  void removeUserWrite(WriteId writeId) {
    _requireTransaction();
    _userWrites.remove(writeId);
  }

  @override
  List<UserWriteRecord> loadUserWrites() => _userWrites.load();

  @override
  void removeAllUserWrites() {
    _requireTransaction();
    _userWrites.removeAll();
  }

  @override
  Node serverCache(Path path) {
    if (!isDurable) {
      return ChildrenNode.empty;
    }
    return _serverCache.load(path);
  }

  @override
  void overwriteServerCache(Path path, Node node) {
    _requireTransaction();
    _serverCache.overwrite(path, node);
  }

  @override
  void mergeIntoServerCache(Path path, Node node) {
    _requireTransaction();
    _serverCache.mergeChildren(path, node);
  }

  @override
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children) {
    _requireTransaction();
    _serverCache.mergeWrite(path, children);
  }

  /// The bytes of the server cache rows (UTF-8 path plus value), from a counter kept in memory;
  /// 0 when the store is not durable.
  @override
  int serverCacheEstimatedSizeInBytes() => isDurable ? _serverCache.size : 0;

  @override
  void saveTrackedQuery(TrackedQuery trackedQuery) {
    _requireTransaction();
    _trackedQueries.save(trackedQuery);
  }

  @override
  void deleteTrackedQuery(int trackedQueryId) {
    _requireTransaction();
    _trackedQueries.delete(trackedQueryId);
  }

  @override
  List<TrackedQuery> loadTrackedQueries() => _trackedQueries.load();

  @override
  void resetPreviouslyActiveTrackedQueries(int lastUse) {
    if (_connection.inTransaction) {
      _trackedQueries.resetPreviouslyActive(lastUse);
      return;
    }
    beginTransaction();
    try {
      _trackedQueries.resetPreviouslyActive(lastUse);
      setTransactionSuccessful();
    } finally {
      endTransaction();
    }
  }

  @override
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys) {
    _requireTransaction();
    _trackedQueries.saveKeys(trackedQueryId, keys);
  }

  @override
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) {
    _requireTransaction();
    _trackedQueries.updateKeys(trackedQueryId, added, removed);
  }

  @override
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds) =>
      _trackedQueries.loadKeys(trackedQueryIds);

  @override
  void pruneCache(Path root, PruneForest pruneForest) {
    _requireTransaction();
    if (!isDurable || !pruneForest.prunesAnything()) {
      return;
    }
    _serverCache.prune(root, pruneForest);
  }
}
