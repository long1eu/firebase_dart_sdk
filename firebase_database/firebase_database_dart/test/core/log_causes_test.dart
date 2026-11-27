// Errors whose text can quote user data are logged by type and a fixed reason only, and the
// original stays reachable where the client hands an error on: a throwing transaction update
// function (the error's cause and stack trace) and a storage engine that fails while a server
// push is applied (rethrown by the persistence manager, logged by Repo). Mutations in
// rtdb/from_helper/reports/fix_round/logging_and_urls.md, "Review fixes".
//
// No test answers more than one pending server request.

import 'package:firebase_database_dart/src/core/compound_write.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/src/core/path.dart';
import 'package:firebase_database_dart/src/core/persistence/cache_policy.dart';
import 'package:firebase_database_dart/src/core/persistence/default_persistence_manager.dart';
import 'package:firebase_database_dart/src/core/persistence/persistence_storage_engine.dart';
import 'package:firebase_database_dart/src/core/persistence/prune_forest.dart';
import 'package:firebase_database_dart/src/core/persistence/tracked_query.dart';
import 'package:firebase_database_dart/src/core/snap/child_key.dart';
import 'package:firebase_database_dart/src/core/snap/node.dart';
import 'package:firebase_database_dart/src/core/user_write_record.dart';
import 'package:firebase_database_dart/src/core/write_id.dart';
import 'package:firebase_database_dart/src/testing/in_memory_persistence_storage_engine.dart';
import 'package:test/test.dart';

import 'repo_harness.dart';

const String _secret = 'secret-value';

/// An in-memory engine whose server cache writes throw, with [_secret] in the message, while
/// [failServerWrites] is set.
final class _FailingEngine implements PersistenceStorageEngine {
  final InMemoryPersistenceStorageEngine _inner =
      InMemoryPersistenceStorageEngine();

  bool failServerWrites = false;

  void _check() {
    if (failServerWrites) {
      throw StateError('INSERT failed for $_secret');
    }
  }

  @override
  void overwriteServerCache(Path path, Node node) {
    _check();
    _inner.overwriteServerCache(path, node);
  }

  @override
  void mergeIntoServerCache(Path path, Node node) {
    _check();
    _inner.mergeIntoServerCache(path, node);
  }

  @override
  void mergeIntoServerCacheWrite(Path path, CompoundWrite children) {
    _check();
    _inner.mergeIntoServerCacheWrite(path, children);
  }

  @override
  void saveUserOverwrite(Path path, Node node, WriteId writeId) =>
      _inner.saveUserOverwrite(path, node, writeId);

  @override
  void saveUserMerge(Path path, CompoundWrite children, WriteId writeId) =>
      _inner.saveUserMerge(path, children, writeId);

  @override
  void removeUserWrite(WriteId writeId) => _inner.removeUserWrite(writeId);

  @override
  List<UserWriteRecord> loadUserWrites() => _inner.loadUserWrites();

  @override
  void removeAllUserWrites() => _inner.removeAllUserWrites();

  @override
  Node serverCache(Path path) => _inner.serverCache(path);

  @override
  int serverCacheEstimatedSizeInBytes() =>
      _inner.serverCacheEstimatedSizeInBytes();

  @override
  void saveTrackedQuery(TrackedQuery trackedQuery) =>
      _inner.saveTrackedQuery(trackedQuery);

  @override
  void deleteTrackedQuery(int trackedQueryId) =>
      _inner.deleteTrackedQuery(trackedQueryId);

  @override
  List<TrackedQuery> loadTrackedQueries() => _inner.loadTrackedQueries();

  @override
  void resetPreviouslyActiveTrackedQueries(int lastUse) =>
      _inner.resetPreviouslyActiveTrackedQueries(lastUse);

  @override
  void saveTrackedQueryKeys(int trackedQueryId, Set<ChildKey> keys) =>
      _inner.saveTrackedQueryKeys(trackedQueryId, keys);

  @override
  void updateTrackedQueryKeys(
    int trackedQueryId,
    Set<ChildKey> added,
    Set<ChildKey> removed,
  ) => _inner.updateTrackedQueryKeys(trackedQueryId, added, removed);

  @override
  Set<ChildKey> loadTrackedQueryKeys(Set<int> trackedQueryIds) =>
      _inner.loadTrackedQueryKeys(trackedQueryIds);

  @override
  void pruneCache(Path root, PruneForest pruneForest) =>
      _inner.pruneCache(root, pruneForest);

  @override
  void beginTransaction() => _inner.beginTransaction();

  @override
  void endTransaction() => _inner.endTransaction();

  @override
  void setTransactionSuccessful() => _inner.setTransactionSuccessful();

  @override
  void close() => _inner.close();

  @override
  bool get isDurable => _inner.isDurable;
}

void main() {
  // Mutation T: in core/repo_transactions.dart `_runUpdate`, build the error without
  // `cause: e` and `causeStackTrace: stackTrace`.
  test('a throwing update function: type-only log line, the exception is the '
      "error's cause with its stack trace", () async {
    final RepoHarness h = RepoHarness();
    final StateError thrown = StateError('handler saw $_secret');
    DatabaseError? failure;
    h.repo.startTransaction(
      Path('t'),
      (Object? value) => throw thrown,
      onComplete: (DatabaseError? error, bool committed, Node? node) =>
          failure = error,
    );
    await settle();
    expect(failure, isNotNull);
    expect(failure!.code, DatabaseErrorCode.userCodeException);
    expect(failure!.cause, same(thrown));
    expect(
      failure!.causeStackTrace.toString(),
      contains('log_causes_test.dart'),
    );
    expect(h.logs, contains('error: Caught Throwable. StateError'));
    for (final String line in h.logs) {
      expect(line, isNot(contains(_secret)), reason: line);
    }
  });

  // Mutation S: in core/persistence/default_persistence_manager.dart `runInTransaction`, log
  // `$e` in place of `${e.runtimeType}`.
  test('a storage engine that fails under a server push: type and reason in '
      'the log, never its text', () async {
    final _FailingEngine engine = _FailingEngine();
    final List<String> managerLogs = <String>[];
    final RepoHarness h = RepoHarness(
      persistence: DefaultPersistenceManager(
        engine,
        CachePolicy.none,
        () => DateTime.utc(2026),
        logger: (level, message) => managerLogs.add('${level.name}: $message'),
      ),
    );
    h.listen('S', 'a');
    await settle();
    engine.failServerWrites = true;
    h.server.deliverDataUpdate('a', <String, Object?>{'x': _secret});
    await settle();
    expect(managerLogs, contains('error: Caught Throwable. StateError'));
    expect(
      h.logs,
      contains(
        'error: FIREBASE INTERNAL ERROR at /a: applying server data failed, '
        'in the local cache or the client (StateError)',
      ),
    );
    for (final String line in <String>[...managerLogs, ...h.logs]) {
      expect(line, isNot(contains(_secret)), reason: line);
    }
  });
}
