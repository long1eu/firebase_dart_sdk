// Regression tests for the defects recorded in reviews/review_followups.md.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/firestore_client.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/timer_task.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/test_util.dart' as util;
import 'clear_persistence_test.dart'
    show firestoreErrorWithCode, newApp, offlineSettings, openFixed;
import 'local/mock/database_mock.dart';

import '../../../util/test_hygiene.dart';

class _Client extends Mock implements FirestoreClient {}

String? _nickname(
        DocumentSnapshot<Map<String, Object?>> snapshot, SnapshotOptions? o) =>
    snapshot.data!['nickname'] as String?;

Map<String, Object?> _nicknameToFirestore(String? value, SetOptions? o) =>
    <String, Object?>{'nickname': value};

const FirestoreDataConverter<String?> nicknameConverter =
    FirestoreDataConverter<String?>.from(
  fromFirestore: _nickname,
  toFirestore: _nicknameToFirestore,
);

String? _upperNickname(
        DocumentSnapshot<Map<String, Object?>> snapshot, SnapshotOptions? o) =>
    (snapshot.data!['nickname'] as String?)?.toUpperCase();

const FirestoreDataConverter<String?> upperNicknameConverter =
    FirestoreDataConverter<String?>.from(
  fromFirestore: _upperNickname,
  toFirestore: _nicknameToFirestore,
);

void main() {
  checkTestsLeaveNothingBehind();

  group('converters', () {
    late Firestore db;

    setUp(() {
      db = FirestoreInternal.create(
          DatabaseId.forProject('p'), null, _Client(), TaskScheduler('test'));
    });

    test('a QueryDocumentSnapshot returns a null that its converter produced',
        () {
      final Document doc =
          util.doc('users/a', 1, <String, Object?>{'nickname': null});
      final QueryDocumentSnapshot<String?> snapshot =
          QueryDocumentSnapshotInternal.fromDocument<String?>(
        db,
        doc,
        fromCache: false,
        hasPendingWrites: false,
        converter: nicknameConverter,
      );

      expect(snapshot.data, isNull);
      expect(snapshot.getData(ServerTimestampBehavior.estimate), isNull);
    });

    test('snapshots with different converters are not equal', () {
      final Document doc =
          util.doc('users/a', 1, <String, Object?>{'nickname': 'n'});
      DocumentSnapshot<String?> snapshot(
              FirestoreDataConverter<String?> converter) =>
          DocumentSnapshotInternal.fromDocument<String?>(
            db,
            doc,
            isFromCache: false,
            hasPendingWrites: false,
            converter: converter,
          );

      expect(snapshot(nicknameConverter), snapshot(nicknameConverter));
      expect(snapshot(nicknameConverter).hashCode,
          snapshot(nicknameConverter).hashCode);
      // They convert the same document to different values ('n' and 'N').
      expect(snapshot(nicknameConverter),
          isNot(snapshot(upperNicknameConverter)));
    });
  });

  group('instance lifecycle', () {
    test('instanceFor does not return an instance that is being terminated',
        () async {
      final FirebaseApp app = newApp('reviewTerminateRace');
      addTearDown(app.delete);
      final FirestoreSettings memory = offlineSettings.copyWith(
          cacheSettings: const MemoryCacheSettings());

      final Firestore first =
          await Firestore.instanceFor(app: app, settings: memory);
      final Future<void> terminating = first.terminate();
      // terminate() was called: from now on the app has no usable instance.
      final Firestore second =
          await Firestore.instanceFor(app: app, settings: memory);
      addTearDown(second.terminate);
      await terminating;

      expect(second, isNot(same(first)));
      expect(second.client.isTerminated, isFalse);
      // The new instance stays registered after the old one finished.
      expect(await Firestore.instanceFor(app: app, settings: memory),
          same(second));
    });

    test(
        'clearPersistence of a terminated instance fails while a newer '
        'instance of the same database is running', () async {
      final String dbName = 'review-clear-${const Uuid().v4()}.db';
      addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
      final FirebaseApp app = newApp('reviewClearWhileRestarted');
      addTearDown(app.delete);

      final Firestore first = await Firestore.instanceFor(
          app: app, settings: offlineSettings, openDatabase: openFixed(dbName));
      await first.terminate();

      final Firestore second = await Firestore.instanceFor(
          app: app, settings: offlineSettings, openDatabase: openFixed(dbName));

      // The file is open in [second]: deleting it would silently detach the
      // running instance from its cache.
      await expectLater(first.clearPersistence(),
          throwsA(firestoreErrorWithCode(FirestoreErrorCode.failedPrecondition)));
      expect(DatabaseMock.pathForName(dbName).existsSync(), isTrue);

      await second.terminate();
      await first.clearPersistence();
      expect(DatabaseMock.pathForName(dbName).existsSync(), isFalse);
    });
  });
}
