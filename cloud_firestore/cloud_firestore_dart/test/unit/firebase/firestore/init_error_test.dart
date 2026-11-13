// A cache that can't be opened: `Firestore.instanceFor` returns at once and opens the cache in the background, so
// every operation, including the ones queued while the open was running, fails with the error of the open (before,
// the first queued one failed with `LateInitializationError: Field 'localStore'`). The pattern of
// `openWithMemoryFallback` (example/sqlite_database_web.dart) then works: wait for a first operation, terminate,
// create an instance with a memory cache.

@TestOn('vm')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/test_hygiene.dart';
import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings;

/// An opener that fails, after [delay], like the web opener when another tab holds the cache.
OpenDatabase failingOpener(Completer<void> opening, Duration delay) {
  return (
    String path, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    if (!opening.isCompleted) {
      opening.complete();
    }
    await Future<void>.delayed(delay);
    throw FirestoreError(
      'The cache is open in another tab.',
      FirestoreErrorCode.failedPrecondition,
    );
  };
}

void main() {
  checkTestsLeaveNothingBehind();

  test('operations queued while the cache fails to open fail with the error '
      'of the open', () async {
    final FirebaseApp app = newApp('init-error-${const Uuid().v4()}');
    addTearDown(app.delete);
    final Completer<void> opening = Completer<void>();
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase: failingOpener(opening, const Duration(milliseconds: 100)),
    );
    addTearDown(firestore.terminate);
    await opening.future;

    // Queued behind the initialization, which is still opening the cache.
    final List<Future<Object?>> operations = <Future<Object?>>[
      firestore.getNamedQuery('none'),
      firestore.doc('col/doc').get(Source.cache),
      firestore.collection('col').get(Source.cache),
      firestore.getNamedQuery('none'),
    ];
    for (final Future<Object?> operation in operations) {
      await expectLater(
        operation,
        throwsA(firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition)),
      );
    }
    // And the operations requested afterwards.
    await expectLater(
      firestore.getNamedQuery('none'),
      throwsA(firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition)),
    );
  });

  test('the fallback to a memory cache: wait for a first operation, '
      'terminate, create again', () async {
    final FirebaseApp app = newApp('fallback-${const Uuid().v4()}');
    addTearDown(app.delete);
    final Firestore persistent = Firestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase: failingOpener(Completer<void>(), Duration.zero),
    );
    Firestore firestore;
    try {
      await persistent.getNamedQuery('openWithMemoryFallback');
      fail('the cache opened');
    } on FirestoreError catch (e) {
      expect(e.code, FirestoreErrorCode.failedPrecondition);
      await persistent.terminate();
      firestore = Firestore.instanceFor(
        app: app,
        settings: offlineSettings.copyWith(
          cacheSettings: const MemoryCacheSettings(),
        ),
      );
    }
    addTearDown(firestore.terminate);
    expect(firestore, isNot(same(persistent)));
    expect(await firestore.getNamedQuery('none'), isNull);
  });
}
