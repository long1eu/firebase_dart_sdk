/// The sync tree's only dependency on persistence. JS: none (no persistence); Android:
/// `core/persistence/PersistenceManager.java`; iOS: `Persistence/FPersistenceManager.h`.
///
/// Seam between the sync-tree team and the persistence team.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/noop_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// Stores pending user writes, the server cache and the tracked-query bookkeeping.
///
/// Rules every implementation keeps:
///
/// * **Synchronous.** Every method returns its result directly; the sync tree never awaits. An
///   engine over an asynchronous store (IndexedDB, an async SQLite) keeps an in-memory image and
///   writes behind it, one batch per [runInTransaction], or has the server cache loaded before
///   the sync tree asks (`SyncTree.addEventRegistration` takes a `preloadedServerCache` for that).
/// * **Inside a transaction.** Every mutating method is called only from inside the body of a
///   [runInTransaction]; the sync tree wraps each of its entry points in one, so the user-write
///   log and the server cache change together. Calling a mutating method outside a transaction,
///   or nesting transactions, is a programming error ([NoopPersistenceManager] asserts it).
/// * **Unresolved writes.** [saveUserOverwrite] and [saveUserMerge] get the data with server
///   values unresolved (`{'.sv': ...}`), so a restart replays what the user asked for.
/// * The Repo of `.info` always uses [NoopPersistenceManager].
abstract interface class PersistenceManager {
  /// Persists a user overwrite of [node] at [path] with [writeId].
  void saveUserOverwrite(Path path, Node node, WriteId writeId);

  /// Persists a user merge of [children] at [path] with [writeId].
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId);

  /// Removes the persisted write [writeId] (acknowledged or reverted).
  void removeUserWrite(WriteId writeId);

  /// Removes every persisted write (purgeOutstandingWrites).
  void removeAllUserWrites();

  /// Promotes an acknowledged overwrite into the server cache, unless an active default query at
  /// [path] will receive the data from the server anyway.
  void applyUserWriteToServerCache(Path path, Node node);

  /// Promotes an acknowledged merge into the server cache (Android's second
  /// `applyUserWriteToServerCache` overload).
  void applyUserMergeToServerCache(Path path, CompoundWrite merge);

  /// The persisted writes in write-id order; Repo calls it once at start to restore them.
  List<UserWriteRecord> loadUserWrites();

  /// The cached server data for [query], with whether it is complete (a complete tracked query
  /// covers it) and filtered (only the tracked keys of a filtered query).
  CacheNode serverCache(QuerySpec query);

  /// Stores server data [node] for [query]: an overwrite for a query that loads all data, a merge
  /// of the children otherwise; marks the query complete.
  void updateServerCache(QuerySpec query, Node node);

  /// Merges server [children] at [path] into the cache (Android's second `updateServerCache`).
  void updateServerCacheWithMerge(Path path, CompoundWrite children);

  /// A listen on [query] started (tracked query active, last use updated).
  void setQueryActive(QuerySpec query);

  /// A listen on [query] stopped (the query becomes prunable).
  void setQueryInactive(QuerySpec query);

  /// The server finished sending [query]'s data.
  void setQueryComplete(QuerySpec query);

  /// Replaces the child keys a filtered [query] holds.
  void setTrackedQueryKeys(QuerySpec query, Set<ChildKey> keys);

  /// Adds and removes child keys of a filtered [query].
  void updateTrackedQueryKeys(
    QuerySpec query,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  );

  /// Whether what this manager stores survives a restart: false for [NoopPersistenceManager],
  /// otherwise the engine's `isDurable` (false once it is degraded). Storage errors never throw
  /// from any method here; they degrade the engine and this turns false.
  bool get isDurable;

  /// Runs [body] in one storage transaction and returns its result; an exception from [body]
  /// rolls the transaction back and is rethrown.
  T runInTransaction<T>(T Function() body);
}
