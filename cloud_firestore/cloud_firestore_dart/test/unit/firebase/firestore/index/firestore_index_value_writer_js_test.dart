import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/index/firestore_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_entry.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as pv1;
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

/// Port of firestore_index_value_writer.test.ts of the JS SDK.
///
/// The JS cases build most values twice: as the map the backend sends (`{__oid__: ...}`) and through the user data
/// reader. Here the first form is a proto `Value` decoded by the [RemoteSerializer], the second a [wrap]ped user value.
///
/// Not ported: "can handle different format of timestamp", "can handle timestamps with 0 nanoseconds" and "can compare
/// timestamps with different formats" compare the proto3 JSON string forms of a timestamp (`'2016-01-02T10:20:50Z'`),
/// which the port never sees: its `Timestamp` proto always has seconds and nanos.
void main() {
  final RemoteSerializer serializer = RemoteSerializer(
    DatabaseId.forProject('project'),
  );

  int compareIndexEncodedValues(
    FieldValue value1,
    FieldValue value2,
    SegmentKind direction,
  ) {
    final IndexByteEncoder encoder1 = IndexByteEncoder();
    final IndexByteEncoder encoder2 = IndexByteEncoder();
    FirestoreIndexValueWriter.instance.writeIndexValue(
      value1,
      encoder1.forKind(direction),
    );
    FirestoreIndexValueWriter.instance.writeIndexValue(
      value2,
      encoder2.forKind(direction),
    );
    return compareByteArrays(encoder1.encodedBytes, encoder2.encodedBytes).sign;
  }

  const SegmentKind asc = SegmentKind.ascending;
  const SegmentKind desc = SegmentKind.descending;

  pv1.Value protoMap(Map<String, pv1.Value> fields) =>
      pv1.Value()..mapValue = (pv1.MapValue()..fields.addAll(fields));
  pv1.Value protoString(String value) => pv1.Value()..stringValue = value;
  pv1.Value protoInt(int value) => pv1.Value()..integerValue = Int64(value);
  pv1.Value protoBytes(List<int> value) => pv1.Value()..bytesValue = value;
  pv1.Value protoNull() => pv1.Value()..nullValue = proto.NullValue.NULL_VALUE;
  FieldValue decode(pv1.Value value) => serializer.decodeValue(value);

  test('reproduces year 2286 timestamp string comparison bug', () {
    // 10-digit seconds timestamp (e.g. Year 2026)
    final FieldValue value1 = wrap(Timestamp(1770000000, 0));
    // 11-digit seconds timestamp (e.g. Year 2286)
    final FieldValue value2 = wrap(Timestamp(10000000000, 0));
    // DEVIATION from JS, which writes the seconds as a string ("10000000000" < "1770000000") and expects 1 here, a
    // bug its test pins. The port writes them as a number, as Android does, so the index order is the value order.
    expect(value1.compareTo(value2).sign, -1);
    expect(compareIndexEncodedValues(value1, value2, asc), -1);
    expect(compareIndexEncodedValues(value1, value2, desc), 1);
  });

  test(
    'sorts vector as a different type from array and map, with unique rules',
    () {
      final FieldValue vector1 = wrap(VectorValue(<double>[100]));
      final FieldValue vector2 = wrap(VectorValue(<double>[1, 2]));
      final FieldValue vector3 = wrap(VectorValue(<double>[1, 3]));
      final FieldValue map1 = wrap(<String, Object?>{
        'value': <Object?>[1.0, 2.0],
      });
      final FieldValue array1 = wrap(<Object?>[1.0, 2.0]);

      // Array sorts before vector
      expect(compareIndexEncodedValues(array1, vector1, asc), -1);
      expect(compareIndexEncodedValues(array1, vector1, desc), 1);
      // Vector sorts before map
      expect(compareIndexEncodedValues(vector3, map1, asc), -1);
      expect(compareIndexEncodedValues(vector3, map1, desc), 1);
      // Shorter vectors sort before longer vectors
      expect(compareIndexEncodedValues(vector1, vector2, asc), -1);
      expect(compareIndexEncodedValues(vector1, vector2, desc), 1);
      // Vectors of the same length sort by value
      expect(compareIndexEncodedValues(vector2, vector3, asc), -1);
      expect(compareIndexEncodedValues(vector2, vector3, desc), 1);
    },
  );

  group('can gracefully handle BSON types', () {
    test('can compare BSON ObjectIds', () {
      final FieldValue value1 = decode(
        protoMap(<String, pv1.Value>{
          '__oid__': protoString('507f191e810c19729de860ea'),
        }),
      );
      final FieldValue value2 = decode(
        protoMap(<String, pv1.Value>{
          '__oid__': protoString('507f191e810c19729de860eb'),
        }),
      );
      final FieldValue value3 = wrap(
        const BsonObjectId('507f191e810c19729de860ea'),
      );
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value3, value1, asc), 0);
    });

    pv1.Value bsonTimestamp(
      int seconds,
      int increment, {
      bool incrementFirst = false,
    }) => protoMap(<String, pv1.Value>{
      '__request_timestamp__': protoMap(
        incrementFirst
            ? <String, pv1.Value>{
                'increment': protoInt(increment),
                'seconds': protoInt(seconds),
              }
            : <String, pv1.Value>{
                'seconds': protoInt(seconds),
                'increment': protoInt(increment),
              },
      ),
    });

    test('can compare BSON Timestamps', () {
      final FieldValue value1 = decode(bsonTimestamp(1, 2));
      final FieldValue value2 = decode(bsonTimestamp(1, 3));
      final FieldValue value3 = wrap(BsonTimestamp(1, 2));
      final FieldValue value4 = wrap(BsonTimestamp(2, 1));
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value4, value1, asc), 1);
      expect(compareIndexEncodedValues(value4, value2, asc), 1);
      expect(compareIndexEncodedValues(value4, value3, asc), 1);
    });

    test(
      'reproduces BSON Timestamp index key instability based on field insertion order',
      () {
        final FieldValue valueA = decode(bsonTimestamp(1, 2));
        final FieldValue valueB = decode(
          bsonTimestamp(1, 2, incrementFirst: true),
        );
        // DEVIATION from JS, which writes the inner map in insertion order and pins (`not.toBe(0)`) that the two
        // encodings differ. The port decodes both into the same BsonTimestamp, as Android does, so they are equal.
        expect(valueA.compareTo(valueB), 0);
        expect(compareIndexEncodedValues(valueA, valueB, asc), 0);
      },
    );

    test('can compare BSON Binary', () {
      final FieldValue value1 = decode(
        protoMap(<String, pv1.Value>{
          '__binary__': protoBytes(<int>[1, 1, 2, 3]),
        }),
      );
      final FieldValue value2 = decode(
        protoMap(<String, pv1.Value>{
          '__binary__': protoBytes(<int>[1, 1, 2, 4]),
        }),
      );
      final FieldValue value3 = wrap(
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      );
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value3, value1, asc), 0);
    });

    test('can compare standard blobs vs. subtyped blobs in indexes', () {
      final FieldValue stdBytes123 = wrap(
        Blob.bsonBinary(0, Uint8List.fromList(<int>[1, 2, 3])),
      );
      final FieldValue stdBytes255 = wrap(
        Blob.bsonBinary(0, Uint8List.fromList(<int>[255])),
      );
      final FieldValue sub1Bytes123 = wrap(
        Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3])),
      );
      final FieldValue sub1Bytes0 = wrap(
        Blob.bsonBinary(1, Uint8List.fromList(<int>[0])),
      );
      final FieldValue sub2Bytes1 = wrap(
        Blob.bsonBinary(2, Uint8List.fromList(<int>[1])),
      );
      // Subtype 0 (standard) < Subtype 1 (subtyped) with identical payload
      expect(compareIndexEncodedValues(stdBytes123, sub1Bytes123, asc), -1);
      expect(compareIndexEncodedValues(sub1Bytes123, stdBytes123, asc), 1);
      // Subtype 0 (standard) < Subtype 1 (subtyped), even with greater payload byte values ([255] < [0])
      expect(compareIndexEncodedValues(stdBytes255, sub1Bytes0, asc), -1);
      expect(compareIndexEncodedValues(sub1Bytes0, stdBytes255, asc), 1);
      // Subtype 1 < Subtype 2
      expect(compareIndexEncodedValues(sub1Bytes123, sub2Bytes1, asc), -1);
      expect(compareIndexEncodedValues(sub2Bytes1, sub1Bytes123, asc), 1);
      // Equalities
      expect(compareIndexEncodedValues(stdBytes123, stdBytes123, asc), 0);
      expect(compareIndexEncodedValues(sub1Bytes123, sub1Bytes123, asc), 0);
    });

    test(
      'asserts standard blobs and BSON binary subtype 0 are encoded identically',
      () {
        final FieldValue rawBytes = decode(protoBytes(<int>[1, 2, 3]));
        final FieldValue bsonBinarySubtype0 = decode(
          protoMap(<String, pv1.Value>{
            '__binary__': protoBytes(<int>[0, 1, 2, 3]),
          }),
        );
        // DEVIATION from JS, which reads `{__binary__: <0, ...>}` as BSON binary data of subtype 0 and expects both
        // comparisons to be 0. The port follows Android (`Values.isBsonBinaryData` requires a subtype other than 0):
        // that map is a plain map, which sorts after every blob, in memory and in the index alike. The backend never
        // sends it (a blob of subtype 0 is a `bytesValue`). A regular blob and `Blob.bsonBinary(0, ...)` are the
        // same value with the same encoding (writeIndexValueSupportsBsonBinarySubtype0).
        expect(bsonBinarySubtype0, isA<ObjectValue>());
        expect(rawBytes.compareTo(bsonBinarySubtype0), -1);
        expect(
          compareIndexEncodedValues(rawBytes, bsonBinarySubtype0, asc),
          -1,
        );
        expect(
          compareIndexEncodedValues(
            rawBytes,
            wrap(Blob.bsonBinary(0, Uint8List.fromList(<int>[1, 2, 3]))),
            asc,
          ),
          0,
        );
      },
    );

    pv1.Value regex(String pattern, String options) =>
        protoMap(<String, pv1.Value>{
          '__regex__': protoMap(<String, pv1.Value>{
            'pattern': protoString(pattern),
            'options': protoString(options),
          }),
        });

    test('can compare BSON Regex', () {
      final FieldValue value1 = decode(regex('^foo', 'i'));
      final FieldValue value2 = decode(regex('^foo', 'm'));
      final FieldValue value3 = wrap(const RegexValue('^foo', 'i'));
      final FieldValue value4 = wrap(const RegexValue('^zoo', 'i'));
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value3, value1, asc), 0);
      expect(compareIndexEncodedValues(value4, value1, asc), 1);
      expect(compareIndexEncodedValues(value4, value2, asc), 1);
      expect(compareIndexEncodedValues(value4, value3, asc), 1);
    });

    test('can compare BSON Int32', () {
      final FieldValue value1 = decode(
        protoMap(<String, pv1.Value>{'__int__': protoInt(1)}),
      );
      final FieldValue value2 = decode(
        protoMap(<String, pv1.Value>{'__int__': protoInt(2)}),
      );
      final FieldValue value3 = wrap(Int32Value(1));
      final FieldValue value4 = wrap(Int32Value(2));
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value3, value1, asc), 0);
      expect(compareIndexEncodedValues(value4, value1, asc), 1);
      expect(compareIndexEncodedValues(value4, value2, asc), 0);
      expect(compareIndexEncodedValues(value4, value3, asc), 1);
    });

    pv1.Value decimal(String value) =>
        protoMap(<String, pv1.Value>{'__decimal128__': protoString(value)});

    test('can compare BSON Decimal128', () {
      final FieldValue value1 = decode(decimal('-1.2e3'));
      final FieldValue value2 = decode(decimal('1.2e3'));
      final FieldValue value3 = wrap(Decimal128Value('-1.2e3'));
      final FieldValue value4 = wrap(Decimal128Value('1.2e3'));
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
      expect(compareIndexEncodedValues(value3, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value3, value1, asc), 0);
      expect(compareIndexEncodedValues(value4, value1, asc), 1);
      expect(compareIndexEncodedValues(value4, value2, asc), 0);
      expect(compareIndexEncodedValues(value4, value3, asc), 1);
    });

    test('can compare BSON Decimal128 special cases', () {
      final FieldValue value1 = decode(decimal('NaN'));
      final FieldValue value2 = decode(decimal('-Infinity'));
      final FieldValue value3 = wrap(Decimal128Value('NaN'));
      final FieldValue value4 = wrap(Decimal128Value('Infinity'));
      // order should be: NaNs are equal, and less than -Infinity
      expect(compareIndexEncodedValues(value1, value2, asc), -1);
      expect(compareIndexEncodedValues(value2, value1, asc), 1);
      expect(compareIndexEncodedValues(value1, value3, asc), 0);
      expect(compareIndexEncodedValues(value1, value4, asc), -1);
      expect(compareIndexEncodedValues(value2, value2, asc), 0);
      expect(compareIndexEncodedValues(value2, value3, asc), 1);
      expect(compareIndexEncodedValues(value2, value4, asc), -1);
      expect(compareIndexEncodedValues(value3, value4, asc), -1);
      expect(compareIndexEncodedValues(value4, value3, asc), 1);
      expect(compareIndexEncodedValues(value4, value4, asc), 0);
    });

    test('can compare BSON MinKey', () {
      final FieldValue value1 = decode(
        protoMap(<String, pv1.Value>{'__min__': protoNull()}),
      );
      final FieldValue value2 = decode(
        protoMap(<String, pv1.Value>{'__min__': protoNull()}),
      );
      final FieldValue value3 = wrap(MinKey.instance);
      expect(compareIndexEncodedValues(value1, value2, asc), 0);
      expect(compareIndexEncodedValues(value1, value3, desc), 0);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
    });

    test('can compare BSON MaxKey', () {
      final FieldValue value1 = decode(
        protoMap(<String, pv1.Value>{'__max__': protoNull()}),
      );
      final FieldValue value2 = decode(
        protoMap(<String, pv1.Value>{'__max__': protoNull()}),
      );
      final FieldValue value3 = wrap(MaxKey.instance);
      expect(compareIndexEncodedValues(value1, value2, asc), 0);
      expect(compareIndexEncodedValues(value1, value3, desc), 0);
      expect(compareIndexEncodedValues(value1, value1, asc), 0);
    });
  });
}
