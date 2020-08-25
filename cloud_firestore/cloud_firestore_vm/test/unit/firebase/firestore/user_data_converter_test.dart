// File created by
// Lung Razvan <long1eu>
// on 15/03/2020

import 'dart:collection';

import 'package:cloud_firestore_vm/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../util/test_access_helper.dart';
import '../../../util/test_util.dart';

void main() {
  ObjectValue fromMap(List<Object> entries) {
    final Map<String, FieldValue> res = <String, FieldValue>{};
    for (int i = 0; i < entries.length; i += 2) {
      res[entries[i]] = entries[i + 1];
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
    const List<double> testCases = <double>[
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
      final Timestamp timestamp = value.value;

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
      final ReferenceValue ref = value;

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
    final Map<String, Object> actual =
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
    final FieldValue actual = wrapList(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        map<dynamic>(<dynamic>['c', 'foo']),
        'd',
        true
      ])
    ]);

    final ObjectValue expected = fromMap(<dynamic>[
      'a',
      fromMap(<dynamic>[
        'b',
        fromMap(<dynamic>['c', StringValue.valueOf('foo')]),
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
}
