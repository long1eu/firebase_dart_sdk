// What happens to operations that are pending when an instance is terminated.
// As upstream: Android leaves the Task of a pending write incomplete, and the
// JS SDK returns "a Promise which never resolves" for work queued at or after
// terminate (AsyncQueueImpl.enqueue).

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

void main() {
  checkTestsLeaveNothingBehind();

  // Nothing listens on port 1: writes are applied locally and stay pending.
  final FirestoreSettings offline = FirestoreSettings()
      .withEmulator('127.0.0.1', 1)
      .copyWith(cacheSettings: const MemoryCacheSettings());

  FirebaseApp newApp(String name) => FirebaseApp.withOptions(
        const FirebaseOptions(
            apiKey: 'key', applicationId: 'appId', projectId: 'projectId'),
        dependencies: null,
        name: name,
      );

  test('a write that is pending at terminate never completes', () async {
    final FirebaseApp app = newApp('terminatePendingWrite');
    addTearDown(app.delete);
    final Firestore firestore =
        Firestore.instanceFor(app: app, settings: offline);
    final DocumentReference<Map<String, Object?>> doc = firestore.doc('a/b');

    String outcome = 'pending';
    unawaited(doc.set(<String, Object?>{'a': 1}).then<void>(
        (_) => outcome = 'completed',
        onError: (Object error) => outcome = 'failed: $error'));
    // The write is in the local cache.
    expect((await doc.get(Source.cache)).data, <String, Object?>{'a': 1});

    await firestore.terminate();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(outcome, 'pending');
  });

  test('operations started after terminate fail', () async {
    final FirebaseApp app = newApp('terminateThenUse');
    addTearDown(app.delete);
    final Firestore firestore =
        Firestore.instanceFor(app: app, settings: offline);
    await firestore.terminate();

    expect(() => firestore.doc('a/b').set(<String, Object?>{'a': 1}),
        throwsA(anything));
    // Terminating again is fine.
    await firestore.terminate();
  });
}
