// RemoteStore when the persistence fails (the JS SDK's recovery, see RemoteStore._disableNetworkUntilRecovery): a
// recoverable error takes the network offline until a probe of the persistence succeeds, any other error is thrown.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:fake_async/fake_async.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import '../local/mock/database_mock.dart';
import 'mock_datastore.dart';
import 'remote_store_test.dart' show MockRemoteStoreCallback;

/// The database of a SQLite cache that throws [nextError] from the next read of a mutation batch (the query of
/// SQLiteMutationQueue.getNextMutationBatchAfterBatchId).
class _FlakyDatabase implements Database {
  _FlakyDatabase(this._inner);

  final Database _inner;
  Object? nextError;
  int nextBatchReads = 0;

  /// Every read of the next batch fails while set (a page of the mutations table that can not be read).
  Object? batchReadError;

  @override
  String get path => _inner.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) =>
      _inner.execute(statement, arguments);

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) {
    if (statement.contains('FROM mutations') &&
        statement.contains('batch_id >=')) {
      nextBatchReads++;
      if (batchReadError != null) {
        return Future<List<Map<String, dynamic>>>.error(batchReadError!);
      }
      final Object? error = nextError;
      if (error != null) {
        nextError = null;
        return Future<List<Map<String, dynamic>>>.error(error);
      }
    }
    return _inner.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) =>
      _inner.delete(statement, arguments);

  @override
  void close() => _inner.close();
}

class _OnlineStates extends MockRemoteStoreCallback {
  final List<OnlineState> states = <OnlineState>[];

  /// Remote events can not be stored while set (a disk that is full: reads work, writes do not).
  bool diskFull = false;
  int remoteEvents = 0;
  int storedRemoteEvents = 0;

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {
    remoteEvents++;
    if (diskFull) {
      throw TransientDatabaseException('database or disk is full');
    }
    storedRemoteEvents++;
  }

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    states.add(onlineState);
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late TaskScheduler scheduler;
  late MockDatastore datastore;
  late SQLitePersistence persistence;
  late _FlakyDatabase db;
  late LocalStore localStore;
  late _OnlineStates callback;
  late RemoteStore remoteStore;
  late String name;

  setUp(() async {
    scheduler = TaskScheduler('recovery');
    datastore = MockDatastore(scheduler);
    name = 'recovery-${const Uuid().v4()}';
    final DatabaseId databaseId = DatabaseId.forProject('projectId');
    persistence = await SQLitePersistence.create(
      name,
      databaseId,
      LocalSerializer(RemoteSerializer(databaseId)),
      (
        String path, {
        int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen,
      }) async => db = _FlakyDatabase(
        await DatabaseMock.create(
          name,
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen,
        ),
      ),
      const LruGarbageCollectorParams(),
    );
    await persistence.start();
    localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    callback = _OnlineStates();
    remoteStore = RemoteStore(
      callback,
      localStore,
      datastore,
      BehaviorSubject<bool>.seeded(true),
      scheduler,
    );
  });

