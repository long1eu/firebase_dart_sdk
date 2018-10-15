// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:firebase_firestore/src/firebase/firestore/transaction.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/server_timestamp';

  // Data written in tests via set.
  final Map<String, Object> setData = map(<dynamic>[
    'a',
    42,
    'when',
    FieldValue.serverTimestamp(),
    'deep',
    map<FieldValue>(<dynamic>['when', FieldValue.serverTimestamp()])
  ]);

  // Base and update data used for update tests.
  final Map<String, Object> initialData = map(<dynamic>['a', 42]);
  final Map<String, Object> updateData = map<dynamic>(<dynamic>[
    'when',
    FieldValue.serverTimestamp(),
    'deep',
    map<FieldValue>(<dynamic>['when', FieldValue.serverTimestamp()])
  ]);

  // A document reference to read and write to.
  DocumentReference docRef;

  // Accumulator used to capture events during the test.
  EventAccumulator<DocumentSnapshot> accumulator;

  // Listener registration for a listener maintained during the course of the test.
  StreamSubscription<DocumentSnapshot> listenerRegistration;

  setUp(() async {
    docRef = await testDocument();
    accumulator = EventAccumulator<DocumentSnapshot>();
    listenerRegistration = docRef
        .getSnapshots(MetadataChanges.include)
        .listen(accumulator.onData, onError: accumulator.onError);

    // Wait for initial null snapshot to avoid potential races.
    final DocumentSnapshot initialSnapshot = await accumulator.wait();
    expect(initialSnapshot.exists, isFalse);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    listenerRegistration.cancel();
    await IntegrationTestUtil.tearDown();
  });

  // Returns the expected data, with an arbitrary timestamp substituted in.
  Map<String, Object> expectedDataWithTimestamp(Object timestamp) {
    return map(<dynamic>[
      'a',
      42,
      'when',
      timestamp,
      'deep',
      map<dynamic>(<dynamic>['when', timestamp])
    ]);
  }

  /// Writes initialData and waits for the corresponding snapshot.
  Future<void> writeInitialData() async {
    await docRef.set(initialData);
    DocumentSnapshot initialDataSnap = await accumulator.wait();
    expect(initialDataSnap.data, initialData);
    initialDataSnap = await accumulator.wait();
    expect(initialDataSnap.data, initialData);
  }

  /// Verifies a snapshot containing setData but with null for the timestamps.
  void verifyTimestampsAreNull(DocumentSnapshot snapshot) {
    expect(snapshot.data, expectedDataWithTimestamp(null));
  }

  /// Verifies a snapshot containing setData but with resolved server
  /// timestamps.
  void verifyTimestampsAreResolved(DocumentSnapshot snapshot) {
    expect(snapshot.exists, isTrue);
    final Timestamp when = snapshot.getTimestamp('when');
    expect(when, isNotNull);
    // Tolerate up to 48*60*60 seconds of clock skew between client and server.
    // This should be more than enough to compensate for timezone issues (even
    // after taking daylight saving into account) and should allow local clocks
    // to deviate from true time slightly and still pass the test.
    const int deltaSec = 48 * 60 * 60;
    final Timestamp now = Timestamp.now();
    expect((when.seconds - now.seconds).abs() < deltaSec, isTrue,
        reason:
        'resolved timestamp ($when) should be within $deltaSec\s of now ($now)');

    // Validate the rest of the document.
    expect(snapshot.data, expectedDataWithTimestamp(when));
  }

  /// Verifies a snapshot containing setData but with local estimates for server
  /// timestamps.
  void verifyTimestampsAreEstimates(DocumentSnapshot snapshot) {
    expect(snapshot.exists, isTrue);
    final Timestamp when =
    snapshot.getTimestamp('when', ServerTimestampBehavior.estimate);
    expect(when, isNotNull);
    expect(snapshot.getData(ServerTimestampBehavior.estimate),
        expectedDataWithTimestamp(when));
  }

  /// Verifies a snapshot containing setData but using the previous field value
  /// for the timestamps.
  void verifyTimestampsUsePreviousValue(DocumentSnapshot current, DocumentSnapshot previous) {
    expect(current.exists, isTrue);
    if (previous != null) {
      final Timestamp when = previous.getTimestamp('when');
      expect(when, isNotNull);
      expect(current.getData(ServerTimestampBehavior.previous),
          expectedDataWithTimestamp(when));
    } else {
      expect(current.getData(ServerTimestampBehavior.previous),
          expectedDataWithTimestamp(null));
    }
  }

  test('testServerTimestampsWorkViaSet', () async {
    await docRef.set(setData);
    verifyTimestampsAreNull(await accumulator.awaitLocalEvent());
    verifyTimestampsAreResolved(await accumulator.awaitRemoteEvent());
  });

  test('testServerTimestampsWorkViaUpdate', () async {
    await writeInitialData();
    await docRef.update(updateData);
    verifyTimestampsAreNull(await accumulator.awaitLocalEvent());
    verifyTimestampsAreResolved(await accumulator.awaitRemoteEvent());
  });

  test('testServerTimestampsCanReturnEstimatedValue', () async {
    await writeInitialData();
    await docRef.update(updateData);
    verifyTimestampsAreEstimates(await accumulator.awaitLocalEvent());
    verifyTimestampsAreResolved(await accumulator.awaitRemoteEvent());
  });

  test('testServerTimestampsCanReturnPreviousValue', () async {
    await writeInitialData();
    await docRef.update(updateData);
    verifyTimestampsUsePreviousValue(await accumulator.awaitLocalEvent(), null);

    final DocumentSnapshot previousSnapshot =
    await accumulator.awaitRemoteEvent();
    verifyTimestampsAreResolved(previousSnapshot);

    await docRef.update(updateData);
    verifyTimestampsUsePreviousValue(
        await accumulator.awaitLocalEvent(), previousSnapshot);
    verifyTimestampsAreResolved(await accumulator.awaitRemoteEvent());
  });

  test('testServerTimestampsCanReturnPreviousValueOfDifferentType', () async {
    await writeInitialData();
    await docRef.updateFromList(<dynamic>['a', FieldValue.serverTimestamp()]);

    final DocumentSnapshot localSnapshot = await accumulator.awaitLocalEvent();
    expect(localSnapshot.get('a'), isNull);
    expect(localSnapshot.get('a', ServerTimestampBehavior.estimate),
        const TypeMatcher<Timestamp>());
    expect(localSnapshot.get('a', ServerTimestampBehavior.previous), 42);

    final DocumentSnapshot remoteSnapshot =
    await accumulator.awaitRemoteEvent();
    expect(remoteSnapshot.get('a'), const TypeMatcher<Timestamp>());
    expect(remoteSnapshot.get('a', ServerTimestampBehavior.estimate),
        const TypeMatcher<Timestamp>());
    expect(remoteSnapshot.get('a', ServerTimestampBehavior.previous),
        const TypeMatcher<Timestamp>());
  });

  test('testServerTimestampsCanRetainPreviousValueThroughConsecutiveUpdates',
          () async {
        await writeInitialData();
        await docRef.firestore.client.disableNetwork();
        await accumulator.awaitRemoteEvent();

        docRef.updateFromList(<dynamic>['a', FieldValue.serverTimestamp()]);
        DocumentSnapshot localSnapshot = await accumulator.awaitLocalEvent();
        expect(localSnapshot.get('a', ServerTimestampBehavior.previous), 42);

        docRef.updateFromList(<dynamic>['a', FieldValue.serverTimestamp()]);
        localSnapshot = await accumulator.awaitLocalEvent();
        expect(localSnapshot.get('a', ServerTimestampBehavior.previous), 42);

        await docRef.firestore.client.enableNetwork();

        final DocumentSnapshot remoteSnapshot =
        await accumulator.awaitRemoteEvent();
        expect(remoteSnapshot.get('a'), const TypeMatcher<Timestamp>());
      });

  test('testServerTimestampsUsesPreviousValueFromLocalMutation', () async {
    await writeInitialData();
    await docRef.firestore.client.disableNetwork();
    await accumulator.awaitRemoteEvent();

    docRef.updateFromList(<dynamic>['a', FieldValue.serverTimestamp()]);
    DocumentSnapshot localSnapshot = await accumulator.awaitLocalEvent();
    expect(localSnapshot.get('a', ServerTimestampBehavior.previous), 42);

    docRef.updateFromList(<dynamic>['a', 1337]);
    await accumulator.awaitLocalEvent();

    docRef.updateFromList(<dynamic>['a', FieldValue.serverTimestamp()]);
    localSnapshot = await accumulator.awaitLocalEvent();
    expect(localSnapshot.get('a', ServerTimestampBehavior.previous), 1337);

    await docRef.firestore.client.enableNetwork();

    final DocumentSnapshot remoteSnapshot =
    await accumulator.awaitRemoteEvent();
    expect(remoteSnapshot.get('a'), const TypeMatcher<Timestamp>());
  });

  //todo
  test('testServerTimestampsWorkViaTransactionSet', () async {
    await docRef.firestore.runTransaction<void>((Transaction transaction) {
      transaction.set(docRef, setData);
      return null;
    });
    verifyTimestampsAreResolved(await accumulator.awaitRemoteEvent());
  });

  //todo
  test('testServerTimestampsWorkViaTransactionUpdate', () async {
    await writeInitialData();
    await docRef.firestore.runTransaction<void>((Transaction transaction) {
      transaction.update(docRef, updateData);
      return null;
    });
    verifyTimestampsAreResolved(await accumulator.awaitRemoteEvent());
  });

  test('testServerTimestampsFailViaUpdateOnNonexistentDocument', () async {
    bool hadError = false;
    try {
      await docRef.update(updateData);
    } on FirebaseFirestoreError catch (e) {
      hadError = true;
      expect(e, isNotNull);
      expect(e.code, FirebaseFirestoreErrorCode.notFound);
    } catch (e) {
      assert(false, 'This should not happen.');
    }
    expect(hadError, isTrue);
  });

  test('testServerTimestampsFailViaTransactionUpdateOnNonexistentDocument',
          () async {
        bool hadError = false;
        try {
          await docRef.firestore.runTransaction<void>((Transaction transaction) {
            transaction.update(docRef, updateData);
            return null;
          });
        } on FirebaseFirestoreError catch (e) {
          hadError = true;
          expect(e, isNotNull);
          // TODO: This should be a NOT_FOUND, but right now we retry transactions
          // on any error and so this turns into ABORTED instead.
          expect(e.code, FirebaseFirestoreErrorCode.aborted);
        } catch (e) {
          assert(false, 'This should not happen.');
        }
        expect(hadError, isTrue);
      });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const testDocument = IntegrationTestUtil.testDocument;
