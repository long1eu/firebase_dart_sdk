// RemoteStore when the persistence fails (the JS SDK's recovery, see RemoteStore._disableNetworkUntilRecovery): a
// recoverable error takes the network offline until a probe of the persistence succeeds, any other error is thrown.

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
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
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
}
