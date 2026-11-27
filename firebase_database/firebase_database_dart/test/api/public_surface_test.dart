// A compile-level pin of the public API (contract 14_api_contract.md, sections 1 to 7.2).
//
// Every public member is assigned to a variable of its exact static type inside functions that are never
// called. `.exact` yields `T Function(T)` for the receiver's static type T, and a `T Function(T)` is
// assignable to `U Function(U)` only when T and U are the same type, so a member whose type drifts in
// either direction fails `dart analyze`. Enums are pinned by exhaustive switches, so a value added or
// removed fails too.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/src/api/firebase_database_exception.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:test/test.dart';

typedef _Same<T> = T Function(T);

extension _Exact<S> on S {
  _Same<S> get exact =>
      (S value) => value;
}

void main() {
  test('the public surface compiles with its contract types', () {
    expect(<Object>[
      _firebaseDatabase,
      _query,
      _databaseReference,
      _snapshotsAndEvents,
      _transactionsAndOnDisconnect,
      _serverValuesErrorsPersistenceLogging,
      _testingLibrary,
      _storageEngineLibrary,
    ], hasLength(8));
  });

  test('the exception codes are those of C19', () {
    expect(firebaseDatabaseExceptionCodes, <String>[
      'permission-denied',
      'disconnected',
      'max-retries',
      'overridden-by-set',
      'unavailable',
      'network-error',
      'write-canceled',
      'index-not-defined',
      'operation-failed',
      'too-big',
      'database-closed',
      'data-stale',
      'unknown',
    ]);
    // Every core code is public (with this code) or internal (null); a code added to or removed from
    // the core enum fails this switch.
    for (final DatabaseErrorCode c in DatabaseErrorCode.values) {
      final String? public = switch (c) {
        DatabaseErrorCode.dataStale => 'data-stale',
        DatabaseErrorCode.userCodeException => null,
        DatabaseErrorCode.operationFailed => 'operation-failed',
        DatabaseErrorCode.permissionDenied => 'permission-denied',
        DatabaseErrorCode.disconnected => 'disconnected',
        DatabaseErrorCode.maxRetries => 'max-retries',
        DatabaseErrorCode.overriddenBySet => 'overridden-by-set',
        DatabaseErrorCode.unavailable => 'unavailable',
        DatabaseErrorCode.tooBig => 'too-big',
        DatabaseErrorCode.networkError => 'network-error',
        DatabaseErrorCode.writeCanceled => 'write-canceled',
        DatabaseErrorCode.indexNotDefined => 'index-not-defined',
        DatabaseErrorCode.databaseClosed => 'database-closed',
        DatabaseErrorCode.unknown => 'unknown',
      };
      if (public == null) {
        expect(firebaseDatabaseExceptionCodes, isNot(contains(c.code)));
      } else {
        expect(c.code, public);
        expect(firebaseDatabaseExceptionCodes, contains(public));
      }
    }
  });

  test('server statuses map to public codes', () {
    FirebaseDatabaseException fromServer(String status, [String? reason]) =>
        exceptionFromDatabaseError(DatabaseError.fromStatus(status, reason));

    expect(fromServer('no_index').code, 'index-not-defined');
    expect(fromServer('too_big').code, 'too-big');
    expect(fromServer('failure').code, 'operation-failed');
    expect(fromServer('permission_denied').code, 'permission-denied');
    expect(fromServer('datastale').code, 'data-stale');
    for (final String other in <String>[
      'invalid_parameters',
      'internal_error',
      'unknown',
      'expired_token',
      'invalid_token',
    ]) {
      expect(fromServer(other).code, 'unknown');
    }
    final FirebaseDatabaseException e = fromServer('internal_error', 'boom');
    expect(e.code, 'unknown');
    expect(e.message, 'boom');
    expect(e.serverStatus, 'internal_error: boom');
    final FirebaseDatabaseException bare = fromServer('internal_error');
    expect(bare.message, 'An unknown error occurred.');
    expect(bare.serverStatus, 'internal_error');
    final FirebaseDatabaseException denied = fromServer(
      'permission_denied',
      'Permission denied',
    );
    expect(
      denied.message,
      'This client does not have permission to perform this operation.',
    );
    expect(denied.serverStatus, 'permission_denied: Permission denied');
  });

  test('a local error has no server status', () {
    final StateError cause = StateError('x');
    final FirebaseDatabaseException e = exceptionFromDatabaseError(
      DatabaseError.local(
        DatabaseErrorCode.unknown,
        'get() failed.',
        cause: cause,
      ),
    );
    expect(e.code, 'unknown');
    expect(e.message, 'get() failed.');
    expect(e.cause, same(cause));
    expect(e.serverStatus, isNull);
  });
}

