/// Tier 1 persistence: restart-safe pending writes only. JS: none; Android: none (a split of
/// `core/persistence/DefaultPersistenceManager.java`; see the storage engine design, section 13a).
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// A [PersistenceManager] that sends the user-write methods ([saveUserOverwrite],
/// [saveUserMerge], [removeUserWrite], [removeAllUserWrites], [loadUserWrites]) and
/// [runInTransaction] to [engine], and behaves like [NoopPersistenceManager] for everything else:
/// [serverCache] is empty and not complete, nothing is tracked, acknowledged writes are not
/// promoted into a server cache.
///
/// Why a separate manager and not a writes-only engine under [DefaultPersistenceManager]: the
/// default manager takes completeness from its in-memory tracked queries and the data from the
/// engine, so a query marked complete earlier in the session would come back, when listened to
/// again, as complete but empty, and the listener would get a false null before the server
/// answers. Here nothing is ever reported complete, so listeners after a restart start empty and
/// wait for the server, as the JS SDK does.
final class WritesOnlyPersistenceManager implements PersistenceManager {
  /// Creates a manager over [engine]. Android: none (see the library doc).
  const WritesOnlyPersistenceManager(this.engine);

  /// The storage engine (its server-cache and tracked-query tables stay empty).
  final PersistenceStorageEngine engine;

  /// Sent to the engine. Android: `DefaultPersistenceManager.saveUserOverwrite`.
  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) =>
      engine.saveUserOverwrite(path, node, writeId);

  /// Sent to the engine. Android: `DefaultPersistenceManager.saveUserMerge`.
  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) =>
      engine.saveUserMerge(path, children, writeId);

  /// Sent to the engine. Android: `DefaultPersistenceManager.removeUserWrite`.
  @override
  void removeUserWrite(WriteId writeId) => engine.removeUserWrite(writeId);

  /// Sent to the engine. Android: `DefaultPersistenceManager.removeAllUserWrites`.
  @override
  void removeAllUserWrites() => engine.removeAllUserWrites();

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.applyUserWriteToServerCache`.
  @override
  void applyUserWriteToServerCache(Path path, Node node) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.applyUserWriteToServerCache`.
  @override
  void applyUserMergeToServerCache(Path path, CompoundWrite merge) {}

  /// Sent to the engine. Android: `DefaultPersistenceManager.loadUserWrites`.
  @override
  List<UserWriteRecord> loadUserWrites() => engine.loadUserWrites();

  /// Empty, not complete, not filtered. Android: `NoopPersistenceManager.serverCache`.
  @override
  CacheNode serverCache(QuerySpec query) =>
      CacheNode(ChildrenNode.empty, fullyInitialized: false, filtered: false);

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.updateServerCache`.
  @override
  void updateServerCache(QuerySpec query, Node node) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.updateServerCache`.
  @override
  void updateServerCacheWithMerge(Path path, CompoundWrite children) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.setQueryActive`.
  @override
  void setQueryActive(QuerySpec query) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.setQueryInactive`.
  @override
  void setQueryInactive(QuerySpec query) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.setQueryComplete`.
  @override
  void setQueryComplete(QuerySpec query) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.setTrackedQueryKeys`.
  @override
  void setTrackedQueryKeys(QuerySpec query, Set<ChildKey> keys) {}

  /// A no-op, as in [NoopPersistenceManager]. Android: `NoopPersistenceManager.updateTrackedQueryKeys`.
  @override
  void updateTrackedQueryKeys(
    QuerySpec query,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) {}

  /// The engine's `isDurable`. Android: none.
  @override
  bool get isDurable => engine.isDurable;

  /// One engine transaction around [body]; committed only when [body] returns. Android:
  /// `DefaultPersistenceManager.runInTransaction`.
  @override
  T runInTransaction<T>(T Function() body) {
    engine.beginTransaction();
    try {
      final T result = body();
      engine.setTransactionSuccessful();
      return result;
    } finally {
      engine.endTransaction();
    }
  }
}
