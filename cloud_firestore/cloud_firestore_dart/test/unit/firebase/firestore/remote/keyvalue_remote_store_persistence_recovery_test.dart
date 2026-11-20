// The same on the key-value cache. RemoteStore when the persistence fails (the JS SDK's recovery, see RemoteStore._disableNetworkUntilRecovery): a
// recoverable error takes the network offline until a probe of the persistence succeeds, any other error is thrown.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/kv_codec.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/watch_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../../util/test_util.dart';
import '../local/persistence_test_helpers.dart';
import 'mock_datastore.dart';
import 'remote_store_test.dart' show MockRemoteStoreCallback;

/// A [CacheStore] that throws [nextError] from the next read of a mutation batch (the scan of
/// KvMutationQueue.getNextMutationBatchAfterBatchId, the only scan of one entry in the `mut` table).
class _FlakyStore implements CacheStore {
  _FlakyStore(this._inner);

  final CacheStore _inner;
  Object? nextError;
  int nextBatchReads = 0;

  /// Every read of the next batch fails while set (a page of the mutations table that can not be read).
  Object? batchReadError;

  final Uint8List _mutPrefix = KvKeyWriter().string('mut').bytes;

  @override
  Future<void> open() => _inner.open();

  @override
  Future<void> close() => _inner.close();

  @override
  Future<Uint8List?> get(Uint8List key) => _inner.get(key);

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) {
    if (limit == 1 && !reverse && _startsWith(start, _mutPrefix)) {
      nextBatchReads++;
      if (batchReadError != null) {
        return Future<List<CacheStoreEntry>>.error(batchReadError!);
      }
      final Object? error = nextError;
      if (error != null) {
        nextError = null;
        return Future<List<CacheStoreEntry>>.error(error);
      }
    }
    return _inner.scan(start, end, reverse: reverse, limit: limit);
  }

  @override
  Future<void> write(List<CacheStoreEntry> puts, List<Uint8List> deletes) =>
      _inner.write(puts, deletes);

  static bool _startsWith(Uint8List bytes, Uint8List prefix) {
    if (bytes.length < prefix.length) {
      return false;
    }
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
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
  late CacheStorePersistence persistence;
  late _FlakyStore db;
  late LocalStore localStore;
  late _OnlineStates callback;
  late RemoteStore remoteStore;

  setUp(() async {
    scheduler = TaskScheduler('recovery');
    datastore = MockDatastore(scheduler);
    db = _FlakyStore(MemoryLogStore());
    persistence = await createKeyValuePersistence(store: db);
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

  test('any other failure of the store is recoverable too', () async {
    // The key-value cache makes every error of the store a TransientDatabaseException.
    await localStore.writeLocally(<Mutation>[
      setMutation('foo/bar', map(<String>['a', 'b'])),
    ]);
    db.nextError = StateError('corrupt');

    await remoteStore.start();
    await _settle();

    expect(callback.states, contains(OnlineState.offline));
    expect(datastore.writesSent, 1);
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

    // Not in virtual time as the SQLite variant: under FakeAsync the first snapshot never reached the callback with
    // the key-value cache (cause not found), so this runs in real time.
    // The retry of the backoff is run by hand, so the attempts are told apart without waiting for it.
    test(
      'a full disk is probed with the backoff, not in a loop of reconnects',
      () async {
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
        await remoteStore.start();
        await remoteStore.listen(
          QueryData(query('foo').toTarget(), 2, 1, QueryPurpose.listen),
        );
        await _settle();

        // The first failure is probed at once; the read works, the network comes back, the next snapshot can not be
        // stored either. From then on each attempt waits for the backoff.
        final int first = callback.remoteEvents;
        expect(first, inInclusiveRange(1, 3));
        final int streams = datastore.watchStreamRequestCount;
        await _settle();
        await _settle();
        expect(
          callback.remoteEvents,
          first,
          reason: 'nothing happens between two attempts',
        );
        expect(datastore.watchStreamRequestCount, streams);

        // One attempt per run of the backoff: one reconnect, one snapshot that can not be stored.
        for (int i = 1; i <= 3; i++) {
          await runRecoveryRetry();
          expect(callback.remoteEvents, first + i);
          expect(datastore.watchStreamRequestCount, streams + i);
        }
        expect(callback.storedRemoteEvents, 0);

        // Once there is room again, the next attempt stores the snapshot and the client stays online.
        callback.diskFull = false;
        await runRecoveryRetry();
        expect(callback.storedRemoteEvents, 1);
        expect(callback.states.last, OnlineState.online);
        expect(scheduler.getTask(TaskId.asyncQueueRetry), isNull);
      },
    );

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