// Section 1.
void _firebaseDatabase(FirebaseApp app, FirebaseDatabase db) {
  final _Same<
    FirebaseDatabase Function(
      FirebaseApp, {
      String? databaseUrl,
      String? emulatorHost,
      String? mockUserToken,
      DatabasePersistence? persistence,
      DatabaseLogger? logger,
      DateTime Function()? clock,
      double Function()? random,
    })
  >
  _ = FirebaseDatabase.new.exact;
  final _Same<String?> _ = FirebaseDatabase.emulatorHostFromEnvironment.exact;
  final _Same<FirebaseApp> _ = db.app.exact;
  final _Same<Uri> _ = db.databaseUrl.exact;
  final _Same<DatabaseReference Function([String])> _ = db.ref.exact;
  final _Same<DatabaseReference Function(String)> _ = db.refFromUrl.exact;
  final _Same<void Function()> _ = db.goOffline.exact;
  final _Same<void Function()> _ = db.goOnline.exact;
  final _Same<Future<void> Function()> _ = db.purgeOutstandingWrites.exact;
  final _Same<Stream<bool>> _ = db.onConnected.exact;
  final _Same<bool> _ = db.isConnected.exact;
  final _Same<Duration> _ = db.serverTimeOffset.exact;
  final _Same<DateTime> _ = db.estimatedServerTime.exact;
  final _Same<bool> _ = db.persistenceEnabled.exact;
  final _Same<Future<void> Function()> _ = db.close.exact;
  // Defaults of optional parameters.
  final DatabaseReference _ = db.ref();
}

// Section 2, Query.
void _query(Query q) {
  final _Same<FirebaseDatabase> _ = q.database.exact;
  final _Same<DatabaseReference> _ = q.ref.exact;
  final _Same<String> _ = q.path.exact;
  final _Same<Uri> _ = q.url.exact;
  final _Same<Query Function(String)> _ = q.orderByChild.exact;
  final _Same<Query Function()> _ = q.orderByKey.exact;
  final _Same<Query Function()> _ = q.orderByValue.exact;
  final _Same<Query Function()> _ = q.orderByPriority.exact;
  final _Same<Query Function(Object?, {String? key})> _ = q.startAt.exact;
  final _Same<Query Function(Object?, {String? key})> _ = q.startAfter.exact;
  final _Same<Query Function(Object?, {String? key})> _ = q.endAt.exact;
  final _Same<Query Function(Object?, {String? key})> _ = q.endBefore.exact;
  final _Same<Query Function(Object?, {String? key})> _ = q.equalTo.exact;
  final _Same<Query Function(int)> _ = q.limitToFirst.exact;
  final _Same<Query Function(int)> _ = q.limitToLast.exact;
  final _Same<Future<DataSnapshot> Function()> _ = q.get.exact;
  final _Same<Future<DatabaseEvent> Function([DatabaseEventType])> _ =
      q.once.exact;
  final _Same<Stream<DatabaseEvent>> _ = q.onValue.exact;
  final _Same<Stream<DatabaseEvent>> _ = q.onChildAdded.exact;
  final _Same<Stream<DatabaseEvent>> _ = q.onChildChanged.exact;
  final _Same<Stream<DatabaseEvent>> _ = q.onChildMoved.exact;
  final _Same<Stream<DatabaseEvent>> _ = q.onChildRemoved.exact;
  final _Same<Stream<DatabaseEvent>> _ = q.onChildEvents.exact;
  final _Same<Future<void> Function(bool)> _ = q.keepSynced.exact;
  final _Same<bool> _ = (q == q).exact;
  final _Same<int> _ = q.hashCode.exact;
  final Future<DatabaseEvent> _ = q.once();
}

// Section 2, DatabaseReference and TransactionHandler.
void _databaseReference(DatabaseReference r) {
  final Query _ = r;
  final _Same<String?> _ = r.key.exact;
  final _Same<DatabaseReference?> _ = r.parent.exact;
  final _Same<DatabaseReference> _ = r.root.exact;
  final _Same<DatabaseReference Function(String)> _ = r.child.exact;
  final _Same<DatabaseReference Function()> _ = r.push.exact;
  final _Same<Future<void> Function(Object?, {Object? priority})> _ =
      r.set.exact;
  final _Same<Future<void> Function(Map<String, Object?>)> _ = r.update.exact;
  final _Same<Future<void> Function(Object?)> _ = r.setPriority.exact;
  final _Same<Future<void> Function()> _ = r.remove.exact;
  final _Same<
    Future<TransactionResult> Function(TransactionHandler, {bool applyLocally})
  >
  _ = r.runTransaction.exact;
  final _Same<OnDisconnect> _ = r.onDisconnect.exact;
  Transaction handler(Object? current) => const Transaction.abort();
  final _Same<TransactionHandler> _ = handler.exact;
  final Future<TransactionResult> _ = r.runTransaction(handler);
}

