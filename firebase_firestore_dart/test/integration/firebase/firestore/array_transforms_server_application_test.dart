// File created by
// Lung Razvan <long1eu>
// on 10/10/2018
import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/firebase_firestore_error.dart';
import 'package:firebase_firestore/src/firebase/firestore/set_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

/// Unlike the array_transforms_test.dart tests, these tests intentionally avoid
/// having any ongoing listeners so that we can test what gets stored in the
/// offline cache based purely on the write acknowledgement (without receiving
/// an updated document via watch). As such they also rely on persistence being
/// enabled so documents remain in the cache after the write.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/array_transforms';

  // A document reference to read and write to.
  DocumentReference docRef;

  setUp(() async {
    docRef = await testDocument();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('setWithNoCachedBaseDoc', () async {
    await docRef.set(map(<dynamic>[
      'array',
      FieldValue.arrayUnion(<int>[1, 2])
    ]));
    final DocumentSnapshot snapshot = await docRef.get(Source.cache);
    expect(
        snapshot.data,
        map<List<int>>(<dynamic>[
          'array',
          <int>[1, 2]
        ]));
  });

  test('updateWithNoCachedBaseDoc', () async {
    // Write an initial document in an isolated Firestore instance so it's not
    // stored in our cache.
    await (await testFirestore(newTestSettings(), 'integration/array_transforms_updateWithNoCachedBaseDoc.db'))
        .document(docRef.path)
        .set(map(<dynamic>[
          'array',
          <int>[42]
        ]));

    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayUnion(<int>[1, 2])
    ]));

    // Nothing should be cached since it was an update and we had no base doc.
    try {
      await docRef.get(Source.cache);
    } on FirebaseFirestoreError catch (e) {
      expect(e.code, FirebaseFirestoreErrorCode.unavailable);
    }
  });

  test('mergeSetWithNoCachedBaseDoc', () async {
    // Write an initial document in an isolated Firestore instance so it's not
    // stored in our cache.
    await (await testFirestore(newTestSettings(), 'integration/array_transforms_mergeSetWithNoCachedBaseDoc.db'))
        .document(docRef.path)
        .set(map(<dynamic>[
          'array',
          <int>[42]
        ]));

    await docRef.set(
        map(<dynamic>[
          'array',
          FieldValue.arrayUnion(<int>[1, 2])
        ]),
        SetOptions.mergeAllFields);

    // Document will be cached but we'll be missing 42.
    final DocumentSnapshot snapshot = await docRef.get(Source.cache);
    expect(
        snapshot.data,
        map<List<int>>(<dynamic>[
          'array',
          <int>[1, 2]
        ]));
  });

  test('updateWithCachedBaseDocUsingArrayUnion', () async {
    await docRef.set(map<List<int>>(<dynamic>[
      'array',
      <int>[42]
    ]));
    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayUnion(<int>[1, 2])
    ]));
    final DocumentSnapshot snapshot = await docRef.get(Source.cache);
    expect(
        snapshot.data,
        map<List<int>>(<dynamic>[
          'array',
          <int>[42, 1, 2]
        ]));
  });

  test('updateWithCachedBaseDocUsingArrayRemove', () async {
    await docRef.set(map(<dynamic>[
      'array',
      <int>[42, 1, 2]
    ]));
    await docRef.update(map(<dynamic>[
      'array',
      FieldValue.arrayRemove(<int>[1, 2])
    ]));
    final DocumentSnapshot snapshot = await docRef.get(Source.cache);
    expect(
        snapshot.data,
        map<List<int>>(<dynamic>[
          'array',
          <int>[42]
        ]));
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testDocument = IntegrationTestUtil.testDocument;
// ignore: always_specify_types, type_annotate_public_apis
const newTestSettings = IntegrationTestUtil.newTestSettings;