  tearDown(() async {
    await remoteStore.shutdown();
    await persistence.shutdown();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  test(
    'a recoverable failure to read the next write goes offline and back',
    () async {
      await localStore.writeLocally(<Mutation>[
        setMutation('foo/bar', map(<String>['a', 'b'])),
      ]);
      db.nextError = TransientDatabaseException('locked');

      await remoteStore.start();
      await _settle();

      // The failed read took the network offline; the probe that runs right away succeeded and brought it back, and
      // the write went out once (the refill after the recovery must not add the batch to the pipeline again).
      expect(callback.states, contains(OnlineState.offline));
      expect(db.nextBatchReads, greaterThan(1));
      expect(datastore.writesSent, 1);
    },
  );

  test('any other failure to read the next write is thrown', () async {
    await remoteStore.start();
    db.nextError = StateError('corrupt');
    await expectLater(remoteStore.fillWritePipeline(), throwsStateError);
    expect(callback.states, isNot(contains(OnlineState.offline)));
  });

  group('a credential change', () {
    late int requests;

    setUp(() async {
      await remoteStore.start();
      await remoteStore.listen(
        QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen),
      );
      await _settle();
      requests = datastore.watchStreamRequestCount;
      expect(requests, greaterThan(0));
    });

    test('whose user switch fails for another reason restarts the network and '
        'rethrows', () async {
      await expectLater(
        remoteStore.handleCredentialChange(
          () async => throw StateError('switch failed'),
        ),
        throwsStateError,
      );
      await _settle();
      // The listen was sent again on the restarted watch stream.
      expect(datastore.watchStreamRequestCount, greaterThan(requests));
    });

    test(
      'whose user switch fails with a recoverable error stays offline',
      () async {
        await expectLater(
          remoteStore.handleCredentialChange(
            () async => throw TransientDatabaseException('locked'),
          ),
          throwsA(isA<TransientDatabaseException>()),
        );
        await _settle();
        expect(datastore.watchStreamRequestCount, requests);

        // The retry of the change succeeds: the network comes back.
        await remoteStore.handleCredentialChange(() async {});
        await _settle();
        expect(datastore.watchStreamRequestCount, greaterThan(requests));
      },
    );
  });

  group('a persistence that keeps failing', () {
    /// Runs the retry of the persistence that is scheduled, if any, and lets what it starts settle.
    Future<void> runRecoveryRetry() async {
      expect(
        scheduler.getTask(TaskId.asyncQueueRetry),
        isNotNull,
        reason: 'the next attempt waits for the backoff',
      );
      scheduler.runUntil(TaskId.asyncQueueRetry);
      await _settle();
    }

    // In virtual time: the attempts are told apart by the time between them, and with real timers a slow machine
    // (x64 under emulation) can still be finishing the first round when the test looks for the quiet between two.
    // The persistence (SQLite through FFI) answers synchronously, so nothing here waits for real I/O.
    test('a full disk is probed with the backoff, not in a loop of reconnects', () async {
      final FakeAsync virtual = FakeAsync();
      late RemoteStore remoteStore;
      virtual.run((FakeAsync async) {
        // A remote store whose scheduler, timers and streams live in virtual time, on the cache of setUp.
        final TaskScheduler scheduler = TaskScheduler('recovery-virtual');
        final MockDatastore datastore = MockDatastore(scheduler);
        remoteStore = RemoteStore(
          callback,
          localStore,
          datastore,
          BehaviorSubject<bool>.seeded(true),
          scheduler,
        );
        void settle() => async.elapse(const Duration(milliseconds: 50));
        void runRecoveryRetry() {
          expect(
            scheduler.getTask(TaskId.asyncQueueRetry),
            isNotNull,
            reason: 'the next attempt waits for the backoff',
          );
          scheduler.runUntil(TaskId.asyncQueueRetry);
          settle();
        }

        // A backend that answers every listen with a consistent snapshot.
        int snapshot = 1;
        datastore.onWatchQuery = (QueryData queryData) {
          unawaited(
            Future<void>(() async {
              await datastore.writeWatchChange(
                WatchChangeWatchTargetChange(WatchTargetChangeType.added, <int>[
                  queryData.targetId,
                ]),
                SnapshotVersion.none,
              );
              await datastore.writeWatchChange(
                WatchChangeWatchTargetChange(
                  WatchTargetChangeType.current,
                  <int>[queryData.targetId],
                  resumeToken(snapshot),
                ),
                SnapshotVersion.none,
              );
              await datastore.writeWatchChange(
                WatchChangeWatchTargetChange(
                  WatchTargetChangeType.noChange,
                  <int>[],
                ),
                version(1000 * snapshot++),
              );
            }),
          );
        };
        callback.diskFull = true;
        bool listening = false;
        remoteStore
            .start()
            .then(
              (_) => remoteStore.listen(
                QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen),
              ),
            )
            .then((_) => listening = true);
        settle();
        expect(listening, isTrue);

        // The first failure is probed at once; the read works, the network comes back, the next snapshot can not
        // be stored either. From then on each attempt waits for the backoff.
        final int first = callback.remoteEvents;
        expect(first, inInclusiveRange(1, 3));
        final int streams = datastore.watchStreamRequestCount;
        settle();
        settle();
        expect(
          callback.remoteEvents,
          first,
          reason: 'nothing happens between two attempts',
        );
        expect(datastore.watchStreamRequestCount, streams);

        // One attempt per run of the backoff: one reconnect, one snapshot that can not be stored.
        for (int i = 1; i <= 3; i++) {
          runRecoveryRetry();
          expect(callback.remoteEvents, first + i);
          expect(datastore.watchStreamRequestCount, streams + i);
        }
        expect(callback.storedRemoteEvents, 0);

        // Once there is room again, the next attempt stores the snapshot and the client stays online.
        callback.diskFull = false;
        runRecoveryRetry();
        expect(callback.storedRemoteEvents, 1);
        expect(callback.states.last, OnlineState.online);
        expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
      });

      // The shutdown also waits for work of the persistence, which setUp started outside virtual time: let real and
      // virtual time take turns until it is done.
      bool stopped = false;
      virtual.run(
        (FakeAsync _) => remoteStore.shutdown().then((_) => stopped = true),
      );
      for (int i = 0; i < 500 && !stopped; i++) {
        await Future<void>.delayed(Duration.zero);
        virtual.elapse(const Duration(milliseconds: 10));
      }
      expect(stopped, isTrue);
    });

    test(
      'a write that can not be read is probed with that read, so the network stays offline',
      () async {
        await localStore.writeLocally(<Mutation>[
          setMutation('foo/bar', map(<String>['a', 'b'])),
        ]);
        db.batchReadError = TransientDatabaseException('disk I/O error');

        await remoteStore.start();
        await _settle();
        await _settle();
        expect(callback.states, <OnlineState>[OnlineState.offline]);
        // The read of the pipeline, the probe right away, and the first retry (its backoff starts at 0).
        final int reads = db.nextBatchReads;
        expect(reads, lessThanOrEqualTo(3));

        // Each run of the backoff reads the batch once and does not bring the network back.
        for (int i = 1; i <= 3; i++) {
          await runRecoveryRetry();
          expect(db.nextBatchReads, reads + i);
        }
        expect(callback.states, <OnlineState>[OnlineState.offline]);
        expect(datastore.writesSent, 0);

        db.batchReadError = null;
        await runRecoveryRetry();
        expect(datastore.writesSent, 1);
      },
    );
  });
}