// Section 3.
void _snapshotsAndEvents(DataSnapshot s, DatabaseEvent e) {
  final _Same<DatabaseReference> _ = s.ref.exact;
  final _Same<String?> _ = s.key.exact;
  final _Same<bool> _ = s.exists.exact;
  final _Same<Object?> _ = s.value.exact;
  final _Same<Object?> _ = s.priority.exact;
  final _Same<DataSnapshot Function(String)> _ = s.child.exact;
  final _Same<bool Function(String)> _ = s.hasChild.exact;
  final _Same<bool> _ = s.hasChildren.exact;
  final _Same<int> _ = s.childrenCount.exact;
  final _Same<Iterable<DataSnapshot>> _ = s.children.exact;
  final _Same<Object? Function()> _ = s.toJson.exact;

  final _Same<DatabaseEventType> _ = e.type.exact;
  final _Same<DataSnapshot> _ = e.snapshot.exact;
  final _Same<String?> _ = e.previousChildKey.exact;

  final int _ = switch (e.type) {
    DatabaseEventType.value => 0,
    DatabaseEventType.childAdded => 1,
    DatabaseEventType.childChanged => 2,
    DatabaseEventType.childMoved => 3,
    DatabaseEventType.childRemoved => 4,
  };
}

// Section 5.
void _transactionsAndOnDisconnect(TransactionResult t, OnDisconnect o) {
  final _Same<Transaction Function(Object?, {Object? priority})> _ =
      Transaction.success.exact;
  final _Same<Transaction Function()> _ = Transaction.abort.exact;
  const Transaction _ = Transaction.success(1, priority: 'p');
  const Transaction _ = Transaction.abort();

  final _Same<bool> _ = t.committed.exact;
  final _Same<DataSnapshot> _ = t.snapshot.exact;

  final _Same<Future<void> Function(Object?, {Object? priority})> _ =
      o.set.exact;
  final _Same<Future<void> Function(Map<String, Object?>)> _ = o.update.exact;
  final _Same<Future<void> Function()> _ = o.remove.exact;
  final _Same<Future<void> Function()> _ = o.cancel.exact;
}

// Section 6.
void _serverValuesErrorsPersistenceLogging(
  FirebaseDatabaseException x,
  DatabasePersistence p,
  DatabaseLogLevel level,
) {
  const Object _ = ServerValue.timestamp;
  final _Same<Object> _ = ServerValue.timestamp.exact;
  final _Same<Object Function(num)> _ = ServerValue.increment.exact;

  final _Same<
    FirebaseDatabaseException Function({
      required String code,
      required String message,
      String? serverStatus,
      Object? cause,
      StackTrace? stackTrace,
    })
  >
  _ = FirebaseDatabaseException.new.exact;
  const FirebaseDatabaseException _ = FirebaseDatabaseException(
    code: 'unknown',
    message: 'm',
  );
  final FirebaseException _ = x;
  final _Same<String?> _ = x.serverStatus.exact;
  final _Same<Object?> _ = x.cause.exact;
  final _Same<String> _ = x.code.exact;
  final _Same<String> _ = x.plugin.exact;
  final _Same<String?> _ = x.message.exact;
  final _Same<StackTrace?> _ = x.stackTrace.exact;

  final Object _ = p;

  void logger(DatabaseLogLevel l, String m) {}
  final _Same<DatabaseLogger> _ = logger.exact;
  final int _ = switch (level) {
    DatabaseLogLevel.debug => 0,
    DatabaseLogLevel.info => 1,
    DatabaseLogLevel.warning => 2,
    DatabaseLogLevel.error => 3,
  };
}

