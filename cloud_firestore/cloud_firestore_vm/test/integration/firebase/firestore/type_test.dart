// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';
import '../../../util/test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/type_test';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<void> verifySuccessfulWriteReadCycle(
      Map<String, Object> data, DocumentReference documentReference) async {
    await documentReference.set(data);
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, data);
  }

  Future<DocumentReference> testDoc() async {
    return (await testCollection()).document();
  }

  test('testCanReadAndWriteNullFields', () async {
    await verifySuccessfulWriteReadCycle(
        map(<dynamic>['a', 1.0, 'b', null]), await testDoc());
  });

  test('testCanReadAndWriteListFields', () async {
    await verifySuccessfulWriteReadCycle(
        map<dynamic>(<dynamic>[
          'array',
          <dynamic>[
            1.0,
            'foo',
            map<dynamic>(<dynamic>['deep', true]),
            null
          ]
        ]),
        await testDoc());
  });

  test('testCanReadAndWriteBlobFields', () async {
    await verifySuccessfulWriteReadCycle(
        map(<dynamic>[
          'blob',
          blob(<int>[1, 2, 3])
        ]),
        await testDoc());
  });

  test('testCanReadAndWriteGeoPointFields', () async {
    await verifySuccessfulWriteReadCycle(
        map(<dynamic>[
          'geoPoint',
          //ignore: prefer_const_constructors
          GeoPoint(1.23, 4.56)
        ]),
        await testDoc());
  });

  test('testCanReadAndWriteTimestamps', () async {
    final Timestamp timestamp = Timestamp(100, 123000000);
    await verifySuccessfulWriteReadCycle(
        map(<dynamic>['timestamp', timestamp]), await testDoc());
  });

  test('testCanReadAndWriteDates', () async {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(1491847082123);
    // Tests are set up to read back Timestamps, not Dates.
    await verifySuccessfulWriteReadCycle(
        map(<dynamic>['date', Timestamp.fromDate(date)]), await testDoc());
  });

  test('testCanUseTypedAccessors', () async {
    final DocumentReference doc = await testDoc();
    final Map<String, Object> data = map(<dynamic>[
      'null',
      null,
      'boolean',
      true,
      'string',
      'string',
      'double',
      0.0,
      'int',
      1,
      'geoPoint',
      //ignore: prefer_const_constructors
      GeoPoint(1.24, 4.56),
      'blob',
      blob(<int>[0, 1, 2]),
      'date',
      DateTime.now(),
      'timestamp',
      Timestamp(100, 123000000),
      'reference',
      doc
    ]);

    await doc.set(data);
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot['null'], data['null']);
    expect(snapshot.getField(FieldPath.fromDotSeparatedPath('null')),
        data['null']);
    expect(snapshot.getBool('boolean'), data['boolean']);
    expect(snapshot.getString('string'), data['string']);
    expect(snapshot.getDouble('double'), data['double']);
    expect(snapshot.getDouble('int'), 1.0);
    expect(snapshot.getGeoPoint('geoPoint'), data['geoPoint']);
    expect(snapshot.getBlob('blob'), data['blob']);
    expect(snapshot.getDate('date').millisecondsSinceEpoch,
        (data['date'] as DateTime).millisecondsSinceEpoch);
    expect(snapshot.getTimestamp('date'),
        Timestamp.fromDate(data['date'] as DateTime));
    expect(snapshot.getTimestamp('timestamp'), data['timestamp']);
    final Timestamp timestamp = data['timestamp'];
    expect(snapshot.getDate('timestamp'), timestamp.toDate());
    expect(data['reference'], const TypeMatcher<DocumentReference>());
    expect(doc.path, (data['reference'] as DocumentReference).path);
  });

  test('testTypeAccessorsCanReturnNull', () async {
    final DocumentReference doc = await testDoc();
    final Map<String, Object> data = map();

    await doc.set(data);
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot['missing'], isNull);
    expect(snapshot.getBool('missing'), isNull);
    expect(snapshot.getString('missing'), isNull);
    expect(snapshot.getDouble('missing'), isNull);
    expect(snapshot.getDouble('missing'), isNull);
    expect(snapshot.getGeoPoint('missing'), isNull);
    expect(snapshot.getBlob('missing'), isNull);
    expect(snapshot.getDate('missing'), isNull);
    expect(snapshot.getTimestamp('missing'), isNull);
    expect(snapshot.getDocumentReference('missing'), isNull);
  });

  test('testCanReadAndWriteDocumentReferences', () async {
    final DocumentReference docRef = await testDoc();
    final Map<String, Object> data = map(<dynamic>['a', 42, 'ref', docRef]);
    await verifySuccessfulWriteReadCycle(data, docRef);
  });

  test('testCanReadAndWriteDocumentReferencesInLists', () async {
    final DocumentReference docRef = await testDoc();
    final List<Object> refs = <Object>[docRef];
    final Map<String, Object> data = map(<dynamic>['a', 42, 'refs', refs]);
    await verifySuccessfulWriteReadCycle(data, docRef);
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
