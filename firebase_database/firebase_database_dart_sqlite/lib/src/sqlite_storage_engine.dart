// BUILDER B's FILE. Signature-only stub written by builder A so that the package analyzes before
// B starts: `isDurable` and `close` are real (the opener's tests need them); every data method
// throws. B replaces the bodies; design: rtdb_storage_engine_design.md sections 1-3, 5, 6, 9.
import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';

/// The storage engine over one [SqliteConnection]: Android's `SqlPersistenceStorageEngine` with
/// the nested-row layout of the design (16 KiB child split, no leaf parts).
final class SqliteStorageEngine implements PersistenceStorageEngine {
  /// An engine over [connection], whose server cache is pruned above [cacheSizeBytes].
  SqliteStorageEngine(this._connection, {required this.cacheSizeBytes});

  final SqliteConnection _connection;

  /// The size above which the server cache is pruned, in bytes.
  final int cacheSizeBytes;

  static Never _notWritten() {
    throw UnimplementedError('SqliteStorageEngine is not written yet (builder B).');
  }

  @override
  bool get isDurable => _connection.isDurable;

  @override
  void close() => _connection.close();

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) => _notWritten();

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) => _notWritten();

  @override
  void removeUserWrite(WriteId writeId) => _notWritten();

  @override
  List<UserWriteRecord> loadUserWrites() => _notWritten();

  @override
  void removeAllUserWrites() => _notWritten();

  @override
  Node serverCache(Path path) => _notWritten();

  @override
  void overwriteServerCache(Path path, Node node) => _notWritten();

  @override
  void mergeIntoServerCache(Path path, Node node) => _notWritten();

  @override
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children) => _notWritten();

  @override
  int serverCacheEstimatedSizeInBytes() => _notWritten();

  @override
  void saveTrackedQuery(TrackedQuery trackedQuery) => _notWritten();

  @override
  void deleteTrackedQuery(int trackedQueryId) => _notWritten();

  @override
  List<TrackedQuery> loadTrackedQueries() => _notWritten();

  @override
  void resetPreviouslyActiveTrackedQueries(int lastUse) => _notWritten();

  @override
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys) => _notWritten();

  @override
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) => _notWritten();

  @override
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds) => _notWritten();

  @override
  void pruneCache(Path root, PruneForest pruneForest) => _notWritten();

  @override
  void beginTransaction() => _notWritten();

  @override
  void endTransaction() => _notWritten();

  @override
  void setTransactionSuccessful() => _notWritten();
}