// Section 7.1.
void _testingLibrary(FirebaseApp app, FakeDatabaseServer server) {
  final _Same<FakeDatabaseServer Function()> _ = FakeDatabaseServer.new.exact;
  final _Same<bool> _ = server.acceptConnections.exact;
  server.acceptConnections = false;
  final _Same<int> _ = server.connectionAttempts.exact;
  final _Same<List<String>> _ = server.requests.exact;
  final _Same<void Function(String, Object?, {Map<String, Object?>? query})> _ =
      server.answerListen.exact;
  final _Same<void Function(String, String, {Map<String, Object?>? query})> _ =
      server.failListen.exact;
  final _Same<void Function(String, Object?)> _ = server.push.exact;
  final _Same<void Function(String, String, {Map<String, Object?>? query})> _ =
      server.cancelListen.exact;
  final _Same<List<String?>> _ = server.receivedAuthTokens.exact;
  final _Same<DateTime?> _ = server.serverTime.exact;
  final _Same<void Function({bool outOfOrder})> _ = server.ackLastWrite.exact;
  final _Same<void Function(String, {bool outOfOrder})> _ =
      server.failLastWrite.exact;
  final _Same<void Function({bool outOfOrder})> _ =
      server.ackLastOnDisconnect.exact;
  final _Same<void Function()> _ = server.ackNextWrite.exact;
  final _Same<void Function(String)> _ = server.failNextWrite.exact;
  final _Same<void Function()> _ = server.ackNextOnDisconnect.exact;
  final _Same<void Function(String, Object?)> _ = server.answerGet.exact;
  final _Same<void Function(String, String)> _ = server.failGet.exact;
  final _Same<void Function()> _ = server.dropConnection.exact;
  final _Same<void Function()> _ = server.revokeAuth.exact;
  final _Same<void Function(String)> _ = server.kill.exact;

  final _Same<
    FirebaseDatabase Function(
      FirebaseApp,
      FakeDatabaseServer, {
      DatabasePersistence? persistence,
      DatabaseLogger? logger,
      Duration reconnectDelay,
    })
  >
  _ = databaseWithFakeServer.exact;
  final _Same<DatabasePersistence Function({Map<String, Object?> serverCache})>
  _ = fakePersistence.exact;
  final FirebaseDatabase _ = databaseWithFakeServer(app, server);
  final DatabasePersistence _ = fakePersistence();
}

// Section 7.2.
void _storageEngineLibrary(
  PersistenceStorageEngineOpener opener,
  PersistenceKey key,
  PersistenceStorageEngine e,
  UserWriteRecord w,
  TrackedQuery t,
) {
  final _Same<
    DatabasePersistence Function({
      required PersistenceStorageEngineOpener opener,
      int? cacheSizeBytes,
      bool cacheServerData,
    })
  >
  _ = databasePersistence.exact;
  final _Same<
    Future<PersistenceStorageEngine> Function(
      PersistenceKey, {
      DatabaseLogger? logger,
    })
  >
  _ = opener.exact;
  final DatabasePersistence _ = databasePersistence(opener: opener);

  final _Same<String> _ = key.appName.exact;
  final _Same<Uri> _ = key.databaseUrl.exact;

  final _Same<void Function(Path, Node, int)> _ = e.saveUserOverwrite.exact;
  final _Same<void Function(Path, CompoundWrite, int)> _ =
      e.saveUserMerge.exact;
  final _Same<void Function(int)> _ = e.removeUserWrite.exact;
  final _Same<List<UserWriteRecord> Function()> _ = e.loadUserWrites.exact;
  final _Same<void Function()> _ = e.removeAllUserWrites.exact;
  final _Same<Node Function(Path)> _ = e.serverCache.exact;
  final _Same<void Function(Path, Node)> _ = e.overwriteServerCache.exact;
  final _Same<void Function(Path, Node)> _ = e.mergeIntoServerCache.exact;
  final _Same<void Function(Path, CompoundWrite)> _ =
      e.mergeIntoServerCacheWrite.exact;
  final _Same<int Function()> _ = e.serverCacheEstimatedSizeInBytes.exact;
  final _Same<void Function(TrackedQuery)> _ = e.saveTrackedQuery.exact;
  final _Same<void Function(int)> _ = e.deleteTrackedQuery.exact;
  final _Same<List<TrackedQuery> Function()> _ = e.loadTrackedQueries.exact;
  final _Same<void Function(int)> _ =
      e.resetPreviouslyActiveTrackedQueries.exact;
  final _Same<void Function(int, Set<ChildKey>)> _ =
      e.saveTrackedQueryKeys.exact;
  final _Same<void Function(int, Set<ChildKey>, Set<ChildKey>)> _ =
      e.updateTrackedQueryKeys.exact;
  final _Same<Set<ChildKey> Function(Set<int>)> _ =
      e.loadTrackedQueryKeys.exact;
  final _Same<void Function(Path, PruneForest)> _ = e.pruneCache.exact;
  final _Same<void Function()> _ = e.beginTransaction.exact;
  final _Same<void Function()> _ = e.setTransactionSuccessful.exact;
  final _Same<void Function()> _ = e.endTransaction.exact;
  final _Same<void Function()> _ = e.close.exact;
  final _Same<bool> _ = e.isDurable.exact;

  final _Same<int> _ = w.writeId.exact;
  final _Same<Path> _ = w.path.exact;
  final _Same<Node?> _ = w.overwrite.exact;
  final _Same<CompoundWrite?> _ = w.merge.exact;
  final _Same<bool> _ = w.visible.exact;

  final _Same<int> _ = t.id.exact;
  final _Same<QuerySpec> _ = t.querySpec.exact;
  final _Same<int> _ = t.lastUse.exact;
  final _Same<bool> _ = t.complete.exact;
  final _Same<bool> _ = t.active.exact;

  final PersistenceStorageEngine _ = InMemoryPersistenceStorageEngine();
}
