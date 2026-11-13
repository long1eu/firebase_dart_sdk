// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
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
    Map<String, Object?> data,
    DocumentReference documentReference,
  ) async {
    await documentReference.set(data);
    final DocumentSnapshot doc = await documentReference.get();
    expect(doc.data, data);
  }

  Future<DocumentReference> testDoc() async {
    return (await testCollection()).document();
  }

  test('testCanReadAndWriteNullFields', () async {
    await verifySuccessfulWriteReadCycle(
      map(<dynamic>['a', 1.0, 'b', null]),
      await testDoc(),
    );
  });

  // JS type.test.ts
  test('can read and write number fields', () async {
    await verifySuccessfulWriteReadCycle(<String, Object?>{
      'a': 1,
      'c': double.infinity,
      'd': 0.0,
    }, await testDoc());
    // NaN != NaN, so it is checked on its own.
    final DocumentReference doc = await testDoc();
    await doc.set(<String, Object?>{'b': double.nan});
    expect((await doc.get()).getDouble('b')!.isNaN, isTrue);
  });

  test('testCanReadAndWriteListFields', () async {
    await verifySuccessfulWriteReadCycle(
      map<dynamic>(<dynamic>[
        'array',
        <dynamic>[
          1.0,
          'foo',
          map<dynamic>(<dynamic>['deep', true]),
          null,
        ],
      ]),
      await testDoc(),
    );
  });

  test('testCanReadAndWriteBlobFields', () async {
    await verifySuccessfulWriteReadCycle(
      map(<dynamic>[
        'blob',
        blob(<int>[1, 2, 3]),
      ]),
      await testDoc(),
    );
  });

  test('testCanReadAndWriteGeoPointFields', () async {
    await verifySuccessfulWriteReadCycle(
      map(<dynamic>[
        'geoPoint',
        //ignore: prefer_const_constructors
        GeoPoint(1.23, 4.56),
      ]),
      await testDoc(),
    );
  });

  test('testCanReadAndWriteTimestamps', () async {
    const Timestamp timestamp = Timestamp(100, 123000000);
    await verifySuccessfulWriteReadCycle(
      map(<dynamic>['timestamp', timestamp]),
      await testDoc(),
    );
  });

  test('testCanReadAndWriteDates', () async {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(1491847082123);
    // Tests are set up to read back Timestamps, not Dates.
    await verifySuccessfulWriteReadCycle(
      map(<dynamic>['date', Timestamp.fromDate(date)]),
      await testDoc(),
    );
  });

  test('testCanUseTypedAccessors', () async {
    final DocumentReference doc = await testDoc();
    final Map<String, Object?> data = map(<dynamic>[
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
      const Timestamp(100, 123000000),
      'reference',
      doc,
    ]);

    await doc.set(data);
    final DocumentSnapshot snapshot = await doc.get();
    expect(snapshot['null'], data['null']);
    expect(
      snapshot.getField(FieldPath.fromDotSeparatedPath('null')),
      data['null'],
    );
    expect(snapshot.getBool('boolean'), data['boolean']);
    expect(snapshot.getString('string'), data['string']);
    expect(snapshot.getDouble('double'), data['double']);
    expect(snapshot.getDouble('int'), 1.0);
    expect(snapshot.getGeoPoint('geoPoint'), data['geoPoint']);
    expect(snapshot.getBlob('blob'), data['blob']);
    expect(
      snapshot.getDate('date')!.millisecondsSinceEpoch,
      (data['date'] as DateTime).millisecondsSinceEpoch,
    );
    expect(
      snapshot.getTimestamp('date'),
      Timestamp.fromDate(data['date'] as DateTime),
    );
    expect(snapshot.getTimestamp('timestamp'), data['timestamp']);
    final Timestamp timestamp = data['timestamp']! as Timestamp;
    expect(snapshot.getDate('timestamp'), timestamp.toDate());
    expect(data['reference'], const TypeMatcher<DocumentReference>());
    expect(doc.path, (data['reference'] as DocumentReference).path);
  });

  test('testTypeAccessorsCanReturnNull', () async {
    final DocumentReference doc = await testDoc();
    final Map<String, Object?> data = map();

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
    final Map<String, Object?> data = map(<dynamic>['a', 42, 'ref', docRef]);
    await verifySuccessfulWriteReadCycle(data, docRef);
  });

  test('testCanReadAndWriteDocumentReferencesInLists', () async {
    final DocumentReference docRef = await testDoc();
    final List<Object> refs = <Object>[docRef];
    final Map<String, Object?> data = map(<dynamic>['a', 42, 'refs', refs]);
    await verifySuccessfulWriteReadCycle(data, docRef);
  });

  // The BSON types of the upstream test (MinKey, Int32, Decimal128, BsonTimestamp, BsonBinary, BsonObjectId, regex,
  // MaxKey) are not ported: this covers the others.
  test('snapshotListenerSortsDifferentTypesSameAsServer', () async {
    final CollectionReference colRef = await testCollection();
    // The reference is created first to make sure it uses the same Firestore instance.
    final DocumentReference docRef = colRef.document('testDocRef');

    final Map<String, Map<String, Object?>> testDocs =
        <String, Map<String, Object?>>{
          'null': <String, Object?>{'value': null},
          'boolean': <String, Object?>{'value': true},
          'nan': <String, Object?>{'value': double.nan},
          'double': <String, Object?>{'value': 1.0},
          'int': <String, Object?>{'value': 1},
          'timestamp': <String, Object?>{
            'value': const Timestamp(100, 123000000),
          },
          'string': <String, Object?>{'value': 'a'},
          'bytes': <String, Object?>{
            'value': Blob(Uint8List.fromList(<int>[1, 2, 3])),
          },
          'reference': <String, Object?>{'value': docRef},
          'geoPoint': <String, Object?>{'value': GeoPoint(1.23, 4.56)},
          'array': <String, Object?>{
            'value': <Object?>[
              1.0,
              'foo',
              <String, Object?>{'key': true},
              null,
            ],
          },
          'vector': <String, Object?>{
            'value': FieldValue.vector(<double>[1, 2, 3]),
          },
          'map': <String, Object?>{
            'value': <String, Object?>{'key': true},
          },
        };
    await IntegrationTestUtil.writeAllDocs(colRef, testDocs);

    // The SDK sorts a listener the same way the backend sorts Query.get().
    await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
      colRef,
      colRef.orderBy('value'),
      testDocs,
      <String>[
        'null',
        'boolean',
        'nan',
        'double',
        'int',
        'timestamp',
        'string',
        'bytes',
        'reference',
        'geoPoint',
        'array',
        'vector',
        'map',
      ],
    );
  });
}

// ignore: always_specify_types, type_annotate_public_apis
const testFirestore = IntegrationTestUtil.testFirestore;
// ignore: always_specify_types, type_annotate_public_apis
const testCollection = IntegrationTestUtil.testCollection;
