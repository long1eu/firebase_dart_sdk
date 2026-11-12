import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local_cache_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';

/// Port of the clearPersistence tests of the Android FirestoreTest.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/clear_persistence';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<Firestore> restartable(String dbName) {
    return IntegrationTestUtil.testFirestoreInstance(
        IntegrationTestUtil.provider.projectId,
        InternalLogLevel.w,
        IntegrationTestUtil.newTestSettings(),
        'integration/clear_persistence',
        fixedDbName: dbName);
  }

  Matcher firestoreErrorWithCode(FirestoreErrorCode code) =>
      isA<FirestoreError>().having((FirestoreError e) => e.code, 'code', code);

  test('testCanClearPersistenceAfterRestarting', () async {
    const String dbName = 'integration/clear_persistence_restart.db';
    DatabaseMock.deleteDatabaseFiles(dbName);

    final Firestore firestore = await restartable(dbName);
    final DocumentReference<Map<String, Object?>> docRef =
        firestore.collection('col1').document('doc1');
    await docRef.set(<String, Object?>{'foo': 'bar'});
    // The write is in the local cache before the instance goes away.
    expect(
        (await docRef.get(Source.cache)).data, <String, Object?>{'foo': 'bar'});
    await firestore.terminate();
    await firestore.clearPersistence();
    expect(DatabaseMock.pathForName(dbName).existsSync(), isFalse);

    // Same database file: the cleared cache must not have the document.
    final Firestore firestore2 = await restartable(dbName);
    await expectLater(firestore2.document(docRef.path).get(Source.cache),
        throwsA(firestoreErrorWithCode(FirestoreErrorCode.unavailable)));

    // The document is still on the backend, only the cache was cleared.
    final DocumentSnapshot<Map<String, Object?>> fromServer =
        await firestore2.document(docRef.path).get(Source.server);
    expect(fromServer.data, <String, Object?>{'foo': 'bar'});
  });

  test('without clearPersistence a restarted instance keeps its cache',
      () async {
    // Control for the test above: the cache miss comes from clearPersistence, not from the restart.
    const String dbName = 'integration/clear_persistence_control.db';
    DatabaseMock.deleteDatabaseFiles(dbName);

    final Firestore firestore = await restartable(dbName);
    final DocumentReference<Map<String, Object?>> docRef =
        firestore.collection('col1').document('doc1');
    await docRef.set(<String, Object?>{'foo': 'bar'});
    await firestore.terminate();

    final Firestore firestore2 = await restartable(dbName);
    final DocumentSnapshot<Map<String, Object?>> doc =
        await firestore2.document(docRef.path).get(Source.cache);
    expect(doc.data, <String, Object?>{'foo': 'bar'});
  });

  test('testClearPersistenceWhileRunningFails', () async {
    final Firestore firestore = await IntegrationTestUtil.testFirestore();
    await firestore.enableNetwork();

    await expectLater(firestore.clearPersistence(),
        throwsA(firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition)));

    // The instance keeps working.
    await firestore
        .collection('col1')
        .document('doc1')
        .set(<String, Object?>{'a': 1});
  });

  test('clearPersistence is a no-op for memory persistence', () async {
    final Firestore firestore = await IntegrationTestUtil.testFirestore(
        IntegrationTestUtil.newTestSettings()
            .copyWith(cacheSettings: const MemoryCacheSettings()));
    await firestore
        .collection('col1')
        .document('doc1')
        .set(<String, Object?>{'a': 1});
    await firestore.terminate();
    await firestore.clearPersistence();
  });
}
