// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/metadata_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/set_options.dart';
import 'package:test/test.dart';

import '../../../util/event_accumulator.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

/// Note: Transforms are tested pretty thoroughly via [ServerTimestampTest] (via
/// set, update, transactions, nested in documents, multiple transforms
/// together, etc.) and so these tests mostly focus on the array transform
/// semantics.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/array_transforms';

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

  Future<void> expectLocalAndRemoteEvent(
      Map<String, Object> expectedData) async {
    DocumentSnapshot snap = await accumulator.awaitLocalEvent();
    expect(snap.data, expectedData);
    snap = await accumulator.awaitRemoteEvent();
    expect(snap.data, expectedData);
  }

  /// Writes some initialData and consumes the events generated.
  Future<void> writeInitialData(Map<String, Object> initialData) async {
    await docRef.set(initialData);
    await expectLocalAndRemoteEvent(initialData);
  }

  test('createDocumentWithArrayUnion', () async {
    await docRef.set(map(<dynamic>[
      'array',
      FieldValue.arrayUnion(<int>[1, 2])
    ]));
    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <int>[1, 2]
    ]));
  });

  test('appendToArrayViaUpdate', () async {
    await writeInitialData(map(<dynamic>[
      'array',
      <int>[1, 3]
    ]));
    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayUnion(<int>[2, 1, 4])
    ]));
    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <int>[1, 3, 2, 4]
    ]));
  });

  test('appendToArrayViaSetWithMerge', () async {
    await writeInitialData(map(<dynamic>[
      'array',
      <int>[1, 3]
    ]));
    await docRef.set(
        map(<dynamic>[
          'array',
          FieldValue.arrayUnion(<int>[2, 1, 4])
        ]),
        SetOptions.mergeAllFields);
    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <int>[1, 3, 2, 4]
    ]));
  });

  test('appendObjectToArrayViaUpdate', () async {
    await writeInitialData(map(<dynamic>[
      'array',
      <Map<String, String>>[
        map(<String>['a', 'hi'])
      ]
    ]));
    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayUnion(<Map<String, String>>[
        map(<String>['a', 'hi']),
        map(<String>['a', 'bye'])
      ])
    ]));
    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <Map<String, String>>[
        map(<String>['a', 'hi']),
        map(<String>['a', 'bye'])
      ]
    ]));
  });

  test('removeFromArrayViaUpdate', () async {
    await writeInitialData(map(<dynamic>[
      'array',
      <int>[1, 3, 1, 3]
    ]));
    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayRemove(<int>[1, 4])
    ]));
    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <int>[3, 3]
    ]));
  });

  test('removeFromArrayViaSetMerge', () async {
    await writeInitialData(map(<dynamic>[
      'array',
      <int>[1, 3, 1, 3]
    ]));

    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayRemove(<int>[1, 4])
    ]));

    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <int>[3, 3]
    ]));
  });

  test('removeObjectFromArrayViaUpdate', () async {
    await writeInitialData(map(<dynamic>[
      'array',
      <Map<String, String>>[
        map(<String>['a', 'hi']),
        map(<String>['a', 'bye'])
      ]
    ]));
    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayRemove(<Map<String, String>>[
        map(<String>['a', 'hi'])
      ])
    ]));
    await expectLocalAndRemoteEvent(map(<dynamic>[
      'array',
      <Map<String, String>>[
        map(<String>['a', 'bye'])
      ]
    ]));
  });
}

// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types
const testDocument = IntegrationTestUtil.testDocument;
