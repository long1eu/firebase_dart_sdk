// The key-value cache when its store fails: a write, a get or a scan that throws, and a process that dies before or
// after a write (simulated by dropping the persistence without closing it and opening a new one over the same data).
// The cache must stay usable after a failure, and hold the state of the last completed write after a crash, with the
// pending writes neither lost nor duplicated.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_event.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:rxdart/subjects.dart';
import 'package:test/test.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../../util/test_util.dart';
import '../remote/mock_datastore.dart';
import '../remote/remote_store_test.dart' show MockRemoteStoreCallback;
import 'persistence_test_helpers.dart';

/// The process died: every later call of the store fails.
class StoreCrashed implements Exception {
  @override
  String toString() => 'StoreCrashed';
}

/// When the process dies, around the next write of the store.
enum CrashPoint {
  /// Before the write reaches the store: it is not kept.
  beforeWrite,

  /// After the write is durable, before the SDK learns it completed.
  afterWrite,
}

/// A store over the data of [inner] that fails or crashes when told. A new [FaultyStore] over the same [inner] is the
/// same storage opened by a new process.
class FaultyStore implements CacheStore {
  FaultyStore(this.inner);

  final CacheStore inner;

  bool dead = false;

  /// The next write throws without writing anything; the store stays usable.
  bool failNextWrite = false;

  /// The next get or scan throws.
  bool failNextRead = false;

  /// The process dies at the next write.
  CrashPoint? crash;

  int writes = 0;

  void _checkAlive() {
    if (dead) {
      throw StoreCrashed();
    }
  }

  void _checkRead() {
    _checkAlive();
    if (failNextRead) {
      failNextRead = false;
      throw StateError('the read failed');
    }
  }

  @override
  Future<void> open() async {
    _checkAlive();
    await inner.open();
  }

  @override
  Future<void> close() async {
    _checkAlive();
    await inner.close();
  }

  @override
  Future<Uint8List?> get(Uint8List key) async {
    _checkRead();
    return inner.get(key);
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) async {
    _checkRead();
    return inner.scan(start, end, reverse: reverse, limit: limit);
  }

  @override
  Future<void> write(
    List<CacheStoreEntry> puts,
    List<Uint8List> deletes,
  ) async {
    _checkAlive();
    if (crash == CrashPoint.beforeWrite) {
      dead = true;
      throw StoreCrashed();
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('the disk is full');
    }
    await inner.write(puts, deletes);
    writes++;
    if (crash == CrashPoint.afterWrite) {
      dead = true;
      throw StoreCrashed();
    }
  }
}

/// A client of the cache: the persistence and the local store over a [FaultyStore].
class _Client {
  _Client._(this.store, this.persistence, this.localStore);

  final FaultyStore store;
  final CacheStorePersistence persistence;
  final LocalStore localStore;

  /// Opens a new client over [inner], as a new process would.
  static Future<_Client> open(CacheStore inner) async {
    final FaultyStore store = FaultyStore(inner);
    final CacheStorePersistence persistence = await createKeyValuePersistence(
      store: store,
    );
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    return _Client._(store, persistence, localStore);
  }

  /// The batches of the queue, in order, as the remote store sends them.
  Future<List<MutationBatch>> pending() async {
    final List<MutationBatch> batches = <MutationBatch>[];
    int after = MutationBatch.unknown;
    while (true) {
      final MutationBatch? next = await localStore.getNextMutationBatch(after);
      if (next == null) {
        return batches;
      }
      batches.add(next);
      after = next.batchId;
    }
  }

  Future<void> acknowledge(MutationBatch batch, int atVersion) =>
      localStore.acknowledgeBatch(
        MutationBatchResult.create(batch, version(atVersion), <MutationResult>[
          for (final Mutation _ in batch.mutations)
            MutationResult(version(atVersion)),
        ], Uint8List(0)),
      );

  /// The data of the document [path] in the local view, or null when it does not exist.
  Future<Map<String, Object?>?> read(String path) async {
    final MaybeDocument? document = await localStore.readDocument(key(path));
    return document is Document ? document.data.value : null;
  }
}

Matcher _transient = isA<TransientDatabaseException>();

