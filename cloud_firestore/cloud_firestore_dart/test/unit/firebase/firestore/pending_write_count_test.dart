// getPendingWriteCount and pendingWriteCounts, on an instance whose backend never answers: every write stays in
// the queue.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings, openFixed;
import 'local/mock/database_mock.dart';

void main() {
  int counter = 0;

  FirebaseFirestore memory() {
    final FirebaseApp app = newApp('pendingWriteCount${counter++}');
    addTearDown(app.delete);
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: offlineSettings.copyWith(
        cacheSettings: const MemoryCacheSettings(),
      ),
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  FirebaseFirestore sqlite(String dbName) {
    final FirebaseApp app = newApp('pendingWriteCount${counter++}');
    addTearDown(app.delete);
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
      late FirebaseFirestore firestore;

      setUp(() {
        firestore = cache == 'memory' ? memory() : sqlite(newDatabase());
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
