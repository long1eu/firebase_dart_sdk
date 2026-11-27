import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogger;
import 'package:firebase_database_dart/storage_engine.dart';
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
  /// An engine over [connection]. Warnings about stored data go to [logger].
  ///
  /// The engine never prunes by itself: the client's cache policy compares
  /// [serverCacheEstimatedSizeInBytes] with the size limit of its `DatabasePersistence`.
  SqliteStorageEngine(
    SqliteConnection connection, {
    required DatabaseLogger logger,
  }) : _connection = connection {
    _serverCache = ServerCacheRows(connection, logger);
    _userWrites = UserWriteRows(connection, logger);
    _trackedQueries = TrackedQueryRows(connection, logger);
  }

  final SqliteConnection _connection;
  late final ServerCacheRows _serverCache;
  late final UserWriteRows _userWrites;
  late final TrackedQueryRows _trackedQueries;

  /// Whether an engine transaction is open: [beginTransaction] was called and [endTransaction]
  /// was not. Kept apart from the connection's flag, which [close] clears.
  bool _open = false;
  bool _successful = false;
  int _sizeAtBegin = 0;

  /// The write removals of the open transaction: ids, or all writes.
  final Set<int> _removedNow = <int>{};
  bool _removedAllNow = false;

  /// Write removals of transactions that were meant to commit but did not reach the file (a busy
  /// file, or a storage error that degraded the store). Left in the file, those writes would be
  /// loaded and sent again at the next start although the server already answered them. They are
  /// applied again in the next transaction that reaches the file, or at [close] after a storage
  /// error ([SqliteConnection.removeUserWritesAfterDegraded]).
  final Set<int> _unsavedRemovals = <int>{};
  bool _unsavedRemoveAll = false;

  /// Whether the open transaction applies [_unsavedRemovals] again.
  bool _retryingRemovals = false;

  void _requireTransaction() {
    if (!_open) {
      throw StateError('Transaction expected to already be in progress.');
    }
  }

  /// Checks that an engine transaction is open ([StateError] otherwise) and tells whether a
  /// mutation still reaches the connection: false after a [close] inside the transaction.
  bool _canMutate() {
    _requireTransaction();
    return _connection.inTransaction;
  }

  @override
  bool get isDurable => _connection.isDurable;

  @override
  void close() {
    if (_connection.state == StoreState.degraded &&
        (_unsavedRemoveAll || _unsavedRemovals.isNotEmpty)) {
      _connection.removeUserWritesAfterDegraded(
        _unsavedRemovals,
        all: _unsavedRemoveAll,
      );
    }
    _connection.close();
  }

  @override
  void beginTransaction() {
    if (_open || _connection.inTransaction) {
      throw StateError(
        'beginTransaction called while a storage transaction is already in progress.',
      );
    }
    final bool reachesFile = _connection.begin();
    _open = true;
    _successful = false;
    _sizeAtBegin = _serverCache.size;
    _removedNow.clear();
    _removedAllNow = false;
    _retryingRemovals =
        reachesFile && (_unsavedRemoveAll || _unsavedRemovals.isNotEmpty);
    if (_retryingRemovals) {
      if (_unsavedRemoveAll) {
        _userWrites.removeAll();
      } else {
        _unsavedRemovals.forEach(_userWrites.remove);
      }
    }
  }

  @override
  void setTransactionSuccessful() {
    _requireTransaction();
    _successful = true;
  }

  @override
  void endTransaction() {
    _requireTransaction();
    bool committed = false;
    // A close inside the transaction already rolled it back; ending it is then a no-op.
    if (_connection.inTransaction) {
      if (_successful) {
        // A transaction the file refused (busy) or that failed did not change the rows.
        committed = _connection.commit();
        if (!committed) {
          _serverCache.size = _sizeAtBegin;
        }
      } else {
        _connection.rollback();
        _serverCache.size = _sizeAtBegin;
      }
    }
    if (committed && _retryingRemovals) {
      _unsavedRemovals.clear();
      _unsavedRemoveAll = false;
    }
    if (!committed && _successful) {
      _keepUnsavedRemovals();
    }
    _open = false;
    _successful = false;
  }

  /// Keeps the removals of a transaction that was meant to commit and did not, while the file is
  /// still this store's (durable or degraded; a fenced file belongs to another owner).
  void _keepUnsavedRemovals() {
    final StoreState state = _connection.state;
    if (state != StoreState.durable && state != StoreState.degraded) {
      return;
    }
    if (_removedAllNow) {
      _unsavedRemovals.clear();
      _unsavedRemoveAll = true;
    } else if (!_unsavedRemoveAll) {
      _unsavedRemovals.addAll(_removedNow);
    }
  }

  @override
  void saveUserOverwrite(Path path, Node node, int writeId) {
    if (!_canMutate()) {
      return;
    }
    _userWrites.saveOverwrite(path, node, writeId);
  }

  @override
  void saveUserMerge(Path path, CompoundWrite children, int writeId) {
    if (!_canMutate()) {
      return;
    }
    _userWrites.saveMerge(path, children, writeId);
  }

  @override
  void removeUserWrite(int writeId) {
    if (!_canMutate()) {
      return;
    }
    _removedNow.add(writeId);
    _userWrites.remove(writeId);
  }

  @override
  List<UserWriteRecord> loadUserWrites() => _userWrites.load();

  @override
  void removeAllUserWrites() {
    if (!_canMutate()) {
      return;
    }
    _removedNow.clear();
    _removedAllNow = true;
    _userWrites.removeAll();
  }

  @override
  Node serverCache(Path path) => _serverCache.load(path);

  @override
  void overwriteServerCache(Path path, Node node) {
    if (!_canMutate()) {
      return;
    }
    _serverCache.overwrite(path, node);
  }

  @override
  void mergeIntoServerCache(Path path, Node node) {
    if (!_canMutate()) {
      return;
    }
    _serverCache.mergeChildren(path, node);
  }

  @override
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children) {
    if (!_canMutate()) {
      return;
    }
    _serverCache.mergeWrite(path, children);
  }

  /// The bytes of the server cache rows (UTF-8 path plus value), from a counter kept in memory;
  /// 0 when the store is not durable.
  @override
  int serverCacheEstimatedSizeInBytes() => isDurable ? _serverCache.size : 0;

  @override
  void saveTrackedQuery(TrackedQuery trackedQuery) {
    if (!_canMutate()) {
      return;
    }
    _trackedQueries.save(trackedQuery);
  }

  @override
  void deleteTrackedQuery(int trackedQueryId) {
    if (!_canMutate()) {
      return;
    }
    _trackedQueries.delete(trackedQueryId);
  }

  @override
  List<TrackedQuery> loadTrackedQueries() => _trackedQueries.load();

  @override
  void resetPreviouslyActiveTrackedQueries(int lastUse) {
    if (_open) {
      if (_connection.inTransaction) {
        _trackedQueries.resetPreviouslyActive(lastUse);
      }
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
    if (!_canMutate()) {
      return;
    }
    _trackedQueries.saveKeys(trackedQueryId, keys);
  }

  @override
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) {
    if (!_canMutate()) {
      return;
    }
    _trackedQueries.updateKeys(trackedQueryId, added, removed);
  }

  @override
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds) =>
      _trackedQueries.loadKeys(trackedQueryIds);

  @override
  void pruneCache(Path root, PruneForest pruneForest) {
    if (!_canMutate() || !isDurable || !pruneForest.prunesAnything()) {
      return;
    }
    _serverCache.prune(root, pruneForest);
  }
}
