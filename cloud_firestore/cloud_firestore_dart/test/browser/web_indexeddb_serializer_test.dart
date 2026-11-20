// The rows of the IndexedDB engine (IndexedDbSerializer) for values that package:protobuf's proto3 JSON does not write
// as the JS SDK does: an empty bytes value, -0.0, and timestamps with nanoseconds (which dart2js rounded to
// milliseconds). Each row goes through JSON, as IndexedDB stores it as a plain object tree, and is read back.
//
//   dart test -p chrome -c dart2js test/browser/web_indexeddb_serializer_test.dart

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../util/test_util.dart';

final IndexedDbSerializer serializer = IndexedDbSerializer(
  LocalSerializer(RemoteSerializer(dbId('projectId'))),
);

/// [document] written as a row, through JSON, and read back.
(Map<String, Object?>, MaybeDocument) roundTrip(MaybeDocument document) {
  final Map<String, Object?> row =
      jsonDecode(
            jsonEncode(
              serializer.toDbRemoteDocument(
                document,
                const SnapshotVersion(Timestamp(1, 0)),
              ),
            ),
          )
          as Map<String, Object?>;
  return (row, serializer.fromDbRemoteDocument(row).document);
}

Map<String, Object?> fieldsOf(Map<String, Object?> row) =>
    (row['document']! as Map<String, Object?>)['fields']!
        as Map<String, Object?>;

void main() {
  test(
    'an empty bytes value is written as an empty base64 string and read back',
    () {
      final (Map<String, Object?> row, MaybeDocument read) = roundTrip(
        doc('coll/a', 1000, <String, Object?>{
          'empty': Blob(Uint8List(0)),
          'some': Blob(Uint8List.fromList(<int>[1, 2, 3])),
        }),
      );
      expect(fieldsOf(row)['empty'], <String, Object?>{'bytesValue': ''});
      expect(fieldsOf(row)['some'], <String, Object?>{'bytesValue': 'AQID'});
      final Document document = read as Document;
      expect(document.getField(field('empty')), isA<BlobValue>());
      expect(
        (document.getField(field('empty'))! as BlobValue).value.bytes,
        isEmpty,
      );
      expect(
        (document.getField(field('some'))! as BlobValue).value.bytes,
        <int>[1, 2, 3],
      );
    },
  );

  test('timestamps keep their nanoseconds, up to the last of year 9999', () {
    const Timestamp nearSecond = Timestamp(946684799, 999999999);
    const Timestamp lastOfYear9999 = Timestamp(253402300799, 999999999);
    const Timestamp micros = Timestamp(1700000000, 123456789);
    final Document original = Document(
      key('coll/a'),
      const SnapshotVersion(lastOfYear9999),
      DocumentState.synced,
      // The values as the backend sends them (the user data converter would truncate to microseconds).
      ObjectValue.fromMap(<String, FieldValue>{
        'near': TimestampValue.valueOf(nearSecond),
        'last': TimestampValue.valueOf(lastOfYear9999),
        'micros': TimestampValue.valueOf(micros),
      }),
    );
    final (Map<String, Object?> row, MaybeDocument read) = roundTrip(original);
    expect(fieldsOf(row)['near'], <String, Object?>{
      'timestampValue': '1999-12-31T23:59:59.999999999Z',
    });
    expect(fieldsOf(row)['last'], <String, Object?>{
      'timestampValue': '9999-12-31T23:59:59.999999999Z',
    });
    expect(
      (row['document']! as Map<String, Object?>)['updateTime'],
      '9999-12-31T23:59:59.999999999Z',
    );
    final Document document = read as Document;
    expect(document.version, const SnapshotVersion(lastOfYear9999));
    expect(
      document.getField(field('near')),
      TimestampValue.valueOf(nearSecond),
    );
    expect(
      document.getField(field('last')),
      TimestampValue.valueOf(lastOfYear9999),
    );
    expect(document.getField(field('micros')), TimestampValue.valueOf(micros));
  });

  test('-0.0 is written as "-0" and read back as -0.0', () {
    final (Map<String, Object?> row, MaybeDocument read) = roundTrip(
      // The values as the backend sends them (on dart2js the user's -0.0 is an int: JS has one number type).
      Document(
        key('coll/a'),
        version(1000),
        DocumentState.synced,
        ObjectValue.fromMap(<String, FieldValue>{
          'negzero': DoubleValue.valueOf(-0.0),
          'point': GeoPointValue.valueOf(const GeoPoint(-0.0, 1.5)),
        }),
      ),
    );
    expect(fieldsOf(row)['negzero'], <String, Object?>{'doubleValue': '-0'});
    expect(fieldsOf(row)['point'], <String, Object?>{
      'geoPointValue': <String, Object?>{'latitude': '-0', 'longitude': 1.5},
    });
    final Document document = read as Document;
    final FieldValue negzero = document.getField(field('negzero'))!;
    expect(negzero, isA<DoubleValue>());
    expect((negzero as DoubleValue).value.isNegative, isTrue);
    expect(
      (document.getField(field('point'))! as GeoPointValue)
          .value
          .latitude
          .isNegative,
      isTrue,
    );
  });

  test('a "-0" the JS SDK wrote is read as -0.0', () {
    final Map<String, Object?> row =
        jsonDecode(
              jsonEncode(
                serializer.toDbRemoteDocument(
                  doc('coll/a', 1000, <String, Object?>{'v': 1.5}),
                  const SnapshotVersion(Timestamp(1, 0)),
                ),
              ),
            )
            as Map<String, Object?>;
    fieldsOf(row)['v'] = <String, Object?>{'doubleValue': '-0'};
    final Document document =
        serializer.fromDbRemoteDocument(row).document as Document;
    final FieldValue value = document.getField(field('v'))!;
    expect(value, isA<DoubleValue>());
    expect((value as DoubleValue).value.isNegative, isTrue);
  });

  test('the key of a stored document is unchanged', () {
    expect(
      serializer
          .fromDbRemoteDocument(
            roundTrip(doc('coll/a', 1000, <String, Object?>{'v': 1})).$1,
          )
          .document
          .key,
      DocumentKey.fromPathString('coll/a'),
    );
  });
}