void main() {
  group('a store that fails', () {
    late MemoryLogStore inner;
    late _Client client;

    setUp(() async {
      inner = MemoryLogStore();
      client = await _Client.open(inner);
    });

    test('a failed write is not stored, and the next one is', () async {
      await client.localStore.writeLocally(<Mutation>[
        setMutation('c/a', map(<Object?>['v', 1])),
      ]);
      client.store.failNextWrite = true;
      await expectLater(
        client.localStore.writeLocally(<Mutation>[
          setMutation('c/b', map(<Object?>['v', 2])),
        ]),
        throwsA(_transient),
      );
      expect(await client.read('c/b'), isNull);
      expect(await client.localStore.getPendingWriteCount(), 1);

      await client.localStore.writeLocally(<Mutation>[
        setMutation('c/c', map(<Object?>['v', 3])),
      ]);
      expect(await client.read('c/c'), <String, Object?>{'v': 3});
      final List<MutationBatch> pending = await client.pending();
      expect(pending.map((MutationBatch b) => b.keys.single), <DocumentKey>[
        key('c/a'),
        key('c/c'),
      ]);
      expect(pending[1].batchId, greaterThan(pending[0].batchId));
      expect(await client.localStore.getPendingWriteCount(), 2);

      // And a new process sees the same.
      final _Client reopened = await _Client.open(inner);
      expect(
        (await reopened.pending()).map((MutationBatch b) => b.batchId),
        pending.map((MutationBatch b) => b.batchId),
      );
      expect(await reopened.read('c/b'), isNull);
    });

    test(
      'a failed acknowledgement keeps the batch, the retry removes it',
      () async {
        await client.localStore.writeLocally(<Mutation>[
          setMutation('c/a', map(<Object?>['v', 1])),
        ]);
        final MutationBatch batch = (await client.pending()).single;
        client.store.failNextWrite = true;
        await expectLater(client.acknowledge(batch, 5), throwsA(_transient));
        expect(await client.localStore.getPendingWriteCount(), 1);
        expect((await client.pending()).single.batchId, batch.batchId);

        await client.acknowledge(batch, 5);
        expect(await client.localStore.getPendingWriteCount(), 0);
        expect(await client.read('c/a'), <String, Object?>{'v': 1});
      },
    );

    test('a failed remote event changes nothing, its retry applies', () async {
      final QueryData target = await client.localStore.allocateTarget(
        query('c').toTarget(),
      );
      final RemoteEvent event = addedRemoteEvent(
        doc('c/a', 10, map(<Object?>['v', 1])),
        <int>[target.targetId],
        <int>[],
      );
      client.store.failNextWrite = true;
      await expectLater(
        client.localStore.applyRemoteEvent(event),
        throwsA(_transient),
      );
      expect(await client.read('c/a'), isNull);
      expect(
        await client.localStore.readLastRemoteSnapshotVersion(),
        version(0),
      );

      await client.localStore.applyRemoteEvent(event);
      expect(await client.read('c/a'), <String, Object?>{'v': 1});
      expect(
        await client.localStore.readLastRemoteSnapshotVersion(),
        version(10),
      );
    });

    test('a failed read fails the transaction, the next one works', () async {
      final int writes = client.store.writes;
      client.store.failNextRead = true;
      await expectLater(
        client.localStore.writeLocally(<Mutation>[
          setMutation('c/a', map(<Object?>['v', 1])),
        ]),
        throwsA(_transient),
      );
      expect(client.store.writes, writes);
      client.store.failNextRead = true;
      await expectLater(client.read('c/a'), throwsA(_transient));
      expect(await client.read('c/a'), isNull);

      await client.localStore.writeLocally(<Mutation>[
        setMutation('c/a', map(<Object?>['v', 1])),
      ]);
      expect(await client.read('c/a'), <String, Object?>{'v': 1});
    });

    test('the error of the store is kept as the cause', () async {
      client.store.failNextWrite = true;
      final Object error = await client.localStore
          .writeLocally(<Mutation>[setMutation('c/a', map())])
          .then<Object>((_) => fail('no error'), onError: (Object e) => e);
      expect(error, _transient);
      expect((error as TransientDatabaseException).cause, isStateError);
    });

    test(
      'the remote store goes offline when a read fails, and comes back',
      () async {
        await client.localStore.writeLocally(<Mutation>[
          setMutation('c/a', map(<Object?>['v', 1])),
        ]);
        final TaskScheduler scheduler = TaskScheduler('kv-recovery');
        final MockDatastore datastore = MockDatastore(scheduler);
        final _OnlineStates callback = _OnlineStates();
        final RemoteStore remoteStore = RemoteStore(
          callback,
          client.localStore,
          datastore,
          BehaviorSubject<bool>.seeded(true),
          scheduler,
        );
        client.store.failNextRead = true;
        await remoteStore.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(callback.states, contains(OnlineState.offline));
        expect(datastore.writesSent, 1);
        await remoteStore.shutdown();
      },
    );
  });

  group('a crash', () {
    for (final CrashPoint point in CrashPoint.values) {
      test('${point.name} of a local write', () async {
        final MemoryLogStore inner = MemoryLogStore();
        final _Client client = await _Client.open(inner);
        await client.localStore.writeLocally(<Mutation>[
          setMutation('c/a', map(<Object?>['v', 1])),
        ]);
        client.store.crash = point;
        await expectLater(
          client.localStore.writeLocally(<Mutation>[
            setMutation('c/b', map(<Object?>['v', 2])),
          ]),
          throwsA(_transient),
        );

        final _Client reopened = await _Client.open(inner);
        final List<MutationBatch> pending = await reopened.pending();
        if (point == CrashPoint.beforeWrite) {
          expect(pending.map((MutationBatch b) => b.keys.single), <DocumentKey>[
            key('c/a'),
          ]);
          expect(await reopened.read('c/b'), isNull);
        } else {
          expect(pending.map((MutationBatch b) => b.keys.single), <DocumentKey>[
            key('c/a'),
            key('c/b'),
          ]);
          expect(await reopened.read('c/b'), <String, Object?>{'v': 2});
        }
        expect(
          await reopened.localStore.getPendingWriteCount(),
          pending.length,
        );

        // Sync resumes: the batches are acknowledged in order, a new write gets a new batch id.
        await reopened.localStore.writeLocally(<Mutation>[
          setMutation('c/c', map(<Object?>['v', 3])),
        ]);
        final List<MutationBatch> all = await reopened.pending();
        expect(all.last.batchId, greaterThan(pending.last.batchId));
        for (final MutationBatch batch in all) {
          await reopened.acknowledge(batch, 10 + batch.batchId);
        }
        expect(await reopened.localStore.getPendingWriteCount(), 0);
        expect(await reopened.read('c/c'), <String, Object?>{'v': 3});
      });

      test('${point.name} of an acknowledgement', () async {
        final MemoryLogStore inner = MemoryLogStore();
        final _Client client = await _Client.open(inner);
        await client.localStore.writeLocally(<Mutation>[
          setMutation('c/a', map(<Object?>['v', 1])),
        ]);
        await client.localStore.writeLocally(<Mutation>[
          setMutation('c/b', map(<Object?>['v', 2])),
        ]);
        final List<MutationBatch> before = await client.pending();
        client.store.crash = point;
        await expectLater(
          client.acknowledge(before[0], 5),
          throwsA(_transient),
        );

        final _Client reopened = await _Client.open(inner);
        final List<MutationBatch> pending = await reopened.pending();
        expect(
          pending.map((MutationBatch b) => b.batchId),
          point == CrashPoint.beforeWrite
              ? before.map((MutationBatch b) => b.batchId)
              : <int>[before[1].batchId],
        );
        expect(await reopened.read('c/a'), <String, Object?>{'v': 1});
        expect(await reopened.read('c/b'), <String, Object?>{'v': 2});
      });
    }
  });

  test(
    'crashes at random points agree with a model of the cache',
    () async {
      final int seed = DateTime.now().millisecondsSinceEpoch % 100000;
      for (final int s in <int>[1, 2, 3, seed]) {
        await _randomRun(s);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _OnlineStates extends MockRemoteStoreCallback {
  final List<OnlineState> states = <OnlineState>[];

  @override
  Future<void> handleRemoteEvent(RemoteEvent remoteEvent) async {}

  @override
  Future<void> handleOnlineStateChange(OnlineState onlineState) async {
    states.add(onlineState);
  }
}

/// A pending write of the model: the document and the value it sets (null: a delete).
typedef _PendingWrite = ({String path, int? value});

/// Runs operations at random on a cache whose store fails and crashes at random, and compares the cache with a model
/// after every operation and every restart.
Future<void> _randomRun(int seed) async {
  final Random random = Random(seed);
  final List<String> paths = <String>[for (int i = 0; i < 6; i++) 'c/d$i'];
  final MemoryLogStore inner = MemoryLogStore();

  // The model: the pending writes in order, and the documents of the backend (the acknowledged and remote values).
  final List<_PendingWrite> pending = <_PendingWrite>[];
  final Map<String, int?> remote = <String, int?>{};
  int nextVersion = 1;
  int crashes = 0;
  int failures = 0;

  _Client client = await _Client.open(inner);
  int targetId = (await client.localStore.allocateTarget(
    query('c').toTarget(),
  )).targetId;

  Future<void> check(String when) async {
    final String reason = 'seed $seed, $when';
    final List<MutationBatch> batches = await client.pending();
    for (int i = 1; i < batches.length; i++) {
      expect(
        batches[i].batchId,
        greaterThan(batches[i - 1].batchId),
        reason: reason,
      );
    }
    expect(
      <(String, int?)>[
        for (final MutationBatch b in batches)
          (
            b.keys.single.path.canonicalString,
            b.mutations.single is DeleteMutation
                ? null
                : (b.mutations.single as SetMutation).value.value['v']! as int,
          ),
      ],
      <(String, int?)>[
        for (final _PendingWrite w in pending) (w.path, w.value),
      ],
      reason: reason,
    );
    expect(
      await client.localStore.getPendingWriteCount(),
      pending.length,
      reason: reason,
    );
    for (final String path in paths) {
      int? expected = remote[path];
      for (final _PendingWrite w in pending) {
        if (w.path == path) {
          expected = w.value;
        }
      }
      final Map<String, Object?>? actual = await client.read(path);
      expect(
        actual,
        expected == null ? isNull : <String, Object?>{'v': expected},
        reason: '$reason, $path',
      );
    }
  }

  for (int step = 0; step < 300; step++) {
    // What goes wrong in this step, if anything.
    final int fault = random.nextInt(10);
    CrashPoint? crash;
    if (fault == 0) {
      crash = CrashPoint.beforeWrite;
    } else if (fault == 1) {
      crash = CrashPoint.afterWrite;
    } else if (fault == 2) {
      client.store.failNextWrite = true;
    } else if (fault == 3) {
      client.store.failNextRead = true;
    }
    client.store.crash = crash;

    // The operation, and what it does to the model when it takes effect.
    late Future<void> Function() operation;
    late void Function() apply;
    late String name;
    final int kind = random.nextInt(4);
    if (kind == 0 || pending.isEmpty && kind < 3) {
      final String path = paths[random.nextInt(paths.length)];
      final int? value = random.nextInt(4) == 0 ? null : random.nextInt(1000);
      name = 'write $path=$value';
      operation = () => client.localStore.writeLocally(<Mutation>[
        value == null
            ? deleteMutation(path)
            : setMutation(path, map(<Object?>['v', value])),
      ]);
      apply = () => pending.add((path: path, value: value));
    } else if (kind == 1) {
      final _PendingWrite first = pending.first;
      final int at = nextVersion++;
      name = 'acknowledge ${first.path}=${first.value}';
      operation = () async =>
          client.acknowledge((await client.pending()).first, at);
      apply = () {
        pending.removeAt(0);
        remote[first.path] = first.value;
      };
    } else if (kind == 2) {
      final _PendingWrite first = pending.first;
      name = 'reject ${first.path}=${first.value}';
      operation = () async =>
          client.localStore.rejectBatch((await client.pending()).first.batchId);
      apply = () => pending.removeAt(0);
    } else {
      final String path = paths[random.nextInt(paths.length)];
      final int value = random.nextInt(1000);
      final int at = nextVersion++;
      name = 'remote $path=$value';
      operation = () => client.localStore.applyRemoteEvent(
        addedRemoteEvent(doc(path, at, map(<Object?>['v', value])), <int>[
          targetId,
        ], <int>[]),
      );
      apply = () => remote[path] = value;
    }

    final int writesBefore = client.store.writes;
    bool failed = false;
    try {
      await operation();
    } on TransientDatabaseException {
      failed = true;
    }
    final bool stored = client.store.writes > writesBefore;
    expect(
      !failed || crash == CrashPoint.afterWrite || !stored,
      isTrue,
      reason: 'seed $seed, $name: failed after the store kept its write',
    );
    if (stored) {
      apply();
    }
    client.store
      ..failNextWrite = false
      ..failNextRead = false
      ..crash = null;

    if (failed) {
      failures++;
    }
    if (client.store.dead) {
      crashes++;
      client = await _Client.open(inner);
      targetId = (await client.localStore.allocateTarget(
        query('c').toTarget(),
      )).targetId;
      await check('after a crash at step $step ($name, ${crash?.name})');
    } else {
      await check('after step $step ($name${failed ? ', failed' : ''})');
    }
  }
  // The run did go through failures and crashes of both kinds.
  expect(crashes, greaterThan(10), reason: 'seed $seed');
  expect(failures, greaterThan(crashes), reason: 'seed $seed');
}
