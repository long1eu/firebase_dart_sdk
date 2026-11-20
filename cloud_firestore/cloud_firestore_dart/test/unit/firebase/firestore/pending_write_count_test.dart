// getPendingWriteCount and pendingWriteCounts, on an instance whose backend never answers: every write stays in
// the queue. With the memory and the SQLite cache: the count per user and after a change of user, the throttle of
// the stream, and a second client on the same SQLite cache.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings, openFixed;
import 'local/mock/database_mock.dart';

void main() {
  int counter = 0;

  FirebaseFirestore memory({AuthTokenProvider? auth}) {
    final FirebaseApp app = newApp('pendingWriteCount${counter++}');
    addTearDown(app.delete);
    if (auth != null) {
      app.authProvider = auth;
    }
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  FirebaseFirestore sqlite(String dbName, {AuthTokenProvider? auth}) {
    final FirebaseApp app = newApp('pendingWriteCount${counter++}');
    addTearDown(app.delete);
    if (auth != null) {
      app.authProvider = auth;
    }
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase: openFixed(dbName),
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  String newDatabase() {
    final String dbName = 'pending-write-count-${const Uuid().v4()}.db';
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
    return dbName;
  }

  for (final String cache in <String>['memory', 'sqlite']) {
    group('with the $cache cache', () {
      late _Auth auth;
      late FirebaseFirestore firestore;

      setUp(() {
        auth = _Auth();
        addTearDown(auth.close);
        firestore = cache == 'memory'
            ? memory(auth: auth)
            : sqlite(newDatabase(), auth: auth);
      });

      test('counts the queue of the current user only', () async {
        auth.signIn('alice');
        await pumpEventQueue();
        firestore.doc('rooms/a1').set(<String, Object?>{'n': 1}).ignore();
        firestore.doc('rooms/a2').set(<String, Object?>{'n': 2}).ignore();
        expect(await firestore.getPendingWriteCount(), 2);

        auth.signIn('bob');
        await pumpEventQueue();
        expect(await firestore.getPendingWriteCount(), 0);
        firestore.doc('rooms/b1').set(<String, Object?>{'n': 1}).ignore();
        expect(await firestore.getPendingWriteCount(), 1);

        auth.signOut();
        await pumpEventQueue();
        expect(await firestore.getPendingWriteCount(), 0);
        firestore.doc('rooms/u1').set(<String, Object?>{'n': 1}).ignore();
        firestore.doc('rooms/u2').set(<String, Object?>{'n': 1}).ignore();
        firestore.doc('rooms/u3').set(<String, Object?>{'n': 1}).ignore();
        expect(await firestore.getPendingWriteCount(), 3);

        auth.signIn('alice');
        await pumpEventQueue();
        expect(await firestore.getPendingWriteCount(), 2);
        auth.signIn('bob');
        await pumpEventQueue();
        expect(await firestore.getPendingWriteCount(), 1);
      });

      test('the stream emits the count of the new user after a user change',
          () async {
        auth.signIn('alice');
        await pumpEventQueue();
        firestore.doc('rooms/a1').set(<String, Object?>{'n': 1}).ignore();
        firestore.doc('rooms/a2').set(<String, Object?>{'n': 2}).ignore();
        final List<int> counts = <int>[];
        final StreamSubscription<int> subscription = firestore
            .pendingWriteCounts()
            .listen(counts.add);
        addTearDown(subscription.cancel);
        await firestore.getPendingWriteCount();
        await pumpEventQueue();
        expect(counts, <int>[2]);

        auth.signIn('bob');
        await _afterThrottle(firestore);
        expect(counts, <int>[2, 0]);

        firestore.doc('rooms/b1').set(<String, Object?>{'n': 1}).ignore();
        firestore.doc('rooms/b2').set(<String, Object?>{'n': 1}).ignore();
        await _afterThrottle(firestore);
        expect(counts, <int>[2, 0, 2]);

        // Alice has as many writes as Bob: the change of user reads the count again, but the same count is not
        // emitted twice.
        auth.signIn('alice');
        await _afterThrottle(firestore);
        expect(await firestore.getPendingWriteCount(), 2);
        expect(counts, <int>[2, 0, 2]);

        auth.signOut();
        await _afterThrottle(firestore);
        expect(counts, <int>[2, 0, 2, 0]);
      });

      test('the stream reads the changes within 250 ms together', () async {
        final List<int> counts = <int>[];
        final List<Duration> times = <Duration>[];
        final Stopwatch stopwatch = Stopwatch();
        final StreamSubscription<int> subscription =
            firestore.pendingWriteCounts().listen((int count) {
          counts.add(count);
          times.add(stopwatch.elapsed);
        });
        addTearDown(subscription.cancel);
        await firestore.getPendingWriteCount();
        await pumpEventQueue();
        expect(counts, <int>[0]);

        stopwatch.start();
        for (int i = 0; i < 50; i++) {
          firestore.doc('rooms/$i').set(<String, Object?>{'n': i}).ignore();
        }
        await _afterThrottle(firestore);
        // One read for all the writes: they were queued before the timer of the first change fired, so the read
        // runs after all of them.
        expect(counts, <int>[0, 50]);
        expect(
          times.last,
          greaterThanOrEqualTo(FirestoreClient.pendingWriteCountInterval),
        );

        // The next change after an emission waits for its own interval.
        final Duration before = stopwatch.elapsed;
        firestore.doc('rooms/last').set(<String, Object?>{'n': 0}).ignore();
        await _afterThrottle(firestore);
        expect(counts, <int>[0, 50, 51]);
        expect(
          times.last - before,
          greaterThanOrEqualTo(FirestoreClient.pendingWriteCountInterval),
        );
      });

      test('counts one per write and one per write batch', () async {
        expect(await firestore.getPendingWriteCount(), 0);

        firestore.doc('rooms/a').set(<String, Object?>{'n': 1}).ignore();
        firestore.doc('rooms/a').update(<String, Object?>{'n': 2}).ignore();
        firestore.doc('rooms/b').delete().ignore();
        expect(await firestore.getPendingWriteCount(), 3);

        final WriteBatch batch = firestore.batch();
        for (int i = 0; i < 5; i++) {
          batch.set(firestore.doc('rooms/batch$i'), <String, Object?>{'n': i});
        }
        batch.commit().ignore();
        expect(await firestore.getPendingWriteCount(), 4);
      });

      test('the stream emits the count at once and after the writes', () async {
        firestore.doc('rooms/a').set(<String, Object?>{'n': 1}).ignore();
        final List<int> counts = <int>[];
        final StreamSubscription<int> subscription = firestore
            .pendingWriteCounts()
            .listen(counts.add);
        addTearDown(subscription.cancel);
        await firestore.getPendingWriteCount();
        await pumpEventQueue();
        expect(counts, <int>[1]);

        for (int i = 0; i < 20; i++) {
          firestore.doc('rooms/$i').set(<String, Object?>{'n': i}).ignore();
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        // Throttled: not one event per write, and the last one is the final count.
        expect(counts.length, lessThanOrEqualTo(4));
        expect(counts.last, 21);
      });

      test('the stream closes when the instance is terminated', () async {
        final Completer<void> done = Completer<void>();
        final List<int> counts = <int>[];
        firestore.pendingWriteCounts().listen(
          counts.add,
          onDone: done.complete,
        );
        await firestore.getPendingWriteCount();
        await firestore.terminate();
        await done.future.timeout(const Duration(seconds: 5));
        expect(counts, <int>[0]);

        await expectLater(
          firestore.getPendingWriteCount(),
          throwsA(
            firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition),
          ),
        );
        await expectLater(
          firestore.pendingWriteCounts(),
          emitsInOrder(<Object>[
            emitsError(
              firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition),
            ),
            emitsDone,
          ]),
        );
      });
    });
  }

  test('a second client on the same SQLite cache: its writes are counted at '
      'the next read', () async {
    final String dbName = newDatabase();
    // One after the other, as two clients that open the cache file do not migrate it at the same time.
    final FirebaseFirestore first = sqlite(dbName);
    await first.getPendingWriteCount();
    final FirebaseFirestore second = sqlite(dbName);
    await second.getPendingWriteCount();

    final List<int> counts = <int>[];
    final StreamSubscription<int> subscription =
        first.pendingWriteCounts().listen(counts.add);
    addTearDown(subscription.cancel);
    await first.getPendingWriteCount();
    await pumpEventQueue();
    expect(counts, <int>[0]);

    for (int i = 0; i < 3; i++) {
      second.doc('rooms/second$i').set(<String, Object?>{'n': i}).ignore();
    }
    expect(await second.getPendingWriteCount(), 3);
    // The first client reads the count from the cache: it includes the batches of the second one.
    expect(await first.getPendingWriteCount(), 3);

    // The stream of the first client is not told about the writes of the second one: it shows them at its next
    // emission, after a change of its own.
    first.doc('rooms/first').set(<String, Object?>{'n': 0}).ignore();
    await _afterThrottle(first);
    expect(counts.last, 4);
    expect(counts, isNot(contains(3)));
    expect(await second.getPendingWriteCount(), 4);
  });

  test('the SQLite cache still has the count after a restart', () async {
    final String dbName = newDatabase();
    final FirebaseFirestore first = sqlite(dbName);
    for (int i = 0; i < 7; i++) {
      first.doc('rooms/$i').set(<String, Object?>{'n': i}).ignore();
    }
    expect(await first.getPendingWriteCount(), 7);
    await first.terminate();

    final FirebaseFirestore second = sqlite(dbName);
    expect(await second.getPendingWriteCount(), 7);
    second.doc('rooms/more').set(<String, Object?>{'n': 0}).ignore();
    expect(await second.getPendingWriteCount(), 8);
  });
}

/// Waits until a change of the pending writes of [firestore] has been read by its streams: longer than
/// [FirestoreClient.pendingWriteCountInterval], then for the read on the queue of the client.
Future<void> _afterThrottle(FirebaseFirestore firestore) async {
  await firestore.getPendingWriteCount();
  await Future<void>.delayed(
    FirestoreClient.pendingWriteCountInterval + const Duration(milliseconds: 150),
  );
  await firestore.getPendingWriteCount();
  await pumpEventQueue();
}

/// A token provider whose user the test changes.
class _Auth extends AuthTokenProvider {
  final StreamController<AuthTokenChange> _changes =
      StreamController<AuthTokenChange>.broadcast();

  @override
  String? uid;

  void signIn(String user) {
    uid = user;
    _changes.add(AuthTokenChange('token-$user'));
  }

  void signOut() {
    uid = null;
    _changes.add(const AuthTokenChange(''));
  }

  Future<void> close() => _changes.close();

  @override
  Future<GetTokenResult> getAccessToken({required bool forceRefresh}) async =>
      GetTokenResult('token-$uid');

  @override
  Stream<AuthTokenChange> get onTokenChanged => _changes.stream;
}
