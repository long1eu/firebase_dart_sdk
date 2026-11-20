// An unexpected error on the queue of the client fails the client for good,
// as the JS `AsyncQueue` does (packages/firestore/src/util/async_queue_impl.ts,
// `enqueueInternal` and `verifyNotFailed`): later operations are rejected, and
// the client can still be terminated.

@TestOn('vm')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_hygiene.dart';
import '../clear_persistence_test.dart' show newApp, offlineSettings;

final Matcher _alreadyFailed = predicate<Object>(
  (Object e) =>
      '$e'.contains('AsyncQueue is already failed') &&
      '$e'.contains('broken invariant'),
  'says that the queue already failed, with the first error',
);

void main() {
  checkTestsLeaveNothingBehind();

  late Firestore firestore;
  late DocumentReference<Map<String, Object?>> doc;

  setUp(() async {
    final FirebaseApp app = newApp('failed-queue-${const Uuid().v4()}');
    addTearDown(app.delete);
    firestore = Firestore.instanceFor(app: app, settings: offlineSettings);
    doc = firestore.doc('col/doc');
    // Starts the client.
    await doc
        .get(GetOptions(source: Source.cache))
        .then((_) {}, onError: (Object _) {});
    expect(firestore.client.queue.isFailed, isFalse);
  });

  Future<void> expectFailedForGood() async {
    expect(firestore.client.queue.isFailed, isTrue);
    await expectLater(
      doc.get(GetOptions(source: Source.cache)),
      throwsA(_alreadyFailed),
    );
    await expectLater(
      doc.set(<String, Object?>{'a': 1}),
      throwsA(_alreadyFailed),
    );
    await expectLater(
      firestore.collection('col').get(GetOptions(source: Source.cache)),
      throwsA(_alreadyFailed),
    );
    await expectLater(doc.snapshots().first, throwsA(_alreadyFailed));

    // The client can still be shut down, and its cache cleared.
    await firestore.terminate();
    await firestore.clearPersistence();
  }

  test(
    'a failed internal assertion of an operation fails the client',
    () async {
      // An assertion of the local store, as `hardAssert` throws it.
      firestore.client.persistence.beforeTransaction = (String action) {
        throw AssertionError('broken invariant');
      };
      await expectLater(
        firestore.client.deleteAllFieldIndexes(),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message,
            'message',
            'broken invariant',
          ),
        ),
      );
      firestore.client.persistence.beforeTransaction = null;

      await expectFailedForGood();
    },
  );

  test(
    'an unexpected error of a retryable operation fails the client',
    () async {
      await expectLater(
        firestore.client.remoteStore.enqueueRetryable(
          () async => throw StateError('broken invariant'),
        ),
        throwsStateError,
      );

      await expectFailedForGood();
    },
  );

  test('terminate works while operations wait on a failed queue', () async {
    final Future<void> failing = firestore.client.remoteStore.enqueueRetryable(
      () async => throw StateError('broken invariant'),
    );
    // Requested before the failure: rejected with the error that failed the queue.
    final Future<Object?> waiting = doc.get(GetOptions(source: Source.cache));
    final Future<void> terminated = firestore.terminate();

    await expectLater(failing, throwsStateError);
    await expectLater(waiting, throwsStateError);
    await terminated;
  });
}
