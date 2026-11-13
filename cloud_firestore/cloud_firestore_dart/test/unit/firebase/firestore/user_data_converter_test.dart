// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

import 'dart:collection';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/max_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/min_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:cloud_firestore_dart/src/proto/google/firestore/v1/index.dart'
    as proto;
import 'package:test/test.dart';

import '../../../util/test_access_helper.dart';
import '../../../util/test_util.dart';

const int _int32Min = -2147483648;
const int _int32Max = 2147483647;

/// Java's Float.MAX_VALUE, Float.MIN_VALUE and Float.MIN_NORMAL.
final double _floatMax = _float(3.4028234663852886e38);
final double _floatMinPositive = _float(1.401298464324817e-45);
final double _floatMinNormal = _float(1.1754943508222875e-38);

/// Rounds [value] to the nearest 32-bit float, as a Java float literal does.
double _float(double value) => (Float32List(1)..[0] = value)[0];

void main() {
  ObjectValue fromMap(List<Object> entries) {
    final Map<String, FieldValue> res = <String, FieldValue>{};
    for (int i = 0; i < entries.length; i += 2) {
      res[entries[i] as String] = entries[i + 1] as FieldValue;
    }
    return ObjectValue.fromMap(res);
  }

  test('testConvertsNullValue', () {
    final FieldValue value = wrap(null);
    expect(value, NullValue.nullValue());
    expect(value.value, isNull);
  });

  test('testConvertsBooleanValue', () {
    final List<bool> testCases = <bool>[true, false];
    for (bool b in testCases) {
      final FieldValue value = wrap(b);

      expect(value, isA<BoolValue>());
      expect(value.value, b);
    }
  });

  test('testConvertsIntegerValue', () {
    final List<int> testCases = <int>[_int32Min, -1, 0, 1, _int32Max];
    for (int i in testCases) {
      final FieldValue value = wrap(i);

      expect(value, isA<IntegerValue>());
      expect(value.value, i);
    }
  });

  test('testConvertsLongValue', () {
    final List<int> testCases = <int>[
      IntegerValue.min,
      _int32Min,
      -1,
      0,
      1,
      _int32Max,
      IntegerValue.max,
    ];
    for (int l in testCases) {
      final FieldValue value = wrap(l);

      expect(value, isA<IntegerValue>());
      expect(value.value, l);
    }
  });

  // Dart has no 32-bit float type: the cases are Java's float constants
  // widened to double, which is what Android stores.
  test('testConvertsFloatValue', () {
    final List<double> testCases = <double>[
      -_floatMax,
      IntegerValue.min * 1.0,
      _float(-1.1),
      -_floatMinPositive,
      -0.0,
      0.0,
      _floatMinPositive,
      _floatMinNormal,
      IntegerValue.max * 1.0,
      _floatMax,
    ];
    for (double f in testCases) {
      final FieldValue value = wrap(f);

      expect(value, isA<DoubleValue>());
      expect(value.value, f);
      expect((value.value! as double).isNegative, f.isNegative);
    }
  });

  test('testConvertsDoubleValue', () {
    final List<double> testCases = <double>[
      double.infinity,
      -double.maxFinite,
      IntegerValue.min * 1.0,
      -1.1,
      -double.minPositive,
      -0.0,
      0.0,
      double.minPositive,
      2.2250738585072014E-308,
      IntegerValue.max * 1.0,
      double.maxFinite,
      double.infinity,
      double.nan,
    ];
    for (double d in testCases) {
      final FieldValue value = wrap(d);

      expect(value, isA<DoubleValue>());

      if (d.isNaN) {
        expect(value.value, isNaN);
      } else {
        expect(value.value, d);
      }
    }
  });

  test('testConvertsDateValue', () {
    final List<DateTime> testCases = <DateTime>[
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime.fromMillisecondsSinceEpoch(1356048000000),
    ];

    for (DateTime d in testCases) {
      final FieldValue value = wrap(d);
      final Timestamp timestamp = value.value! as Timestamp;

      expect(value, isA<TimestampValue>());
      expect(timestamp.toDate(), d);
    }
  });

  test('testConvertsTimestampValue', () {
    const List<Timestamp> testCases = <Timestamp>[
      Timestamp(0, 0),
      Timestamp(1356048000, 0),
    ];

    for (Timestamp d in testCases) {
      final FieldValue value = wrap(d);

      expect(value, isA<TimestampValue>());
      expect(value.value, isA<Timestamp>());
      expect(value.value, d);
    }
  });

  test('testConvertsStringValue', () {
    final List<String> testCases = <String>['', 'foo'];
    for (String s in testCases) {
      final FieldValue value = wrap(s);

      expect(value, isA<StringValue>());
      expect(value.value, s);
    }
  });

  test('testConvertsBlobValue', () {
    final List<Blob> testCases = <Blob>[
      blob(<int>[1, 2, 3]),
      blob(<int>[1, 2]),
    ];
    for (Blob b in testCases) {
      final FieldValue value = wrap(b);

      expect(value, isA<BlobValue>());
      expect(value.value, b);
    }
  });

  test('testConvertsResourceName', () {
    final DatabaseId id = DatabaseId.forProject('project');
    final List<DocumentReference> testCases = <DocumentReference>[
      ref('foo/bar'),
      ref('foo/baz'),
    ];
    for (DocumentReference docRef in testCases) {
      final FieldValue value = wrap(docRef);
      final ReferenceValue ref = value as ReferenceValue;

      expect(value, isA<ReferenceValue>());
      expect(ref.value, TestAccessHelper.referenceKey(docRef));
      expect(ref.databaseId, id);
    }
  });

  test('testConvertsGeoPointValue', () {
    const List<GeoPoint> testCases = <GeoPoint>[
      GeoPoint(1.24, 4.56),
      GeoPoint(-20, 100),
    ];
    for (GeoPoint p in testCases) {
      final FieldValue value = wrap(p);

      expect(value, isA<GeoPointValue>());
      expect(value.value, p);
    }
  });

  test('testConvertsBsonObjectIdValue', () {
    final List<BsonObjectId> testCases = <BsonObjectId>[
      const BsonObjectId('foo'),
      const BsonObjectId('bar'),
    ];
    for (BsonObjectId p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsBsonTimestampValue', () {
    final List<BsonTimestamp> testCases = <BsonTimestamp>[
      BsonTimestamp(1, 2),
      BsonTimestamp(3, 4),
    ];
    for (BsonTimestamp p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsBsonBinaryValue', () {
    final List<Blob> testCases = <Blob>[
      Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2])),
      Blob.bsonBinary(127, Uint8List(0)),
      Blob.bsonBinary(128, Uint8List.fromList(<int>[1, 2, 3])),
      Blob.bsonBinary(255, Uint8List.fromList(<int>[255, 254])),
    ];
    for (Blob p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertInvalidBsonBinaryMapAsRegularMap', () {
    final RemoteSerializer serializer = RemoteSerializer(
      DatabaseId.forProject('project'),
    );
    proto.Value binaryMap(List<int> bytes) {
      final proto.MapValue map = proto.MapValue.create();
      map.fields[BsonKeys.binary] = proto.Value.create()..bytesValue = bytes;
      return proto.Value.create()..mapValue = map;
    }

    final Object? emptyBinaryMap = serializer
        .decodeValue(binaryMap(<int>[]))
        .value;
    expect(emptyBinaryMap, <String, Object?>{BsonKeys.binary: blob()});

    final Object? subtypeZeroBinaryMap = serializer
        .decodeValue(binaryMap(<int>[0x00, 0x01]))
        .value;
    expect(subtypeZeroBinaryMap, <String, Object?>{
      BsonKeys.binary: blob(<int>[0x00, 0x01]),
    });

    final Object? validEmptyPayloadSubtypeOne = serializer
        .decodeValue(binaryMap(<int>[0x01]))
        .value;
    expect(validEmptyPayloadSubtypeOne, Blob.bsonBinary(1, Uint8List(0)));
  });

  test('testConvertsRegexValue', () {
    const List<RegexValue> testCases = <RegexValue>[
      RegexValue('^foo', 'i'),
      RegexValue('^bar', 'g'),
    ];
    for (RegexValue p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsInt32Value', () {
    final List<Int32Value> testCases = <Int32Value>[
      Int32Value(1),
      Int32Value(-1),
      Int32Value(0),
      Int32Value(123),
    ];
    for (Int32Value p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsDecimal128Value', () {
    final List<Decimal128Value> testCases = <Decimal128Value>[
      Decimal128Value('-1.2e3'),
      Decimal128Value('1.2e3'),
      Decimal128Value('1.3e3'),
      Decimal128Value('NaN'),
      Decimal128Value('-Infinity'),
      Decimal128Value('Infinity'),
      Decimal128Value('4.2e+3'),
      Decimal128Value('-4.2e-3'),
      Decimal128Value('-0'),
    ];
    for (Decimal128Value p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsMinKey', () {
    final List<MinKey> testCases = <MinKey>[MinKey.instance, MinKey.instance];
    for (MinKey p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsMaxKey', () {
    final List<MaxKey> testCases = <MaxKey>[MaxKey.instance, MaxKey.instance];
    for (MaxKey p in testCases) {
      final FieldValue value = wrap(p);

      expect(value.value, p);
    }
  });

  test('testConvertsEmptyObjects', () {
    expect(wrap(SplayTreeMap<String, FieldValue>()), ObjectValue.empty);
  });

  test('testConvertsSimpleObjects', () {
    // Guava doesn't like null values, so we create a copy of the Immutable map
    // without the null value and then add the null value later.
    final Map<String, Object?> actual = map(<dynamic>[
      'a',
      'foo',
      'b',
      1,
      'c',
      true,
      'd',
      null,
    ]);

    final Map<String, FieldValue> expected = map(<dynamic>[
      'a',
      StringValue.valueOf('foo'),
      'b',
      IntegerValue.valueOf(1),
      'c',
      BoolValue.valueOf(true),
      'd',
      NullValue.nullValue(),
    ]);

    final FieldValue wrappedActual = wrapMap(actual);
    final ObjectValue wrappedExpected = ObjectValue.fromMap(expected);

    expect(wrappedExpected, wrappedActual);
  });

  test('testConvertsNestedObjects', () {
    final FieldValue actual = wrapList(<Object>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        map<dynamic>(<dynamic>['c', 'foo']),
        'd',
        true,
      ]),
    ]);

    final ObjectValue expected = fromMap(<Object>[
      'a',
      fromMap(<Object>[
        'b',
        fromMap(<Object>['c', StringValue.valueOf('foo')]),
        'd',
        BoolValue.valueOf(true),
      ]),
    ]);

    expect(actual, expected);
  });

  test('testConvertsLists', () {
    final ArrayValue expected = ArrayValue.fromList(<FieldValue>[
      StringValue.valueOf('value'),
      BoolValue.valueOf(true),
    ]);
    final FieldValue actual = wrap(<dynamic>['value', true]);

    expect(actual, expected);
  });
  test('testRejectsNestedArraysInQueryValues', () {
    final UserDataConverter converter = UserDataConverter(
      DatabaseId.forProject('project'),
    );
    expect(
      () => converter.parseQueryValue(<Object>[
        <int>[1, 2],
      ]),
      throwsArgumentError,
    );
  });

  test('testAllowsArraysInsideInQueryValues', () {
    final UserDataConverter converter = UserDataConverter(
      DatabaseId.forProject('project'),
    );
    final FieldValue actual = converter.parseQueryValue(<Object>[
      1,
      <int>[1, 2],
    ], allowArrays: true);
    expect(
      actual,
      ArrayValue.fromList(<FieldValue>[
        IntegerValue.valueOf(1),
        ArrayValue.fromList(<FieldValue>[
          IntegerValue.valueOf(1),
          IntegerValue.valueOf(2),
        ]),
      ]),
    );
  });

  group('field names in writes', () {
    final UserDataConverter converter = UserDataConverter(
      DatabaseId.forProject('project'),
    );

    Matcher invalid(String message) => throwsA(
      isA<ArgumentError>().having(
        (ArgumentError e) => e.message,
        'message',
        message,
      ),
    );

    test('testRejectsEmptyFieldNames', () {
      expect(
        () => converter.parseSetData(<String, Object?>{'': 'foo'}),
        invalid(
          'Invalid data. Document fields must not be empty (found in field ``)',
        ),
      );
      expect(
        () => converter.parseSetData(<String, Object?>{
          'foo': <String, Object?>{'': 1},
        }),
        invalid(
          'Invalid data. Document fields must not be empty (found in field foo.``)',
        ),
      );
    });

    test('testRejectsFieldNamesThatBeginAndEndWithDoubleUnderscore', () {
      expect(
        () => converter.parseSetData(<String, Object?>{'__baz__': 1}),
        invalid(
          'Invalid data. Document fields cannot begin and end with "__" (found in field __baz__)',
        ),
      );
    });

    test('testAcceptsFieldNamesThatOnlyBeginOrEndWithDoubleUnderscore', () {
      expect(
        () => converter.parseSetData(<String, Object?>{'__bar': 1}),
        returnsNormally,
      );
      expect(
        () => converter.parseSetData(<String, Object?>{'bar__': 1}),
        returnsNormally,
      );
    });
  });

  group('minimum and maximum sentinels', () {
    final UserDataConverter converter = UserDataConverter(
      DatabaseId.forProject('project'),
    );

    test('testParsesMinimumAndMaximumInSet', () {
      final List<FieldTransform> transforms = converter
          .parseSetData(<String, Object?>{
            'a': firestore.FieldValue.minimum(1),
            'b': firestore.FieldValue.maximum(2.5),
          })
          .toMutation(key('docs/1'), Precondition.none)
          .fieldTransforms;

      expect(transforms, <FieldTransform>[
        FieldTransform(
          field('a'),
          NumericMinimumTransformOperation(IntegerValue.valueOf(1)),
        ),
        FieldTransform(
          field('b'),
          NumericMaximumTransformOperation(DoubleValue.valueOf(2.5)),
        ),
      ]);
    });

    test('testParsesMinimumAndMaximumInMerge', () {
      final List<FieldTransform> transforms = converter
          .parseMergeData(<String, Object?>{
            'a': firestore.FieldValue.minimum(1),
            'nested': <String, Object?>{'b': firestore.FieldValue.maximum(2)},
          }, null)
          .toMutation(key('docs/1'), Precondition.none)
          .fieldTransforms;

      expect(transforms, <FieldTransform>[
        FieldTransform(
          field('a'),
          NumericMinimumTransformOperation(IntegerValue.valueOf(1)),
        ),
        FieldTransform(
          field('nested.b'),
          NumericMaximumTransformOperation(IntegerValue.valueOf(2)),
        ),
      ]);
    });

    test('testParsesMinimumAndMaximumInUpdate', () {
      final List<FieldTransform> transforms =
          converter.parseUpdateData(<String, Object?>{
            'a.b': firestore.FieldValue.minimum(double.nan),
            'c': firestore.FieldValue.maximum(-3),
          }).fieldTransforms;

      expect(transforms.length, 2);
      expect(
        transforms.firstWhere(
          (FieldTransform t) => t.fieldPath == field('a.b'),
        ),
        FieldTransform(
          field('a.b'),
          NumericMinimumTransformOperation(DoubleValue.nan),
        ),
      );
      expect(
        transforms.firstWhere((FieldTransform t) => t.fieldPath == field('c')),
        FieldTransform(
          field('c'),
          NumericMaximumTransformOperation(IntegerValue.valueOf(-3)),
        ),
      );
    });

    test('testMinimumAndMaximumAreNotAllowedInArrays', () {
      expect(
        () => converter.parseSetData(<String, Object?>{
          'a': <Object?>[firestore.FieldValue.minimum(1)],
        }),
        throwsArgumentError,
      );
      expect(
        () => converter.parseSetData(<String, Object?>{
          'a': <Object?>[firestore.FieldValue.maximum(1)],
        }),
        throwsArgumentError,
      );
    });
  });
}
