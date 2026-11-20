// The merge of the queue at start (LocalStore.startMergingQueuedWrites / mergeQueuedWrites, with `mergeUnsentWrites`)
// interrupted at random points: three users each have a queue written with the setting off, then sessions with the
// setting on merge them, a few batches per transaction, while a fault injected into the storage kills the session
// at a random read or write (the storage then behaves as after a process kill: what was not committed is gone). Some
// sessions change the user in the middle of a merge. At the end every queue must be the one the merge at write time
// builds from the same writes (nothing lost, duplicated or reordered), every document the same, and a merged queue is
// not merged again.
//
// On SQLite (an ExclusiveDatabase, as on the web: the row of the killed client does not count as another client) and
// on the key-value cache (a MemoryLogStore that keeps its data across sessions). A last test pins what happens after a
// kill on a SQLite database that is not exclusive (the native one): the row of the killed client counts as another
// client for up to 30 minutes, and the merge waits until then.
//
// PROPERTY_SCALE multiplies the number of seeds, PROPERTY_SEED moves them.

@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel, Log;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../../util/merge_writes_gen.dart';
import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import 'mock/database_mock.dart';
import 'persistence_test_helpers.dart';

final class _InjectedFault implements Exception {
  @override
  String toString() => 'injected fault';
}

/// Kills the storage at the [failAt]-th call after it is armed: that call throws, and so does every later one, as
/// the storage of a process that was killed.
final class _Faults {
  int? failAt;
  int _calls = 0;
  bool dead = false;

  void arm(int? at) {
    failAt = at;
    _calls = 0;
  }

  void tick() {
    if (dead) {
      throw _InjectedFault();
    }
    if (failAt != null && ++_calls >= failAt!) {
      dead = true;
      throw _InjectedFault();
    }
  }
}

class _FaultyDatabase implements Database {
  _FaultyDatabase(this._inner, this._faults);

  final DatabaseMock _inner;
  final _Faults _faults;

  @override
  String get path => _inner.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) {
    _faults.tick();
    return _inner.execute(statement, arguments);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) {
    _faults.tick();
    return _inner.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) {
    _faults.tick();
    return _inner.delete(statement, arguments);
  }

  /// The connection goes away with what it did not commit, as when the process is killed.
  @override
  void close() => _inner.close();
}

class _FaultyExclusiveDatabase extends _FaultyDatabase
    implements ExclusiveDatabase {
  _FaultyExclusiveDatabase(super.inner, super.faults);
}

/// A key-value store that fails as [_Faults] says: the write of a transaction commits it, so a write that fails
/// leaves the store as it was.
class _FaultyStore implements CacheStore {
  _FaultyStore(this._inner, this._faults);

  final CacheStore _inner;
  final _Faults _faults;

  @override
  Future<void> open() => _inner.open();

  @override
  Future<void> close() async {}

  @override
  Future<Uint8List?> get(Uint8List key) {
    _faults.tick();
    return _inner.get(key);
  }

  @override
  Future<List<CacheStoreEntry>> scan(
    Uint8List start,
    Uint8List end, {
    bool reverse = false,
    int? limit,
  }) {
    _faults.tick();
    return _inner.scan(start, end, reverse: reverse, limit: limit);
  }

  @override
  Future<void> write(List<CacheStoreEntry> puts, List<Uint8List> deletes) {
    _faults.tick();
    return _inner.write(puts, deletes);
  }
}

/// One storage that outlives the sessions on it.
abstract class _Storage {
  /// A new session: a persistence on the storage, with the faults of the session.
  Future<Persistence> open(_Faults faults);

  /// Ends a session that was killed.
  Future<void> kill(Persistence persistence);

  Future<void> dispose();
}

final class _SqliteStorage implements _Storage {
  _SqliteStorage({this.exclusive = true});

  final bool exclusive;
  final String name = 'merge_crash_${const Uuid().v4()}';
  int now = 1700000000000;
  final List<DatabaseMock> _opened = <DatabaseMock>[];

  @override
  Future<Persistence> open(_Faults faults) async {
    final DatabaseId databaseId = DatabaseId.forProject('projectId');
    final SQLitePersistence persistence =
        await SQLitePersistence.createWithLease(
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
          }) async {
            final DatabaseMock db = await DatabaseMock.create(
              name,
              version: version,
              onConfigure: onConfigure,
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen,
            );
            db.renamePath = false;
            _opened.add(db);
            return exclusive
                ? _FaultyExclusiveDatabase(db, faults)
                : _FaultyDatabase(db, faults);
          },
          const LruGarbageCollectorParams(),
          clock: () => now,
        );
    await persistence.start();
    return persistence;
  }

  @override
  Future<void> kill(Persistence persistence) async {
    _opened.removeLast().close();
  }

  @override
  Future<void> dispose() async {
    for (final DatabaseMock db in _opened) {
      db.close();
    }
    DatabaseMock.deleteDatabaseFiles(name);
  }
}

