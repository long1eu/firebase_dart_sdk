// PLACEHOLDER: mirrors firebase_database_dart at dcef96bd so that moving onto that commit is a
// change of imports:
//
// * `PersistenceStorageEngine`: lib/src/core/persistence/persistence_storage_engine.dart
// * `PersistenceKey`, `PersistenceStorageEngineOpener`:
//   lib/src/core/persistence/persistence_storage_engine_opener.dart
// * `WriteId`: lib/src/core/write_id.dart
// * `Path`, `Node`, `CompoundWrite`, `TrackedQuery`, `ChildKey`, `PruneForest`, `UserWriteRecord`:
//   the data layer. Declared here as empty marker types only: this package does not model nodes.
//
// When moving onto dcef96bd: delete this file, import those libraries instead, and let builder B's
// `SqliteStorageEngine` replace [engineOverConnection].
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';

/// PLACEHOLDER for the data layer's `Path`.
abstract interface class Path {}

/// PLACEHOLDER for the data layer's `Node`.
abstract interface class Node {}

/// PLACEHOLDER for the data layer's `CompoundWrite`.
abstract interface class CompoundWrite {}

/// PLACEHOLDER for the data layer's `TrackedQuery`.
abstract interface class TrackedQuery {}

/// PLACEHOLDER for the data layer's `ChildKey`.
abstract interface class ChildKey {}

/// PLACEHOLDER for the data layer's `PruneForest`.
abstract interface class PruneForest {}

/// PLACEHOLDER for the data layer's `UserWriteRecord`.
abstract interface class UserWriteRecord {}

/// PLACEHOLDER for `lib/src/core/write_id.dart`.
typedef WriteId = int;

/// PLACEHOLDER for the client's storage engine interface; same members and signatures.
///
/// Mutations happen between [beginTransaction] and [endTransaction]; they are committed only if
/// [setTransactionSuccessful] was called in between. Reads may happen at any time. Programming
/// errors throw a [StateError]; storage errors never throw: the engine becomes degraded
/// ([isDurable] false for good), stores nothing and reads as empty.
abstract interface class PersistenceStorageEngine {
  /// Stores an overwrite.
  void saveUserOverwrite(Path path, Node node, WriteId writeId);

  /// Stores a merge.
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId);

  /// Removes write [writeId]; it must exist.
  void removeUserWrite(WriteId writeId);

  /// The stored writes ordered by write id.
  List<UserWriteRecord> loadUserWrites();

  /// Removes every write.
  void removeAllUserWrites();

  /// The cached node at [path] (empty when nothing is cached).
  Node serverCache(Path path);

  /// Replaces the cache at [path] with [node].
  void overwriteServerCache(Path path, Node node);

  /// Writes each child of [node] below [path], leaving other children alone.
  void mergeIntoServerCache(Path path, Node node);

  /// Writes each write of [children] below [path].
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children);

  /// The estimated size of the server cache in bytes.
  int serverCacheEstimatedSizeInBytes();

  /// Stores [trackedQuery] (insert or replace by id).
  void saveTrackedQuery(TrackedQuery trackedQuery);

  /// Deletes tracked query [trackedQueryId] and its keys.
  void deleteTrackedQuery(int trackedQueryId);

  /// The tracked queries ordered by id.
  List<TrackedQuery> loadTrackedQueries();

  /// Marks every active tracked query inactive with [lastUse] (at start-up).
  void resetPreviouslyActiveTrackedQueries(int lastUse);

  /// Replaces the keys of [trackedQueryId]; the query must exist.
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys);

  /// Adds and removes keys of [trackedQueryId]; the query must exist.
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  );

  /// The union of the keys of [trackedQueryIds] (one id: a set of one); each must exist.
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds);

  /// Deletes the cached data below [root] that [pruneForest] prunes and does not keep.
  void pruneCache(Path root, PruneForest pruneForest);

  /// Starts a transaction; nesting is an error.
  void beginTransaction();

  /// Ends the transaction, committing it if [setTransactionSuccessful] was called.
  void endTransaction();

  /// Marks the current transaction to be committed.
  void setTransactionSuccessful();

  /// Releases the store.
  void close();

  /// Whether data written now survives a restart: true after a successful open, false once the
  /// engine is degraded or fenced (or closed). Never turns true again in the same session.
  bool get isDurable;
}

/// PLACEHOLDER for the client's `PersistenceKey`: the cache of one database of one app.
final class PersistenceKey {
  /// Creates a key.
  const PersistenceKey({required this.appName, required this.databaseUrl});

  /// The name of the Firebase app.
  final String appName;

  /// The database URL (with `ns` for the emulator).
  final Uri databaseUrl;

  @override
  bool operator ==(Object other) =>
      other is PersistenceKey &&
      other.appName == appName &&
      other.databaseUrl == databaseUrl;

  @override
  int get hashCode => Object.hash(appName, databaseUrl);

  @override
  String toString() => 'PersistenceKey($appName, $databaseUrl)';
}

/// PLACEHOLDER for the client's opener type: called once at Repo start.
typedef PersistenceStorageEngineOpener =
    Future<PersistenceStorageEngine> Function(PersistenceKey key);

/// PLACEHOLDER for the client's `DatabaseLogger`; the opener of dcef96bd takes no logger yet.
typedef StoreLogger = void Function(String message);

/// Wraps [connection] in an engine. Builder B replaces the body with
/// `SqliteStorageEngine(connection, cacheSizeBytes: cacheSizeBytes)`.
PersistenceStorageEngine engineOverConnection(
  SqliteConnection connection, {
  required int cacheSizeBytes,
}) {
  return _LifecycleOnlyEngine(connection);
}

/// Until builder B's engine exists: the lifecycle members are real, every data member throws.
final class _LifecycleOnlyEngine implements PersistenceStorageEngine {
  _LifecycleOnlyEngine(this._connection);

  final SqliteConnection _connection;

  @override
  bool get isDurable => _connection.isDurable;

  @override
  void close() => _connection.close();

  static Never _byBuilderB() {
    throw UnimplementedError(
      'SqliteStorageEngine (builder B) is not written yet.',
    );
  }

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) =>
      _byBuilderB();

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) =>
      _byBuilderB();

  @override
  void removeUserWrite(WriteId writeId) => _byBuilderB();

  @override
  List<UserWriteRecord> loadUserWrites() => _byBuilderB();

  @override
  void removeAllUserWrites() => _byBuilderB();

  @override
  Node serverCache(Path path) => _byBuilderB();

  @override
  void overwriteServerCache(Path path, Node node) => _byBuilderB();

  @override
  void mergeIntoServerCache(Path path, Node node) => _byBuilderB();

  @override
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children) =>
      _byBuilderB();

  @override
  int serverCacheEstimatedSizeInBytes() => _byBuilderB();

  @override
  void saveTrackedQuery(TrackedQuery trackedQuery) => _byBuilderB();

  @override
  void deleteTrackedQuery(int trackedQueryId) => _byBuilderB();

  @override
  List<TrackedQuery> loadTrackedQueries() => _byBuilderB();

  @override
  void resetPreviouslyActiveTrackedQueries(int lastUse) => _byBuilderB();

  @override
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys) =>
      _byBuilderB();

  @override
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) => _byBuilderB();

  @override
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds) => _byBuilderB();

  @override
  void pruneCache(Path root, PruneForest pruneForest) => _byBuilderB();

  @override
  void beginTransaction() => _byBuilderB();

  @override
  void endTransaction() => _byBuilderB();

  @override
  void setTransactionSuccessful() => _byBuilderB();
}
