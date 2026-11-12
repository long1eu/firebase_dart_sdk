// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

import 'dart:collection';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_extremum_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/test_access_helper.dart';
import '../../../util/test_util.dart';

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

  test('testConvertsBoolValue', () {
    final List<bool> testCases = <bool>[true, false];
    for (bool b in testCases) {
      final FieldValue value = wrap(b);

      expect(value, isA<BoolValue>());
      expect(value.value, b);
    }
  });

  test('testConvertsIntegerValue', () {
    final List<int> testCases = <int>[
      IntegerValue.min,
      -1,
      0,
      1,
      IntegerValue.max
    ];
    for (int i in testCases) {
      final FieldValue value = wrap(i);

      expect(value, isA<IntegerValue>());
      expect(value.value, i);
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
      double.nan
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
      DateTime.fromMillisecondsSinceEpoch(1356048000000)
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
      Timestamp(1356048000, 0)
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
      blob(<int>[1, 2])
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
      ref('foo/baz')
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
      GeoPoint(-20, 100)
    ];
    for (GeoPoint p in testCases) {
      final FieldValue value = wrap(p);

      expect(value, isA<GeoPointValue>());
      expect(value.value, p);
    }
  });

  test('testConvertsEmptyObjects', () {
    expect(wrap(SplayTreeMap<String, FieldValue>()), ObjectValue.empty);
  });

  test('testConvertsSimpleObjects', () {
    // Guava doesn't like null values, so we create a copy of the Immutable map
    // without the null value and then add the null value later.
    final Map<String, Object?> actual =
        map(<dynamic>['a', 'foo', 'b', 1, 'c', true, 'd', null]);

    final Map<String, FieldValue> expected = map(<dynamic>[
      'a',
      StringValue.valueOf('foo'),
      'b',
      IntegerValue.valueOf(1),
      'c',
      BoolValue.valueOf(true),
      'd',
      NullValue.nullValue()
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
        true
      ])
    ]);

    final ObjectValue expected = fromMap(<Object>[
      'a',
      fromMap(<Object>[
        'b',
        fromMap(<Object>['c', StringValue.valueOf('foo')]),
        'd',
        BoolValue.valueOf(true)
      ])
    ]);

    expect(actual, expected);
  });

  test('testConvertsLists', () {
    final ArrayValue expected = ArrayValue.fromList(
        <FieldValue>[StringValue.valueOf('value'), BoolValue.valueOf(true)]);
    final FieldValue actual = wrap(<dynamic>['value', true]);

    expect(actual, expected);
  });
  test('testRejectsNestedArraysInQueryValues', () {
    final UserDataConverter converter =
        UserDataConverter(DatabaseId.forProject('project'));
    expect(
        () => converter.parseQueryValue(<Object>[
              <int>[1, 2]
            ]),
        throwsArgumentError);
  });

  test('testAllowsArraysInsideInQueryValues', () {
    final UserDataConverter converter =
        UserDataConverter(DatabaseId.forProject('project'));
    final FieldValue actual = converter.parseQueryValue(<Object>[
      1,
      <int>[1, 2]
    ], allowArrays: true);
    expect(
        actual,
        ArrayValue.fromList(<FieldValue>[
          IntegerValue.valueOf(1),
          ArrayValue.fromList(
              <FieldValue>[IntegerValue.valueOf(1), IntegerValue.valueOf(2)])
        ]));
  });

  group('field names in writes', () {
    final UserDataConverter converter =
        UserDataConverter(DatabaseId.forProject('project'));

    Matcher invalid(String message) => throwsA(isA<ArgumentError>()
        .having((ArgumentError e) => e.message, 'message', message));

    test('testRejectsEmptyFieldNames', () {
      expect(
          () => converter.parseSetData(<String, Object?>{'': 'foo'}),
          invalid(
              'Invalid data. Document fields must not be empty (found in field ``)'));
      expect(
          () => converter.parseSetData(<String, Object?>{
                'foo': <String, Object?>{'': 1}
              }),
          invalid(
              'Invalid data. Document fields must not be empty (found in field foo.``)'));
    });

    test('testRejectsFieldNamesThatBeginAndEndWithDoubleUnderscore', () {
      expect(
          () => converter.parseSetData(<String, Object?>{'__baz__': 1}),
          invalid(
              'Invalid data. Document fields cannot begin and end with "__" (found in field __baz__)'));
    });

    test('testAcceptsFieldNamesThatOnlyBeginOrEndWithDoubleUnderscore', () {
      expect(() => converter.parseSetData(<String, Object?>{'__bar': 1}),
          returnsNormally);
      expect(() => converter.parseSetData(<String, Object?>{'bar__': 1}),
          returnsNormally);
    });
  });

  group('minimum and maximum sentinels', () {
    final UserDataConverter converter =
        UserDataConverter(DatabaseId.forProject('project'));

    test('testParsesMinimumAndMaximumInSet', () {
      final List<FieldTransform> transforms = converter
          .parseSetData(<String, Object?>{
            'a': firestore.FieldValue.minimum(1),
            'b': firestore.FieldValue.maximum(2.5),
          })
          .toMutation(key('docs/1'), Precondition.none)
          .fieldTransforms;

      expect(transforms, <FieldTransform>[
        FieldTransform(field('a'),
            NumericMinimumTransformOperation(IntegerValue.valueOf(1))),
        FieldTransform(field('b'),
            NumericMaximumTransformOperation(DoubleValue.valueOf(2.5))),
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
        FieldTransform(field('a'),
            NumericMinimumTransformOperation(IntegerValue.valueOf(1))),
        FieldTransform(field('nested.b'),
            NumericMaximumTransformOperation(IntegerValue.valueOf(2))),
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
          transforms
              .firstWhere((FieldTransform t) => t.fieldPath == field('a.b')),
          FieldTransform(
              field('a.b'), NumericMinimumTransformOperation(DoubleValue.nan)));
      expect(
          transforms
              .firstWhere((FieldTransform t) => t.fieldPath == field('c')),
          FieldTransform(field('c'),
              NumericMaximumTransformOperation(IntegerValue.valueOf(-3))));
    });

    test('testMinimumAndMaximumAreNotAllowedInArrays', () {
      expect(
          () => converter.parseSetData(<String, Object?>{
                'a': <Object?>[firestore.FieldValue.minimum(1)]
              }),
          throwsArgumentError);
      expect(
          () => converter.parseSetData(<String, Object?>{
                'a': <Object?>[firestore.FieldValue.maximum(1)]
              }),
          throwsArgumentError);
    });
  });
}
