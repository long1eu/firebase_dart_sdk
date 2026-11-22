/// A map-backed storage engine: the reference implementation of [PersistenceStorageEngine] and
/// the engine of persistence tests. Android: `testUtil/.../core/persistence/
/// MockPersistenceStorageEngine.java` (plus rollback, which the Android mock lacks).
///
/// Real code, not a stub: it is part of the frozen test support. It calls the data layer
/// ([CompoundWrite], [Node]), so it works once the data layer is filled.
library;

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/children_node.dart';
import 'package:firebase_database_dart/src/core/snap/indexes/priority_index.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart/src/core/util/node_size_estimator.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';

/// Keeps everything in maps; a transaction that ends without [setTransactionSuccessful] is
/// rolled back. Mutations outside a transaction throw a [StateError] unless
/// [disableTransactionCheck].
///
/// While [isDurable] is true it also checks what only stored data can get wrong (unknown write and
/// tracked query ids, removed keys that are not stored, one id per query): reference-engine
/// checks, not requirements on engines, so the contract does not test them; once degraded or
/// closed it skips them, as a real degraded engine reads as empty.
final class InMemoryPersistenceStorageEngine
    implements PersistenceStorageEngine {
  /// Creates an engine holding [initialWrites].
  InMemoryPersistenceStorageEngine([
    List<UserWriteRecord> initialWrites = const <UserWriteRecord>[],
  ]) {
    for (final UserWriteRecord record in initialWrites) {
      _writes[record.writeId] = record;
    }
  }

  /// Lets tests mutate outside a transaction.
  bool disableTransactionCheck = false;

  /// Receives the warnings of [pruneCache] (null: dropped).
  DatabaseLogger? logger;

  Map<WriteId, UserWriteRecord> _writes = <WriteId, UserWriteRecord>{};
  Map<int, TrackedQuery> _trackedQueries = <int, TrackedQuery>{};
  Map<int, Set<ChildKey>> _trackedQueryKeys = <int, Set<ChildKey>>{};
  CompoundWrite? _serverCacheWrite;

  bool _insideTransaction = false;
  bool _transactionSuccessful = false;
  bool _closed = false;
  _Snapshot? _snapshot;

  CompoundWrite get _serverCache => _serverCacheWrite ??= CompoundWrite.empty;

  set _serverCache(CompoundWrite value) => _serverCacheWrite = value;

  void _verifyInsideTransaction() {
    if (_closed) {
      throw StateError('The storage engine was closed.');
    }
    if (!disableTransactionCheck && !_insideTransaction) {
      throw StateError('Transaction expected to already be in progress.');
    }
  }

  /// A reference-engine check, not a requirement on engines; only while [isDurable].
  void _verifyTracked(int trackedQueryId) {
    if (isDurable && !_trackedQueries.containsKey(trackedQueryId)) {
      throw StateError("Can't track keys for an untracked query.");
    }
  }

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) {
    _verifyInsideTransaction();
    _writes[writeId] = UserWriteRecord.overwrite(
      writeId,
      path,
      node,
      visible: true,
    );
  }

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) {
    _verifyInsideTransaction();
    _writes[writeId] = UserWriteRecord.merge(writeId, path, children);
  }

  @override
  void removeUserWrite(WriteId writeId) {
    _verifyInsideTransaction();
    if (_writes.remove(writeId) == null && isDurable) {
      throw StateError("Tried to remove write that doesn't exist.");
    }
  }

  @override
  List<UserWriteRecord> loadUserWrites() => _writes.values.toList()
    ..sort(
      (UserWriteRecord a, UserWriteRecord b) => a.writeId.compareTo(b.writeId),
    );

  @override
  void removeAllUserWrites() {
    _verifyInsideTransaction();
    _writes.clear();
  }

  @override
  Node serverCache(Path path) =>
      _serverCache.childCompoundWrite(path).apply(ChildrenNode.empty);

  @override
  void overwriteServerCache(Path path, Node node) {
    _verifyInsideTransaction();
    _serverCache = _serverCache.addWrite(path, node);
  }

  @override
  void mergeIntoServerCache(Path path, Node node) {
    _verifyInsideTransaction();
    node.forEachChild(priorityIndex, (ChildKey key, Node child) {
      _serverCache = _serverCache.addWrite(path.child(key), child);
      return false;
    });
  }

  @override
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children) {
    _verifyInsideTransaction();
    _serverCache = _serverCache.addWrites(path, children);
  }

  @override
  int serverCacheEstimatedSizeInBytes() =>
      estimateSerializedNodeSize(_serverCache.apply(ChildrenNode.empty));

  @override
  void saveTrackedQuery(TrackedQuery trackedQuery) {
    _verifyInsideTransaction();
    if (isDurable) {
      // A reference-engine check, not a requirement on engines: TrackedQueryManager owns it.
      final TrackedQuery? existing = _trackedQueries[trackedQuery.id];
      if (existing != null && existing.querySpec != trackedQuery.querySpec) {
        throw StateError(
          'Tracked query id ${trackedQuery.id} reused for another query.',
        );
      }
      for (final TrackedQuery query in _trackedQueries.values) {
        if (query.querySpec == trackedQuery.querySpec &&
            query.id != trackedQuery.id) {
          throw StateError(
            'Query ${trackedQuery.querySpec} is tracked under another id.',
          );
        }
      }
    }
    _trackedQueries[trackedQuery.id] = trackedQuery;
  }

  @override
  void deleteTrackedQuery(int trackedQueryId) {
    _verifyInsideTransaction();
    _trackedQueries.remove(trackedQueryId);
    _trackedQueryKeys.remove(trackedQueryId);
  }

  @override
  List<TrackedQuery> loadTrackedQueries() =>
      _trackedQueries.values.toList()
        ..sort((TrackedQuery a, TrackedQuery b) => a.id.compareTo(b.id));

  @override
  void resetPreviouslyActiveTrackedQueries(int lastUse) {
    if (!_insideTransaction && !disableTransactionCheck) {
      // Its own transaction when called outside one.
      beginTransaction();
      try {
        resetPreviouslyActiveTrackedQueries(lastUse);
        setTransactionSuccessful();
      } finally {
        endTransaction();
      }
      return;
    }
    _verifyInsideTransaction();
    for (final MapEntry<int, TrackedQuery> entry
        in _trackedQueries.entries.toList()) {
      if (entry.value.active) {
        _trackedQueries[entry.key] = entry.value
            .withActiveState(false)
            .withLastUse(lastUse);
      }
    }
  }

  @override
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys) {
    _verifyInsideTransaction();
    _verifyTracked(trackedQueryId);
    _trackedQueryKeys[trackedQueryId] = Set<ChildKey>.of(keys);
  }

  @override
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) {
    _verifyInsideTransaction();
    _verifyTracked(trackedQueryId);
    final Set<ChildKey> keys = _trackedQueryKeys.putIfAbsent(
      trackedQueryId,
      () => <ChildKey>{},
    );
    if (isDurable && !keys.containsAll(removed)) {
      throw StateError("Can't remove keys that don't exist.");
    }
    keys
      ..removeAll(removed)
      ..addAll(added);
  }

  @override
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds) {
    final Set<ChildKey> keys = <ChildKey>{};
    for (final int id in trackedQueryIds) {
      _verifyTracked(id);
      keys.addAll(_trackedQueryKeys[id] ?? const <ChildKey>{});
    }
    return keys;
  }

  @override
  void pruneCache(Path root, PruneForest pruneForest) {
    _verifyInsideTransaction();
    for (final MapEntry<Path, Node> write in _serverCache.entries.toList()) {
      final Path absoluteDataPath = write.key;
      if (root != absoluteDataPath && absoluteDataPath.contains(root)) {
        logger?.call(
          DatabaseLogLevel.warning,
          'We are pruning at $root but we have data stored higher up at '
          '$absoluteDataPath. Ignoring.',
        );
        continue;
      }
      if (!root.contains(absoluteDataPath)) {
        continue;
      }
      final Path dataPath = Path.relative(root, absoluteDataPath);
      final Node dataNode = write.value;
      if (pruneForest.shouldPruneUnkeptDescendants(dataPath)) {
        final CompoundWrite kept = pruneForest
            .childAtPath(dataPath)
            .foldKeptNodes<CompoundWrite>(
              CompoundWrite.empty,
              (Path keepPath, CompoundWrite accumulator) =>
                  accumulator.addWrite(keepPath, dataNode.getChild(keepPath)),
            );
        _serverCache = _serverCache
            .removeWrite(absoluteDataPath)
            .addWrites(absoluteDataPath, kept);
      } else if (!pruneForest.shouldKeep(dataPath)) {
        // Android: SqlPersistenceStorageEngine.java:672-680.
        logger?.call(
          DatabaseLogLevel.warning,
          'We are pruning at $root and have data at $absoluteDataPath that '
          "isn't marked for pruning or keeping. Ignoring.",
        );
      }
    }
  }

  @override
  void beginTransaction() {
    if (_insideTransaction) {
      throw StateError(
        'runInTransaction called when an existing transaction is already in progress.',
      );
    }
    _insideTransaction = true;
    _transactionSuccessful = false;
    _snapshot = _Snapshot(
      Map<WriteId, UserWriteRecord>.of(_writes),
      Map<int, TrackedQuery>.of(_trackedQueries),
      <int, Set<ChildKey>>{
        for (final MapEntry<int, Set<ChildKey>> e in _trackedQueryKeys.entries)
          e.key: Set<ChildKey>.of(e.value),
      },
      _serverCacheWrite,
    );
  }

  @override
  void setTransactionSuccessful() {
    if (!_insideTransaction) {
      throw StateError('No transaction in progress.');
    }
    _transactionSuccessful = true;
  }

  @override
  void endTransaction() {
    if (!_insideTransaction) {
      throw StateError('No transaction in progress.');
    }
    final _Snapshot? snapshot = _snapshot;
    if (!_transactionSuccessful && snapshot != null) {
      _writes = snapshot.writes;
      _trackedQueries = snapshot.trackedQueries;
      _trackedQueryKeys = snapshot.trackedQueryKeys;
      _serverCacheWrite = snapshot.serverCache;
    }
    _snapshot = null;
    _insideTransaction = false;
    _transactionSuccessful = false;
  }

  @override
  void close() => _closed = true;

  @override
  bool get isDurable => !_closed && !_degraded;

  bool _degraded = false;

  /// Simulates a run-time storage failure: the engine becomes degraded for good.
  void degrade() => _degraded = true;
}

final class _Snapshot {
  _Snapshot(
    this.writes,
    this.trackedQueries,
    this.trackedQueryKeys,
    this.serverCache,
  );

  final Map<WriteId, UserWriteRecord> writes;
  final Map<int, TrackedQuery> trackedQueries;
  final Map<int, Set<ChildKey>> trackedQueryKeys;
  final CompoundWrite? serverCache;
}
