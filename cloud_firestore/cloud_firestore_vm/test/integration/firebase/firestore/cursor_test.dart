// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/cursor';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('canPageThroughItems', () async {
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a',
      map<String>(<String>['v', 'a']),
      'b',
      map<String>(<String>['v', 'b']),
      'c',
      map<String>(<String>['v', 'c']),
      'd',
      map<String>(<String>['v', 'd']),
      'e',
      map<String>(<String>['v', 'e']),
      'f',
      map<String>(<String>['v', 'f'])
    ]));

    QuerySnapshot snapshot = await testCollection.limit(2).get();
    expect(querySnapshotToValues(snapshot), <Map<String, String>>[
      map<String>(<String>['v', 'a']),
      map<String>(<String>['v', 'b'])
    ]);

    DocumentSnapshot lastDoc = snapshot.documents[1];
    snapshot = await testCollection.limit(3).startAfterDocument(lastDoc).get();

    expect(querySnapshotToValues(snapshot), <Map<String, String>>[
      map<String>(<String>['v', 'c']),
      map<String>(<String>['v', 'd']),
      map<String>(<String>['v', 'e'])
    ]);

    lastDoc = snapshot.documents[2];
    snapshot = await testCollection.limit(1).startAfterDocument(lastDoc).get();
    expect(querySnapshotToValues(snapshot), <Map<String, String>>[
      map<String>(<String>['v', 'f'])
    ]);

    lastDoc = snapshot.documents[0];
    snapshot = await testCollection.limit(3).startAfterDocument(lastDoc).get();
    expect(querySnapshotToValues(snapshot), <Map<String, String>>[]);
  });

  test('canBeCreatedFromDocuments', () async {
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a', map<dynamic>(<dynamic>['k', 'a', 'sort', 1.0]),
      'b', map<dynamic>(<dynamic>['k', 'b', 'sort', 2.0]),
      'c', map<dynamic>(<dynamic>['k', 'c', 'sort', 2.0]),
      'd', map<dynamic>(<dynamic>['k', 'd', 'sort', 2.0]),
      'e', map<dynamic>(<dynamic>['k', 'e', 'sort', 0.0]),
      'f',
      map<dynamic>(<dynamic>['k', 'f', 'nosort', 1.0]) // should not show up
    ]));

    final Query query = testCollection.orderBy('sort');
    final DocumentSnapshot snapshot = await testCollection.document('c').get();

    expect(snapshot.exists, isTrue);

    QuerySnapshot querySnapshot = await query.startAtDocument(snapshot).get();

    expect(querySnapshotToValues(querySnapshot), <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'c', 'sort', 2.0]),
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2.0]),
    ]);

    querySnapshot = await query.endBeforeDocument(snapshot).get();
    expect(querySnapshotToValues(querySnapshot), <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'e', 'sort', 0.0]),
      map<dynamic>(<dynamic>['k', 'a', 'sort', 1.0]),
      map<dynamic>(<dynamic>['k', 'b', 'sort', 2.0]),
    ]);
  });

  test('canBeCreatedFromValues', () async {
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a', map<dynamic>(<dynamic>['k', 'a', 'sort', 1.0]),
      'b', map<dynamic>(<dynamic>['k', 'b', 'sort', 2.0]),
      'c', map<dynamic>(<dynamic>['k', 'c', 'sort', 2.0]),
      'd', map<dynamic>(<dynamic>['k', 'd', 'sort', 2.0]),
      'e', map<dynamic>(<dynamic>['k', 'e', 'sort', 0.0]),
      'f',
      map<dynamic>(<dynamic>['k', 'f', 'nosort', 1.0]) // should not show up
    ]));

    final Query query = testCollection.orderBy('sort');
    QuerySnapshot snapshot = await query.startAt(<double>[2.0]).get();

    expect(querySnapshotToValues(snapshot), <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'b', 'sort', 2.0]),
      map<dynamic>(<dynamic>['k', 'c', 'sort', 2.0]),
      map<dynamic>(<dynamic>['k', 'd', 'sort', 2.0]),
    ]);

    snapshot = await query.endBefore(<double>[2.0]).get();
    expect(querySnapshotToValues(snapshot), <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'e', 'sort', 0.0]),
      map<dynamic>(<dynamic>['k', 'a', 'sort', 1.0]),
    ]);
  });

  test('canBeCreatedUsingDocumentId', () async {
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      'a',
      map<String>(<String>['k', 'a']),
      'b',
      map<String>(<String>['k', 'b']),
      'c',
      map<String>(<String>['k', 'c']),
      'd',
      map<String>(<String>['k', 'd']),
      'e',
      map<String>(<String>['k', 'e'])
    ]);

    final CollectionReference writer = (await testFirestore(newTestSettings(),
            'integration/cursor_canBeCreatedUsingDocumentId.db'))
        .collection('parent-collection')
        .document()
        .collection('sub-collection');
    await writeAllDocs(writer, testDocs);

    final CollectionReference reader =
        (await testFirestore()).collection(writer.path);

    final QuerySnapshot snapshot = await reader
        .orderByField(FieldPath.documentId())
        .startAt(<String>['b']).endBefore(<String>['d']).get();

    expect(querySnapshotToValues(snapshot), <dynamic>[
      map<dynamic>(<dynamic>['k', 'b']),
      map<dynamic>(<dynamic>['k', 'c']),
    ]);
  });

  test('canBeUsedWithReferenceValues', () async {
    final Firestore firestore = await testFirestore();
    final Map<String, Map<String, Object>> testDocs = map(<dynamic>[
      'a',
      map<dynamic>(
          <dynamic>['k', '1a', 'ref', firestore.collection('1').document('a')]),
      'b',
      map<dynamic>(
          <dynamic>['k', '1b', 'ref', firestore.collection('1').document('b')]),
      'c',
      map<dynamic>(
          <dynamic>['k', '2a', 'ref', firestore.collection('2').document('a')]),
      'd',
      map<dynamic>(
          <dynamic>['k', '2b', 'ref', firestore.collection('2').document('b')]),
      'e',
      map<dynamic>(
          <dynamic>['k', '3a', 'ref', firestore.collection('3').document('a')])
    ]);

    final CollectionReference testCollection =
        await testCollectionWithDocs(testDocs);

    final QuerySnapshot snapshot = await testCollection
        .orderBy('ref')
        .startAfter(<DocumentReference>[
      firestore.collection('1').document('a')
    ]).endAt(
            <DocumentReference>[firestore.collection('2').document('b')]).get();

    final List<String> results = <String>[];
    for (DocumentSnapshot doc in snapshot) {
      results.add(doc.getString('k'));
    }
    expect(results, <String>['1b', '2a', '2b']);
  });

  test('canBeUsedInDescendingQueries', () async {
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a', map<dynamic>(<dynamic>['k', 'a', 'sort', 1.0]),
      'b', map<dynamic>(<dynamic>['k', 'b', 'sort', 2.0]),
      'c', map<dynamic>(<dynamic>['k', 'c', 'sort', 2.0]),
      'd', map<dynamic>(<dynamic>['k', 'd', 'sort', 3.0]),
      'e', map<dynamic>(<dynamic>['k', 'e', 'sort', 0.0]),
      'f',
      map<dynamic>(<dynamic>['k', 'f', 'nosort', 1.0]) // should not show up
    ]));

    final Query query = testCollection
        .orderBy('sort', Direction.descending)
        .orderByField(FieldPath.documentId(), Direction.descending);

    QuerySnapshot snapshot = await query.startAt(<double>[2.0]).get();

    expect(querySnapshotToValues(snapshot), <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'c', 'sort', 2.0]),
      map<dynamic>(<dynamic>['k', 'b', 'sort', 2.0]),
      map<dynamic>(<dynamic>['k', 'a', 'sort', 1.0]),
      map<dynamic>(<dynamic>['k', 'e', 'sort', 0.0])
    ]);

    snapshot = await query.endBefore(<double>[2.0]).get();
    expect(querySnapshotToValues(snapshot), <Map<String, dynamic>>[
      map<dynamic>(<dynamic>['k', 'd', 'sort', 3.0])
    ]);
  });

  Timestamp timestamp(int seconds, int micros) {
    // Firestore only supports microsecond resolution, so use a microsecond as a
    // minimum value for nanoseconds.
    return Timestamp(seconds, micros * 1000);
  }

  test('timestampsCanBePassedToQueriesAsLimits', () async {
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a', map<Timestamp>(<dynamic>['timestamp', timestamp(100, 2)]),
      'b', map<Timestamp>(<dynamic>['timestamp', timestamp(100, 5)]),
      'c', map<Timestamp>(<dynamic>['timestamp', timestamp(100, 3)]),
      'd', map<Timestamp>(<dynamic>['timestamp', timestamp(100, 1)]),
      // Number of microseconds deliberately repeated.
      'e', map<Timestamp>(<dynamic>['timestamp', timestamp(100, 5)]),
      'f', map<Timestamp>(<dynamic>['timestamp', timestamp(100, 4)])
    ]));

    final Query query = testCollection.orderBy('timestamp');
    final QuerySnapshot snapshot = await query
        .startAfter(<Timestamp>[timestamp(100, 2)]).endAt(
            <Timestamp>[timestamp(100, 5)]).get();
    expect(querySnapshotToIds(snapshot), <String>['c', 'f', 'b', 'e']);
  });

  test('timestampsCanBePassedToQueriesInWhereClause', () async {
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['timestamp', timestamp(100, 7)]),
      'b',
      map<dynamic>(<dynamic>['timestamp', timestamp(100, 4)]),
      'c',
      map<dynamic>(<dynamic>['timestamp', timestamp(100, 8)]),
      'd',
      map<dynamic>(<dynamic>['timestamp', timestamp(100, 5)]),
      'e',
      map<dynamic>(<dynamic>['timestamp', timestamp(100, 6)])
    ]));

    final QuerySnapshot snapshot = await testCollection
        .whereGreaterThanOrEqualTo('timestamp', timestamp(100, 5))
        .whereLessThan('timestamp', timestamp(100, 8))
        .get();
    expect(querySnapshotToIds(snapshot), <String>['d', 'e', 'a']);
  });

  test('timestampsAreTruncatedToMicroseconds', () async {
    final Timestamp nanos = Timestamp(0, 123456789);
    final Timestamp micros = Timestamp(0, 123456000);
    final Timestamp millis = Timestamp(0, 123000000);
    final CollectionReference testCollection =
        await testCollectionWithDocs(map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['timestamp', nanos])
    ]));

    QuerySnapshot snapshot =
        await testCollection.whereEqualTo('timestamp', nanos).get();
    expect(querySnapshotToValues(snapshot), hasLength(1));
    // Because Timestamp should have been truncated to microseconds, the
    // microsecond timestamp should be considered equal to the nanosecond one.
    snapshot = await testCollection.whereEqualTo('timestamp', micros).get();
    expect(querySnapshotToValues(snapshot), hasLength(1));
    // The truncation is just to the microseconds, however, so the millisecond
    // timestamp should be treated as different and thus the query should return
    // no results.
    snapshot = await testCollection.whereEqualTo('timestamp', millis).get();
    expect(querySnapshotToValues(snapshot), isEmpty);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToValues = IntegrationTestUtil.querySnapshotToValues;
// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const newTestSettings = IntegrationTestUtil.newTestSettings;
// ignore: always_specify_types, type_annotate_public_apis
const writeAllDocs = IntegrationTestUtil.writeAllDocs;
// ignore: always_specify_types, type_annotate_public_apis
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;
