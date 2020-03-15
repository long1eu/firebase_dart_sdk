// File created by
// Lung Razvan <long1eu>
// on 13/03/2020

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/set_options.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';
import 'firestore_test.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/numeric_transforms.db';

  const double doubleEpsilon = 0.000001;

  // A document reference to read and write to.
  DocumentReference docRef;

  // Accumulator used to capture events during the test.
  EventAccumulator<DocumentSnapshot> accumulator;

  // Listener registration for a listener maintained during the course of the
  // test.
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
    await listenerRegistration.cancel();
    await IntegrationTestUtil.tearDown();
  });

  /// Writes some initialData and consumes the events generated.
  Future<void> _writeInitialData(Map<String, Object> initialData) async {
    await docRef.set(initialData);
    await accumulator.awaitRemoteEvent();
  }

  Future<void> _expectLocalAndRemoteValueDouble(double expectedSum) async {
    DocumentSnapshot snap = await accumulator.awaitLocalEvent();

    expect(snap.getDouble('sum'),
        moreOrLessEquals(expectedSum, epsilon: doubleEpsilon));
    snap = await accumulator.awaitRemoteEvent();
    expect(snap.getDouble('sum'),
        moreOrLessEquals(expectedSum, epsilon: doubleEpsilon));
  }

  Future<void> _expectLocalAndRemoteValueInt(int expectedSum) async {
    DocumentSnapshot snap = await accumulator.awaitLocalEvent();
    expect(snap.getInt('sum'), expectedSum);
    snap = await accumulator.awaitRemoteEvent();
    expect(snap.getInt('sum'), expectedSum);
  }

  test('createDocumentWithIncrement', () async {
    await docRef.set(map(<dynamic>['sum', FieldValue.increment(1337)]));
    await _expectLocalAndRemoteValueInt(1337);
  });

  test('mergeOnNonExistingDocumentWithIncrement', () async {
    await docRef.set(map(<dynamic>['sum', FieldValue.increment(1337)]),
        SetOptions.mergeAllFields);
    await _expectLocalAndRemoteValueInt(1337);
  });

  test('integerIncrementWithExistingInteger', () async {
    await _writeInitialData(map(<dynamic>['sum', 1337]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.increment(1)});
    await _expectLocalAndRemoteValueInt(1338);
  });

  test('doubleIncrementWithExistingDouble', () async {
    await _writeInitialData(map(<dynamic>['sum', 13.37]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.increment(0.1)});
    await _expectLocalAndRemoteValueDouble(13.47);
  });

  test('integerIncrementWithExistingDouble', () async {
    await _writeInitialData(map(<dynamic>['sum', 13.37]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.increment(1)});
    await _expectLocalAndRemoteValueDouble(14.37);
  });

  test('doubleIncrementWithExistingInteger', () async {
    await _writeInitialData(map(<dynamic>['sum', 1337]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.increment(0.1)});
    await _expectLocalAndRemoteValueDouble(1337.1);
  });

  test('integerIncrementWithExistingString', () async {
    await _writeInitialData(map(<dynamic>['sum', 'overwrite']));
    await docRef.update(<String, dynamic>{'sum': FieldValue.increment(1337)});
    await _expectLocalAndRemoteValueInt(1337);
  });

  test('doubleIncrementWithExistingString', () async {
    await _writeInitialData(map(<dynamic>['sum', 'overwrite']));
    await docRef.update(<String, dynamic>{'sum': FieldValue.increment(13.37)});
    await _expectLocalAndRemoteValueDouble(13.37);
  });

  test('multipleDoubleIncrements', () async {
    await _writeInitialData(map(<dynamic>['sum', 0.0]));
    await docRef.firestore.disableNetwork();

    unawaited(
        docRef.update(<String, dynamic>{'sum': FieldValue.increment(0.1)}));
    unawaited(
        docRef.update(<String, dynamic>{'sum': FieldValue.increment(0.01)}));
    unawaited(
        docRef.update(<String, dynamic>{'sum': FieldValue.increment(0.001)}));

    DocumentSnapshot snap = await accumulator.awaitLocalEvent();
    expect(
        snap.getDouble('sum'), moreOrLessEquals(0.1, epsilon: doubleEpsilon));
    snap = await accumulator.awaitLocalEvent();
    expect(
        snap.getDouble('sum'), moreOrLessEquals(0.11, epsilon: doubleEpsilon));
    snap = await accumulator.awaitLocalEvent();
    expect(
        snap.getDouble('sum'), moreOrLessEquals(0.111, epsilon: doubleEpsilon));

    await docRef.firestore.enableNetwork();
    snap = await accumulator.awaitRemoteEvent();
    /*
    expect(
        snap.getDouble('sum'), moreOrLessEquals(0.111, epsilon: doubleEpsilon));
    */
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
