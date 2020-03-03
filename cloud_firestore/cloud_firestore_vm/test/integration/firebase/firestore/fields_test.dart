// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:firebase_firestore/src/firebase/firestore/collection_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/query_snapshot.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/fields.db';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Map<String, Object> nestedObject(int number) {
    return map(<dynamic>[
      'name',
      'room $number',
      'metadata',
      map<dynamic>(<dynamic>[
        'createdAt',
        number,
        'deep',
        map<String>(<String>['field', 'deep-field-$number'])
      ])
    ]);
  }

  /// Creates test data with special characters in field names. Datastore
  /// currently prohibits mixing nested data with special characters so tests
  /// that use this data must be separate.
  Map<String, Object> dottedObject(int number) {
    return map(<dynamic>['field', 'field $number', 'field.dot', number.toDouble(), 'field\\slash', number.toDouble()]);
  }

  Map<String, Object> objectWithTimestamp(Timestamp timestamp) {
    return map(<dynamic>[
      'timestamp',
      timestamp,
      'nested',
      map<Timestamp>(<dynamic>['timestamp2', timestamp])
    ]);
  }

  test('testNestedFieldsCanBeWrittenWithSet', () async {
    final Map<String, Object> data = nestedObject(1);
    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(data);
    final DocumentSnapshot result = await docRef.get();
    expect(result.data, data);
  });

  test('testNestedFieldsCanReadDirectly', () async {
    final Map<String, Object> data = nestedObject(1);
    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(data);

    final DocumentSnapshot result = await docRef.get();
    expect(data['name'], result['name']);
    expect(result['metadata'], data['metadata']);

    final Map<String, Object> metadata = data['metadata'];
    final Map<String, Object> deepObject = metadata['deep'];
    expect(result['metadata.deep.field'], deepObject['field']);
    expect(result['metadata.nofield'], isNull);
    expect(result['nonmetadata.nofield'], isNull);
  });

  test('testNestedFieldCanBeUpdated', () async {
    final Map<String, Object> data = nestedObject(1);
    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(data);
    await docRef.updateFromList(<dynamic>['metadata.deep.field', 100.0, 'metadata.added', 200.0]);
    final DocumentSnapshot result = await docRef.get();
    final Map<String, Object> expectedData = map(<dynamic>[
      'name',
      'room 1',
      'metadata',
      map<dynamic>(<dynamic>[
        'createdAt',
        1.0,
        'deep',
        map<dynamic>(<dynamic>['field', 100.0]),
        'added',
        200.0
      ])
    ]);

    expect(result.data, expectedData);
  });

  test('testNestedFieldsCanBeUsedInQueryFilters', () async {
    final Map<String, Map<String, Object>> docs =
        map(<dynamic>['1', nestedObject(300), '2', nestedObject(100), '3', nestedObject(200)]);
    // inequality adds implicit sort on field
    final List<Map<String, Object>> expected = <Map<String, dynamic>>[nestedObject(200), nestedObject(300)];
    final CollectionReference collection = await testCollection();
    final List<Future<void>> tasks = <Future<void>>[];
    for (MapEntry<String, Map<String, Object>> entry in docs.entries) {
      tasks.add(collection.document(entry.key).set(entry.value));
    }

    await Future.wait(tasks);
    final Query query = collection.whereGreaterThanOrEqualTo('metadata.createdAt', 200);
    final QuerySnapshot res = await query.get();
    expect(querySnapshotToValues(res), expected);
  });

  test('testNestedFieldsCanBeUsedInOrderBy', () async {
    final Map<String, Map<String, Object>> docs =
        map(<dynamic>['1', nestedObject(300), '2', nestedObject(100), '3', nestedObject(200)]);
    final List<Map<String, Object>> expected = <Map<String, dynamic>>[
      nestedObject(100),
      nestedObject(200),
      nestedObject(300)
    ];
    final CollectionReference collection = await testCollection();
    final List<Future<void>> tasks = <Future<void>>[];
    for (MapEntry<String, Map<String, Object>> entry in docs.entries) {
      tasks.add(collection.document(entry.key).set(entry.value));
    }

    await Future.wait(tasks);
    final Query query = collection.orderBy('metadata.createdAt');
    final QuerySnapshot res = await query.get();
    expect(querySnapshotToValues(res), expected);
  });

  test('testFieldsWithSpecialCharsCanBeWrittenWithSet', () async {
    final Map<String, Object> data = dottedObject(1);
    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(data);
    final DocumentSnapshot doc = await docRef.get();
    expect(doc.data, data);
  });

  test('testFieldsWithSpecialCharsCanBeReadDirectly', () async {
    final Map<String, Object> data = dottedObject(1);
    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(data);
    final DocumentSnapshot doc = await docRef.get();
    expect(doc['field'], data['field']);
    expect(doc.getField(FieldPath.of(<String>['field.dot'])), data['field.dot']);
    expect(doc['field\\slash'], data['field\\slash']);
  });

  test('testFieldsWithSpecialCharsCanBeUpdated', () async {
    final Map<String, Object> data = dottedObject(1);
    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(data);
    await docRef.updateFromList(<dynamic>[
      FieldPath.of(<String>['field.dot']),
      100.0,
      'field\\slash',
      200.0
    ]);

    final DocumentSnapshot doc = await docRef.get();
    expect(doc.data, map<dynamic>(<dynamic>['field', 'field 1', 'field.dot', 100.0, 'field\\slash', 200.0]));
  });

  test('testFieldsWithSpecialCharsCanBeUsedInQueryFilters', () async {
    final Map<String, Map<String, Object>> docs =
        map(<dynamic>['1', dottedObject(300), '2', dottedObject(100), '3', dottedObject(200)]);
    // inequality adds implicit sort on field
    final List<Map<String, Object>> expected = <Map<String, dynamic>>[dottedObject(200), dottedObject(300)];
    final CollectionReference collection = await testCollection();
    final List<Future<void>> tasks = <Future<void>>[];
    for (MapEntry<String, Map<String, Object>> entry in docs.entries) {
      tasks.add(collection.document(entry.key).set(entry.value));
    }

    await Future.wait(tasks);

    final Query query = collection.whereGreaterThanOrEqualToField(FieldPath.of(<String>['field.dot']), 200);
    final QuerySnapshot res = await query.get();
    expect(querySnapshotToValues(res), expected);
  });

  test('testFieldsWithSpecialCharsCanBeUsedInOrderBy', () async {
    final Map<String, Map<String, dynamic>> docs =
        map(<dynamic>['1', dottedObject(300), '2', dottedObject(100), '3', dottedObject(200)]);
    final List<Map<String, Object>> expected = <Map<String, dynamic>>[
      dottedObject(100),
      dottedObject(200),
      dottedObject(300)
    ];

    final CollectionReference collection = await testCollection();
    final List<Future<void>> tasks = <Future<void>>[];
    for (MapEntry<String, Map<String, Object>> entry in docs.entries) {
      tasks.add(collection.document(entry.key).set(entry.value));
    }

    await Future.wait(tasks);

    Query query = collection.orderByField(FieldPath.of(<String>['field.dot']));
    QuerySnapshot res = await query.get();
    expect(querySnapshotToValues(res), expected);

    query = collection.orderBy('field\\slash');
    res = await query.get();
    expect(querySnapshotToValues(res), expected);
  });

  test('testTimestampsInSnapshots', () async {
    final Timestamp originalTimestamp = Timestamp(100, 123456789);
    // Timestamps are currently truncated to microseconds after being written to
    // the database.
    final Timestamp truncatedTimestamp =
        Timestamp(originalTimestamp.seconds, originalTimestamp.nanoseconds ~/ 1000 * 1000);

    final DocumentReference docRef = (await testCollection()).document();
    await docRef.set(objectWithTimestamp(originalTimestamp));
    final DocumentSnapshot snapshot = await docRef.get();
    final Map<String, Object> data = snapshot.data;

    final Timestamp readTimestamp = snapshot['timestamp'];
    expect(readTimestamp, truncatedTimestamp);
    expect(readTimestamp, data['timestamp']);

    final Timestamp readNestedTimestamp = snapshot['nested.timestamp2'];
    expect(readNestedTimestamp, truncatedTimestamp);

    final Map<String, Object> nestedObject = data['nested'];
    expect(nestedObject['timestamp2'], readNestedTimestamp);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