final class _KeyValueStorage implements _Storage {
  final MemoryLogStore store = MemoryLogStore();

  @override
  Future<Persistence> open(_Faults faults) =>
      createKeyValuePersistence(store: _FaultyStore(store, faults));

  @override
  Future<void> kill(Persistence persistence) async {}

  @override
  Future<void> dispose() async {}
}

const List<User> _users = <User>[
  User.unauthenticated,
  User('alice'),
  User('bob'),
];

final List<DocumentKey> _keys = <DocumentKey>[
  key('coll/d0'),
  key('coll/d1'),
  key('coll/d2'),
];

// A pending server timestamp shows the time of its batch, which differs between two runs.
final RegExp _estimate = RegExp(
  r'\{__local_write_time__:.*?__type__:server_timestamp\}',
);
String _withoutTimes(Object? value) =>
    value.toString().replaceAll(_estimate, 'time');

/// The queue of each user (batch ids increase along it) and the documents each user sees.
Future<Map<User, List<String>>> _state(
  Persistence persistence,
  LocalStore localStore,
) async {
  final Map<User, List<String>> state = <User, List<String>>{};
  for (final User user in _users) {
    final List<MutationBatch> batches = await persistence
        .runTransactionAndReturn(
          'read the queue',
          () => persistence.getMutationQueue(user).getAllMutationBatches(),
        );
    for (int i = 1; i < batches.length; i++) {
      expect(batches[i].batchId, greaterThan(batches[i - 1].batchId));
    }
    await localStore.handleUserChange(user);
    state[user] = <String>[
      for (final MutationBatch batch in batches)
        _withoutTimes('${batch.mutations} with base ${batch.baseMutations}'),
      for (final DocumentKey documentKey in _keys)
        switch (await localStore.readDocument(documentKey)) {
          final Document document => _withoutTimes(document.data),
          final MaybeDocument? other => '${other.runtimeType}',
        },
    ];
  }
  return state;
}

/// The writes of each user: single writes, and now and then a batch of two (which is never merged).
Map<User, List<List<Mutation>>> _writes(Gen gen) =>
    <User, List<List<Mutation>>>{
      for (final User user in _users)
        user: <List<Mutation>>[
          for (int i = 5 + gen.below(10 + gen.size * 12); i > 0; i--)
            <Mutation>[
              for (int j = gen.chance(8) ? 2 : 1; j > 0; j--)
                if (offlineWrite(gen) case final OfflineWrite w)
                  w.toMutation(_keys[w.document]),
            ],
        ],
    };

