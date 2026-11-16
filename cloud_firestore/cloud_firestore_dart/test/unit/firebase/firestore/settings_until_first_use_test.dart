// The settings setter and useFirestoreEmulator work until the first use of an
// instance (as in FlutterFire): the client starts lazily, at the first
// operation, with the settings of that moment. An instance created with
// settings starts at once, as before.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings;

final Matcher throwsStarted = throwsA(
  firestoreErrorWithCode(
    FirestoreErrorCode.failedPrecondition,
  ).having((FirestoreException e) => e.message, 'message', contains('started')),
);

void main() {
  int counter = 0;
  FirebaseApp app() {
    final FirebaseApp created = newApp('settingsUntilFirstUse${counter++}');
    addTearDown(created.delete);
    return created;
  }

  FirebaseFirestore lazyInstance() {
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app(),
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  test('the settings setter works before the first use', () async {
    final FirebaseFirestore firestore = lazyInstance();
    expect(firestore.isStarted, isFalse);

    final Settings settings = offlineSettings.copyWith(
      persistenceEnabled: false,
    );
    firestore.settings = settings;
    expect(firestore.settings, settings);
    expect(firestore.isStarted, isFalse);

    await firestore
        .doc('rooms/a')
        .get(GetOptions(source: Source.cache))
        .then((_) {}, onError: (Object _) {});
    expect(firestore.isStarted, isTrue);
    expect(firestore.client.databaseInfo.host, '127.0.0.1');
    expect(firestore.client.databaseInfo.port, 1);
  });

  test('the settings setter throws after the first use', () async {
    final FirebaseFirestore firestore = lazyInstance();
    firestore.settings = offlineSettings;
    firestore.collection('rooms').doc();
    expect(firestore.isStarted, isFalse, reason: 'a reference is not a use');

    unawaited(
      firestore
          .doc('rooms/a')
          .set(<String, Object?>{'n': 1})
          .catchError((Object _) {}),
    );
    expect(firestore.isStarted, isTrue);
    expect(() => firestore.settings = Settings(), throwsStarted);
    expect(firestore.settings, offlineSettings);
  });

  test('useFirestoreEmulator works before the first use', () async {
    final FirebaseFirestore firestore = lazyInstance();
    firestore.useFirestoreEmulator('127.0.0.1', 1);
    expect(firestore.settings.host, '127.0.0.1');
    expect(firestore.settings.port, 1);
    expect(firestore.settings.sslEnabled, isFalse);

    await firestore.waitForPendingWrites();
    expect(firestore.client.databaseInfo.host, '127.0.0.1');
    expect(firestore.client.databaseInfo.port, 1);
    expect(firestore.client.databaseInfo.sslEnabled, isFalse);
  });

  test('useFirestoreEmulator keeps the other settings', () {
    final FirebaseFirestore firestore = lazyInstance();
    firestore.settings = Settings(persistenceEnabled: false);
    firestore.useFirestoreEmulator('127.0.0.1', 1, sslEnabled: true);
    expect(firestore.settings.persistenceEnabled, isFalse);
    expect(firestore.settings.sslEnabled, isTrue);
  });

  test('useFirestoreEmulator throws after the first use', () async {
    final FirebaseFirestore firestore = lazyInstance();
    firestore.useFirestoreEmulator('127.0.0.1', 1);
    await firestore.waitForPendingWrites();
    expect(() => firestore.useFirestoreEmulator('127.0.0.1', 2), throwsStarted);
    expect(firestore.settings.port, 1);
  });

  test('useFirestoreEmulator refuses the production host', () {
    final FirebaseFirestore firestore = lazyInstance();
    expect(
      () => firestore.useFirestoreEmulator('firestore.googleapis.com', 443),
      throwsArgumentError,
    );
    expect(firestore.isStarted, isFalse);
  });

  test('an instance created with settings starts at once, as before', () {
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app(),
      settings: offlineSettings,
    );
    addTearDown(firestore.terminate);
    expect(firestore.isStarted, isTrue);
    expect(firestore.settings, offlineSettings);
    expect(() => firestore.settings = Settings(), throwsStarted);
    expect(() => firestore.useFirestoreEmulator('127.0.0.1', 2), throwsStarted);
    expect(
      identical(FirebaseFirestore.instanceFor(app: firestore.app), firestore),
      isTrue,
    );
  });

  test(
    'the first listener and the first write of a lazy instance are kept',
    () async {
      final FirebaseFirestore firestore = lazyInstance();
      firestore.settings = offlineSettings.copyWith(persistenceEnabled: false);
      final DocumentReference<Map<String, Object?>> doc = firestore.doc(
        'rooms/first',
      );

      // The listener starts the client; the write is queued after it.
      final Future<DocumentSnapshot<Map<String, Object?>>> written = doc
          .snapshots(includeMetadataChanges: true)
          .firstWhere((DocumentSnapshot<Map<String, Object?>> s) => s.exists);
      unawaited(doc.set(<String, Object?>{'n': 1}).catchError((Object _) {}));

      final DocumentSnapshot<Map<String, Object?>> snapshot = await written
          .timeout(const Duration(seconds: 10));
      expect(snapshot.data(), <String, Object?>{'n': 1});
      expect(snapshot.metadata.hasPendingWrites, isTrue);
    },
  );

  test('a write before any listener on a lazy instance is kept', () async {
    final FirebaseFirestore firestore = lazyInstance();
    firestore.useFirestoreEmulator('127.0.0.1', 1);
    final DocumentReference<Map<String, Object?>> doc = firestore.doc(
      'rooms/write-first',
    );
    unawaited(doc.set(<String, Object?>{'n': 2}).catchError((Object _) {}));
    final DocumentSnapshot<Map<String, Object?>> snapshot = await doc.get(
      GetOptions(source: Source.cache),
    );
    expect(snapshot.data(), <String, Object?>{'n': 2});
  });

  test(
    'runTransaction fails with deadline-exceeded after its timeout',
    () async {
      final FirebaseFirestore firestore = lazyInstance();
      firestore.useFirestoreEmulator('127.0.0.1', 1);
      int attempts = 0;
      await expectLater(
        firestore.runTransaction<void>((Transaction transaction) async {
          attempts++;
          await transaction.get(firestore.doc('rooms/t'));
        }, timeout: const Duration(milliseconds: 300)),
        throwsA(firestoreErrorWithCode(FirestoreErrorCode.deadlineExceeded)),
      );
      final int atTimeout = attempts;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(attempts, atTimeout, reason: 'no new attempt after the timeout');
    },
  );

  test('runTransaction refuses a timeout that is not positive', () {
    final FirebaseFirestore firestore = lazyInstance();
    expect(
      () => firestore.runTransaction<void>(
        (Transaction _) async {},
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(firestore.isStarted, isFalse);
  });
}
