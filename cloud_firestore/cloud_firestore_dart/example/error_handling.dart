// Errors: catching a FirestoreError, telling the codes apart, and trying again
// with a backoff when the code says that a later attempt can succeed.
//
// See docs/guides/error_handling.md in the repository for every code.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/error_handling.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

import 'common.dart';

/// Whether a later attempt of the same call can succeed: the connection or
/// the backend failed, or the backend was busy. The other codes come from the
/// request itself (the rules, the data, a missing document or index), and
/// sending it again gives the same answer.
bool isRetryable(FirestoreException error) {
  switch (error.errorCode) {
    case FirestoreErrorCode.unavailable:
    case FirestoreErrorCode.deadlineExceeded:
    case FirestoreErrorCode.resourceExhausted:
    case FirestoreErrorCode.internal:
    case FirestoreErrorCode.aborted:
      return true;
    default:
      return false;
  }
}

/// Runs [operation] and runs it again, up to [maxAttempts] times in all,
/// while it fails with a [FirestoreException] that [isRetryable] accepts. Waits
/// [initialDelay] before the second attempt and 1.5 times longer before each
/// one after it, give or take half of that at random, as the SDK does for its
/// own retries. Every other error is passed on at once.
///
/// Use it for calls that are answered by the backend (a server read, an
/// aggregation, a transaction that ran out of attempts). Do not wrap a write
/// in it: a write future does not fail when the client is offline, it waits,
/// and the client sends the write again by itself.
///
/// A call that failed with `deadlineExceeded` may have been applied: only
/// retry what gives the same result when it runs twice.
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(seconds: 1),
  void Function(FirestoreException error, Duration delay)? onRetry,
}) async {
  final Random random = Random();
  Duration delay = initialDelay;
  for (int attempt = 1; ; attempt++) {
    try {
      return await operation();
    } on FirestoreException catch (error) {
      if (attempt >= maxAttempts || !isRetryable(error)) {
        rethrow;
      }
      final Duration jittered = delay * (0.5 + random.nextDouble());
      onRetry?.call(error, jittered);
      await Future<void>.delayed(jittered);
      delay *= 1.5;
    }
  }
}

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    scratch('cities'),
  );
  await cities.doc('SF').set(<String, Object?>{'name': 'San Francisco'});

  // 1. A write that the backend rejects fails its future with the code of the
  //    backend. `update` needs an existing document: `notFound`.
  try {
    await cities.doc('nowhere').update(<String, Object?>{'visited': true});
  } on FirestoreException catch (e) {
    print(
      'update of a missing document: ${e.errorCode}, retryable: ${isRetryable(e)}',
    );
  }

  // 2. Invalid arguments are programming errors, reported with an
  //    ArgumentError (here through the future of `set`), not a FirestoreError.
  try {
    await cities.doc('SF').set(<String, Object?>{'__secret__': 1});
  } on ArgumentError catch (e) {
    print('invalid data: ArgumentError: ${e.message}');
  }

  // 3. A call that needs the backend fails with `unavailable` while the
  //    client is offline. Here the network comes back after the first
  //    failure, and withRetry gets the answer at the second attempt.
  await firestore.disableNetwork();
  final AggregateQuerySnapshot count = await withRetry(
    () => cities.count().get(),
    initialDelay: const Duration(milliseconds: 200),
    onRetry: (FirestoreException error, Duration delay) {
      print('count failed with ${error.errorCode}, trying again');
      unawaited(firestore.enableNetwork());
    },
  );
  print('count after a retry: ${count.getCount()}');

  // 4. A write made offline does not fail: it is in the cache at once and
  //    its future completes when the backend acknowledges it. Do not wait for
  //    it before you go on; catch its error so that a rejection is not an
  //    uncaught error.
  await firestore.disableNetwork();
  final Future<void> write = cities
      .doc('LA')
      .set(<String, Object?>{'name': 'Los Angeles'})
      .catchError((Object e) => print('the backend rejected the write: $e'));
  final DocumentSnapshot<Map<String, Object?>> cached = await cities
      .doc('LA')
      .get(Source.cache);
  print('offline: ${cached.data} pending: ${cached.metadata.hasPendingWrites}');
  // A document that is not in the cache cannot be read while offline.
  try {
    await cities.doc('unknown').get();
  } on FirestoreException catch (e) {
    print('get of an uncached document offline: ${e.errorCode}');
  }
  await firestore.enableNetwork();
  await write;
  print('write acknowledged once online');

  // 5. A listener reports an error (permission denied, a missing index) on
  //    its stream, which then closes. Always pass onError.
  final Completer<void> first = Completer<void>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      cities.snapshots.listen(
        (QuerySnapshot<Map<String, Object?>> snapshot) {
          if (!first.isCompleted) {
            first.complete();
          }
        },
        onError: (Object error) {
          if (error is FirestoreException &&
              error.errorCode == FirestoreErrorCode.permissionDenied) {
            print('not allowed to listen; listen again after a sign-in');
          } else {
            print('listener failed: $error');
          }
        },
      );
  await first.future;
  await subscription.cancel();
  print('listener received its first snapshot');

  // 6. A transaction is run again by the client when the documents it read
  //    changed before its commit, up to `maxAttempts` times. Here another
  //    client changes the document at every attempt, so it gives up.
  final FirebaseFirestore other = connect('other');
  int attempts = 0;
  try {
    await firestore.runTransaction((Transaction transaction) async {
      attempts++;
      await transaction.get(cities.doc('SF'));
      await other.doc(cities.doc('SF').path).update(<String, Object?>{
        'changedBy': 'other client, attempt $attempts',
      });
      transaction.update(cities.doc('SF'), <String, Object?>{
        'visits': FieldValue.increment(1),
      });
    }, options: TransactionOptions(maxAttempts: 2));
  } on FirestoreException catch (e) {
    // The code is the one of the last failed commit: the emulator answers
    // with failedPrecondition, the backend can also answer with aborted.
    print('transaction gave up after $attempts attempts: ${e.errorCode}');
  }
  await other.terminate();

  // 7. A bundle that cannot be read fails the task with invalidArgument; the
  //    cause says why.
  try {
    await firestore.loadBundle(utf8.encode('not a bundle')).future;
  } on FirestoreException catch (e) {
    print('bad bundle: ${e.errorCode}, cause: ${e.cause.runtimeType}');
  }

  // 8. Misuse of the API: different settings for an instance that exists
  //    already is a StateError; any call on a terminated instance fails with
  //    failedPrecondition.
  try {
    FirebaseFirestore.instanceFor(
      app: FirebaseApp.instance,
      settings: Settings(),
    );
  } on StateError {
    print('instanceFor with other settings: StateError');
  }
  await firestore.terminate();
  try {
    await cities.doc('SF').get();
  } on FirestoreException catch (e) {
    print('after terminate: ${e.errorCode}');
  }
}
