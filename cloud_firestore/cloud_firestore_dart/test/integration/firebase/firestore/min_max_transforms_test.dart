// NOTE: Whether the Firestore emulator and production backends support the
// minimum/maximum field transforms is UNVERIFIED. These tests port the upstream
// Android SDK NumericTransformsTest cases and may fail against a backend that
// does not implement them yet.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/metadata_change.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/set_options.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';
import 'firestore_test.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/min_max_transforms.db';

  const double doubleEpsilon = 0.000001;

  // A document reference to read and write to.
  late DocumentReference docRef;

  // Accumulator used to capture events during the test.
  late EventAccumulator<DocumentSnapshot> accumulator;

  // Listener registration for a listener maintained during the course of the
  // test.
  late StreamSubscription<DocumentSnapshot> listenerRegistration;

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
  Future<void> _writeInitialData(Map<String, Object?> initialData) async {
    await docRef.set(initialData);
    await accumulator.awaitRemoteEvent();
  }

  Future<void> _expectLocalAndRemoteValueDouble(double expectedSum) async {
    DocumentSnapshot snap = await accumulator.awaitLocalEvent();

    expect(snap.get('sum'), isA<double>());
    expect(snap.getDouble('sum'),
        moreOrLessEquals(expectedSum, epsilon: doubleEpsilon));
    snap = await accumulator.awaitRemoteEvent();
    expect(snap.get('sum'), isA<double>());
    expect(snap.getDouble('sum'),
        moreOrLessEquals(expectedSum, epsilon: doubleEpsilon));
  }

  Future<void> _expectLocalAndRemoteValueInt(int expectedSum) async {
    DocumentSnapshot snap = await accumulator.awaitLocalEvent();
    expect(snap.get('sum'), isA<int>());
    expect(snap.getInt('sum'), expectedSum);
    snap = await accumulator.awaitRemoteEvent();
    expect(snap.get('sum'), isA<int>());
    expect(snap.getInt('sum'), expectedSum);
  }

  Future<void> _expectLocalAndRemoteNaN() async {
    DocumentSnapshot snap = await accumulator.awaitLocalEvent();
    expect(snap.get('sum'), isA<double>());
    expect(snap.getDouble('sum')!.isNaN, isTrue);
    snap = await accumulator.awaitRemoteEvent();
    expect(snap.get('sum'), isA<double>());
    expect(snap.getDouble('sum')!.isNaN, isTrue);
  }

  test('createDocumentWithMinimum', () async {
    await docRef.set(map(<dynamic>['sum', FieldValue.minimum(1337)]));
    await _expectLocalAndRemoteValueInt(1337);
  });

  test('createDocumentWithMaximum', () async {
    await docRef.set(map(<dynamic>['sum', FieldValue.maximum(1337)]));
    await _expectLocalAndRemoteValueInt(1337);
  });

  test('minimumWithExistingInteger', () async {
    await _writeInitialData(map(<dynamic>['sum', 10]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(5)});
    await _expectLocalAndRemoteValueInt(5);

    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(20)});
    await _expectLocalAndRemoteValueInt(5);
  });

  test('maximumWithExistingInteger', () async {
    await _writeInitialData(map(<dynamic>['sum', 10]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(5)});
    await _expectLocalAndRemoteValueInt(10);

    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(20)});
    await _expectLocalAndRemoteValueInt(20);
  });

  test('minimumWithExistingDouble', () async {
    await _writeInitialData(map(<dynamic>['sum', 10.5]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(5.5)});
    await _expectLocalAndRemoteValueDouble(5.5);

    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(20.5)});
    await _expectLocalAndRemoteValueDouble(5.5);
  });

  test('maximumWithExistingDouble', () async {
    await _writeInitialData(map(<dynamic>['sum', 10.5]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(5.5)});
    await _expectLocalAndRemoteValueDouble(10.5);

    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(20.5)});
    await _expectLocalAndRemoteValueDouble(20.5);
  });

  test('minimumOnExistingString', () async {
    await _writeInitialData(map(<dynamic>['sum', 'overwrite']));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(7)});
    await _expectLocalAndRemoteValueInt(7);
  });

  test('maximumOnExistingString', () async {
    await _writeInitialData(map(<dynamic>['sum', 'overwrite']));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(7)});
    await _expectLocalAndRemoteValueInt(7);
  });

  test('mixedTypesPreserveOperandTypeForMinimum', () async {
    // Field and operand of mixed types: the field takes the type of the
    // smaller one.
    await _writeInitialData(map(<dynamic>['sum', 10]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(5.5)});
    await _expectLocalAndRemoteValueDouble(5.5);

    await _writeInitialData(map(<dynamic>['sum', 10.5]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(5)});
    await _expectLocalAndRemoteValueInt(5);
  });

  test('mixedTypesPreserveOperandTypeForMaximum', () async {
    // Field and operand of mixed types: the field takes the type of the
    // larger one.
    await _writeInitialData(map(<dynamic>['sum', 10]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(20.5)});
    await _expectLocalAndRemoteValueDouble(20.5);

    await _writeInitialData(map(<dynamic>['sum', 10.5]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(20)});
    await _expectLocalAndRemoteValueInt(20);
  });

  test('equivalentValuesDoNotChangeTypeForMinimum', () async {
    // Equivalent values (3 and 3.0): the field keeps its type.
    await _writeInitialData(map(<dynamic>['sum', 3]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(3.0)});
    await _expectLocalAndRemoteValueInt(3);

    await _writeInitialData(map(<dynamic>['sum', 3.0]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(3)});
    await _expectLocalAndRemoteValueDouble(3.0);
  });

  test('equivalentValuesDoNotChangeTypeForMaximum', () async {
    await _writeInitialData(map(<dynamic>['sum', 3]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(3.0)});
    await _expectLocalAndRemoteValueInt(3);

    await _writeInitialData(map(<dynamic>['sum', 3.0]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(3)});
    await _expectLocalAndRemoteValueDouble(3.0);
  });

  test('minimumWithNaN', () async {
    // If one of the values is NaN, the minimum is NaN.
    await _writeInitialData(map(<dynamic>['sum', double.nan]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.minimum(5)});
    await _expectLocalAndRemoteNaN();

    await _writeInitialData(map(<dynamic>['sum', 5]));
    await docRef
        .update(<String, dynamic>{'sum': FieldValue.minimum(double.nan)});
    await _expectLocalAndRemoteNaN();
  });

  test('maximumWithNaN', () async {
    await _writeInitialData(map(<dynamic>['sum', double.nan]));
    await docRef.update(<String, dynamic>{'sum': FieldValue.maximum(5)});
    await _expectLocalAndRemoteNaN();

    await _writeInitialData(map(<dynamic>['sum', 5]));
    await docRef
        .update(<String, dynamic>{'sum': FieldValue.maximum(double.nan)});
    await _expectLocalAndRemoteNaN();
  });

  test('mergeOnNonExistingDocumentWithMaximum', () async {
    await docRef.set(map(<dynamic>['sum', FieldValue.maximum(1337)]),
        SetOptions.mergeAllFields);
    await _expectLocalAndRemoteValueInt(1337);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
