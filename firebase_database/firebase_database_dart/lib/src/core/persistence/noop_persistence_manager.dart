/// Persistence that keeps nothing. JS: none; Android:
/// `core/persistence/NoopPersistenceManager.java`.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_manager.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/view/cache_node.dart';
import 'package:firebase_database_dart/src/core/view/query_spec.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// The default [PersistenceManager]: stores nothing, returns an empty incomplete server cache, and
/// asserts the transaction rules (no nesting, no mutation outside a transaction).
final class NoopPersistenceManager implements PersistenceManager {
  /// Creates a manager. Android: `NoopPersistenceManager()`.
  NoopPersistenceManager();

  bool _insideTransaction = false;

  /// Android: `NoopPersistenceManager.saveUserOverwrite`; stores nothing.
  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.saveUserMerge`; stores nothing.
  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.removeUserWrite`.
  @override
  void removeUserWrite(WriteId writeId) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.removeAllUserWrites`.
  @override
  void removeAllUserWrites() {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.applyUserWriteToServerCache(Path, Node)`.
  @override
  void applyUserWriteToServerCache(Path path, Node node) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.applyUserWriteToServerCache(Path, CompoundWrite)`.
  @override
  void applyUserMergeToServerCache(Path path, CompoundWrite merge) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.loadUserWrites`; always empty.
  @override
  List<UserWriteRecord> loadUserWrites() => const <UserWriteRecord>[];

  /// Android: `NoopPersistenceManager.serverCache`; empty, not complete, not filtered.
  @override
  CacheNode serverCache(QuerySpec query) =>
      CacheNode(ChildrenNode.empty, fullyInitialized: false, filtered: false);

  /// Android: `NoopPersistenceManager.updateServerCache(QuerySpec, Node)`.
  @override
  void updateServerCache(QuerySpec query, Node node) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.updateServerCache(Path, CompoundWrite)`.
  @override
  void updateServerCacheWithMerge(Path path, CompoundWrite children) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.setQueryActive`.
  @override
  void setQueryActive(QuerySpec query) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.setQueryInactive`.
  @override
  void setQueryInactive(QuerySpec query) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.setQueryComplete`.
  @override
  void setQueryComplete(QuerySpec query) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.setTrackedQueryKeys`.
  @override
  void setTrackedQueryKeys(QuerySpec query, Set<ChildKey> keys) {
    _verifyInsideTransaction();
  }

  /// Android: `NoopPersistenceManager.updateTrackedQueryKeys`.
  @override
  void updateTrackedQueryKeys(
    QuerySpec query,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) {
    _verifyInsideTransaction();
  }

  /// Always false: nothing is stored. Android: none.
  @override
  bool get isDurable => false;

  /// Android: `NoopPersistenceManager.runInTransaction`: tracks only that a transaction is in progress, to catch
  /// nesting and mutations outside one; rethrows the body's exception as is (Android wraps it).
  @override
  T runInTransaction<T>(T Function() body) {
    // The flag is still tracked, to catch bugs.
    if (_insideTransaction) {
      throw StateError(
        'runInTransaction called when an existing transaction is already in progress.',
      );
    }
    _insideTransaction = true;
    try {
      return body();
    } finally {
      _insideTransaction = false;
    }
  }

  void _verifyInsideTransaction() {
    if (!_insideTransaction) {
      throw StateError('Transaction expected to already be in progress.');
    }
  }
}