void main() {
  // Every kill logs a failed rollback, and every session after one a client that takes over the cache.
  Log.level = InternalLogLevel.e;
  int kills = 0;
  int userChanges = 0;

  Future<void> check(_Storage storage, Gen gen) async {
    final Map<User, List<List<Mutation>>> writes = _writes(gen);

    // What the merge at write time builds.
    final Persistence expectedPersistence = await createLRUMemoryPersistence();
    final LocalStore expected = LocalStore(
      expectedPersistence,
      User.unauthenticated,
    )..mergeUnsentWrites = true;
    await expected.start();
    for (final User user in _users) {
      await expected.handleUserChange(user);
      expect(await expected.startMergingQueuedWrites(), isFalse);
      for (final List<Mutation> write in writes[user]!) {
        await expected.writeLocally(write, mayMerge: true);
      }
    }

    try {
      // The queues, written with the setting off.
      Persistence persistence = await storage.open(_Faults());
      LocalStore localStore = LocalStore(persistence, User.unauthenticated);
      await localStore.start();
      for (final User user in _users) {
        await localStore.handleUserChange(user);
        for (final List<Mutation> write in writes[user]!) {
          await localStore.writeLocally(write, mayMerge: true);
        }
      }
      await persistence.shutdown();

      // Sessions with the setting on, killed at random points, until one merges every queue to its end.
      for (int session = 0; ; session++) {
        final bool faulty = session < 8 && gen.chance(85);
        final _Faults faults = _Faults();
        persistence = await storage.open(faults);
        localStore = LocalStore(persistence, User.unauthenticated)
          ..mergeUnsentWrites = true;
        await localStore.start();
        faults.arm(faulty ? 1 + gen.below(400) : null);
        bool done = true;
        try {
          for (final User user in <User>[
            ..._users.skip(session % 3),
            ..._users.take(session % 3),
          ]) {
            await localStore.handleUserChange(user);
            await localStore.startMergingQueuedWrites();
            while (localStore.mergingQueuedWrites) {
              // Nothing is handed to the network while the merge runs.
              expect(await localStore.getNextMutationBatch(-1), isNull);
              await localStore.mergeQueuedWrites(maxBatches: 1 + gen.below(30));
              if (session < 8 && gen.chance(4)) {
                // The user changes before the merge of this queue is done: it goes on at a later session.
                userChanges++;
                done = false;
                break;
              }
            }
          }
        } on _InjectedFault {
          kills++;
          await storage.kill(persistence);
          continue;
        }
        faults.arm(null);
        if (!done) {
          await persistence.shutdown();
          continue;
        }
        // Every queue is merged: a merged queue is not merged again.
        for (final User user in _users) {
          await localStore.handleUserChange(user);
          expect(await localStore.startMergingQueuedWrites(), isFalse);
          expect(await localStore.getPendingWriteCount(), isNonNegative);
        }
        expect(
          await _state(persistence, localStore),
          await _state(expectedPersistence, expected),
        );
        // The count the app sees follows the merges.
        for (final User user in _users) {
          await localStore.handleUserChange(user);
          await expected.handleUserChange(user);
          expect(
            await localStore.getPendingWriteCount(),
            await expected.getPendingWriteCount(),
          );
        }
        await persistence.shutdown();
        return;
      }
    } finally {
      await expectedPersistence.shutdown();
      await storage.dispose();
    }
  }

  for (final (String cache, int count, _Storage Function() storage)
      in <(String, int, _Storage Function())>[
        ('SQLite', 40, _SqliteStorage.new),
        ('key-value', 60, _KeyValueStorage.new),
      ]) {
    test(
      'a merge of the queues at start that is killed at random points ends as the merge at write time, $cache',
      () async {
        kills = 0;
        userChanges = 0;
        await forAllAsync<int>(
          'merge of the queue killed at random points, $cache',
          count: cases(count),
          generate: (Gen gen) => gen.seed,
          check: (int seed) => check(storage(), Gen(seed)),
        );
        print('$cache: $kills kills, $userChanges user changes in a merge');
        expect(kills, greaterThan(count));
        expect(userChanges, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }

  test(
    'after a kill, a SQLite database that is not exclusive merges once the row of the killed client is 30 minutes old',
    () async {
      final _SqliteStorage storage = _SqliteStorage(exclusive: false);
      try {
        final Gen gen = Gen(1);
        final List<Mutation> writes = <Mutation>[
          for (int i = 0; i < 40; i++)
            if (offlineWrite(gen, documents: 1) case final OfflineWrite w)
              w.toMutation(_keys[0]),
        ];
        Persistence persistence = await storage.open(_Faults());
        LocalStore localStore = LocalStore(persistence, User.unauthenticated);
        await localStore.start();
        for (final Mutation write in writes) {
          await localStore.writeLocally(<Mutation>[write], mayMerge: true);
        }
        await persistence.shutdown();

        // A session with the setting is killed in the middle of the merge.
        final _Faults faults = _Faults();
        persistence = await storage.open(faults);
        localStore = LocalStore(persistence, User.unauthenticated)
          ..mergeUnsentWrites = true;
        await localStore.start();
        expect(await localStore.startMergingQueuedWrites(), isTrue);
        await localStore.mergeQueuedWrites(maxBatches: 5);
        faults.arm(1);
        await expectLater(
          localStore.mergeQueuedWrites(maxBatches: 5),
          throwsA(isA<_InjectedFault>()),
        );
        await storage.kill(persistence);

        // At once: the row of the killed client is fresh, it counts as another client, and nothing merges.
        persistence = await storage.open(_Faults());
        localStore = LocalStore(persistence, User.unauthenticated)
          ..mergeUnsentWrites = true;
        await localStore.start();
        expect(await persistence.hasOtherClients(), isTrue);
        expect(await localStore.startMergingQueuedWrites(), isFalse);
        final int pending = await localStore.getPendingWriteCount();
        await persistence.shutdown();

        // 30 minutes later the merge resumes where it was.
        storage.now += SQLiteClientMetadata.maxClientAgeMs + 1;
        persistence = await storage.open(_Faults());
        localStore = LocalStore(persistence, User.unauthenticated)
          ..mergeUnsentWrites = true;
        await localStore.start();
        expect(await persistence.hasOtherClients(), isFalse);
        expect(await localStore.startMergingQueuedWrites(), isTrue);
        while (localStore.mergingQueuedWrites) {
          await localStore.mergeQueuedWrites();
        }
        expect(await localStore.getPendingWriteCount(), lessThan(pending));
        await persistence.shutdown();
      } finally {
        await storage.dispose();
      }
    },
  );
}
