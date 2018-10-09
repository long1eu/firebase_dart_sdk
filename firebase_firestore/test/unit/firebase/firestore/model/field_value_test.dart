// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/blob_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/bool_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/geo_point_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/integer_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/reference_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/server_timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/string_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';
import '../../../../util/equals_tester.dart';
import '../../../../util/test_access_helper.dart';
import '../../../../util/test_util.dart';

// ignore_for_file: prefer_const_constructors

void main() {
  final DateTime date1 = DateTime(2016, 5, 20, 10, 20);
  final DateTime date2 = DateTime(2016, 10, 21, 15, 32);

  ObjectValue fromMap(List<Object> entries) {
    final Map<String, FieldValue> res = <String, FieldValue>{};
    for (int i = 0; i < entries.length; i += 2) {
      res[entries[i] as String] = entries[i + 1] as FieldValue;
    }
    return ObjectValue.fromMap(res);
  }

  test('testIntegerValueConversion', () {
    final List<int> testCases = <int>[
      IntegerValue.max,
      -1,
      0,
      1,
      IntegerValue.max
    ];
    for (int i in testCases) {
      final FieldValue value = wrap(i);
      expect(value is IntegerValue, isTrue);
      expect(value.value, i);
    }
  });

  test('testDoubleValueConversion', () {
    final List<double> testCases = <double>[
      double.infinity,
      -double.maxFinite,
      IntegerValue.max * 1.0,
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
      expect(value is DoubleValue, isTrue);

      if (d.isNaN) {
        expect(value.value, isNaN);
      } else {
        expect(value.value, d);
      }
    }
  });

  test('testNullValueConversion', () {
    final FieldValue value = wrap(null);
    expect(value is NullValue, isTrue);
    expect(null, value.value);
  });

  test('testBoolValueConversion', () {
    final List<bool> testCases = <bool>[true, false];
    for (bool b in testCases) {
      final FieldValue value = wrap(b);
      expect(value is BoolValue, isTrue);
      expect(value.value, b);
    }
  });

  test('testDateValueConversion', () {
    final List<DateTime> testCases = <DateTime>[
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime.fromMillisecondsSinceEpoch(1356048000000)
    ];
    for (DateTime d in testCases) {
      final FieldValue value = wrap(d);
      expect(value is TimestampValue, isTrue);
      final Timestamp timestamp = value.value;
      expect(timestamp.toDate(), d);
    }
  });

  test('testTimestampValueConversion', () {
    final List<Timestamp> testCases = <Timestamp>[
      Timestamp(0, 0),
      Timestamp(1356048000, 0)
    ];
    for (Timestamp d in testCases) {
      final FieldValue value = wrap(d);
      expect(value is TimestampValue, isTrue);
      expect(value.value is Timestamp, isTrue);
      expect(value.value, d);
    }
  });

  test('testGeoPointValueConversion', () {
    final List<GeoPoint> testCases = <GeoPoint>[
      GeoPoint(1.24, 4.56),
      GeoPoint(-20.0, 100.0)
    ];
    for (GeoPoint p in testCases) {
      final FieldValue value = wrap(p);
      expect(value is GeoPointValue, isTrue);
      expect(value.value, p);
    }
  });

  test('testBlobValueConversion', () {
    final List<Blob> testCases = <Blob>[
      blob(<int>[1, 2, 3]),
      blob(<int>[1, 2])
    ];
    for (Blob b in testCases) {
      final FieldValue value = wrap(b);
      expect(value is BlobValue, isTrue);
      expect(value.value, b);
    }
  });

  test('testResourceNameConversion', () {
    final DatabaseId id = DatabaseId.forProject('project');
    final List<DocumentReference> testCases = <DocumentReference>[
      ref('foo/bar'),
      ref('foo/baz')
    ];
    for (DocumentReference docRef in testCases) {
      final FieldValue value = wrap(docRef);
      expect(value is ReferenceValue, isTrue);
      final ReferenceValue ref = value;
      expect(ref.value, TestAccessHelper.referenceKey(docRef));
      expect(ref.databaseId, id);
    }
  });

  test('testWrapsEmptyObjects', () {
    expect(ObjectValue.empty, wrap(SplayTreeMap<String, FieldValue>()));
  });

  test('testWrapsSimpleObjects', () {
    // Guava doesn't like null values, so we create a copy of the Immutable map without
    // the null value and then add the null value later.
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

    final FieldValue wrappedActual = wrapObject(actual);
    final ObjectValue wrappedExpected = ObjectValue.fromMap(expected);
    expect(wrappedExpected, wrappedActual);
  });

  test('testWrapsNestedObjects', () {
    final FieldValue actual = wrapList(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        map<String>(<String>['c', 'foo']),
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

  test('testExtractsFields', () {
    final FieldValue val = wrapList(<dynamic>[
      'foo',
      map<dynamic>(<dynamic>['a', 1, 'b', true, 'c', 'string'])
    ]);
    expect(val is ObjectValue, isTrue);
    final ObjectValue obj = val;
    expect(obj.get(field('foo')) is ObjectValue, isTrue);
    expect(obj.get(field('foo.a')), wrap(1));
    expect(obj.get(field('foo.b')), wrap(true));
    expect(obj.get(field('foo.c')), wrap('string'));

    expect(obj.get(field('foo.a.b')), isNull);
    expect(obj.get(field('bar')), isNull);
    expect(obj.get(field('bar.a')), isNull);
  });

  test('testOverwritesExistingFields', () {
    final ObjectValue old = wrapList(<String>['a', 'old']);
    final ObjectValue mod = old.set(field('a'), wrap('mod'));
    expect(mod, isNot(old));
    expect(old, wrapList(<String>['a', 'old']));
    expect(mod, wrapList(<String>['a', 'mod']));
  });

  test('testAddsNewFields', () {
    final ObjectValue empty = ObjectValue.empty;
    ObjectValue mod = empty.set(field('a'), wrap('mod'));
    expect(empty, wrap(SplayTreeMap<String, FieldValue>()));
    expect(mod, wrapList(<String>['a', 'mod']));

    final ObjectValue old = mod;
    mod = old.set(field('b'), wrap(1));
    expect(old, wrapList(<String>['a', 'mod']));
    expect(mod, wrapList(<dynamic>['a', 'mod', 'b', 1]));
  });

  test('testImplicitlyCreatesObjects', () {
    final ObjectValue old = wrapList(<String>['a', 'old']);
    final ObjectValue mod = old.set(field('b.c.d'), wrap('mod'));

    expect(mod, isNot(old));
    expect(old, wrapList(<String>['a', 'old']));
    expect(
        mod,
        wrapList(<dynamic>[
          'a',
          'old',
          'b',
          map<dynamic>(<dynamic>[
            'c',
            map<String>(<String>['d', 'mod'])
          ])
        ]));
  });

  test('testCanOverwritePrimitivesWithObjects', () {
    final ObjectValue old = wrapList(<dynamic>[
      'a',
      map<String>(<String>['b', 'old'])
    ]);
    final ObjectValue mod = old.set(field('a'), wrapList(<String>['b', 'mod']));
    expect(mod, isNot(old));
    expect(
        old,
        wrapList(<dynamic>[
          'a',
          map<String>(<String>['b', 'old'])
        ]));
    expect(
        mod,
        wrapList(<dynamic>[
          'a',
          map<String>(<String>['b', 'mod'])
        ]));
  });

  test('testAddsToNestedObjects', () {
    final ObjectValue old = wrapList(<dynamic>[
      'a',
      map<String>(<String>['b', 'old'])
    ]);
    final ObjectValue mod = old.set(field('a.c'), wrap('mod'));
    expect(mod, isNot(old));
    expect(
        old,
        wrapList(<dynamic>[
          'a',
          map<String>(<String>['b', 'old'])
        ]));
    expect(
        mod,
        wrapList(<dynamic>[
          'a',
          map<String>(<String>['b', 'old', 'c', 'mod'])
        ]));
  });

  test('testDeletesKey', () {
    final ObjectValue old = wrapList(<dynamic>['a', 1, 'b', 2]);
    final ObjectValue mod = old.delete(field('a'));

    expect(mod, isNot(old));
    expect(old, wrapList(<dynamic>['a', 1, 'b', 2]));
    expect(mod, wrapList(<dynamic>['b', 2]));

    final ObjectValue empty = mod.delete(field('b'));
    expect(empty, isNot(mod));
    expect(mod, wrapList(<dynamic>['b', 2]));
    expect(empty, ObjectValue.empty);
  });

  test('testDeletesHandleMissingKeys', () {
    final ObjectValue old = wrapList(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['b', 1, 'c', 2])
    ]);
    ObjectValue mod = old.delete(field('b'));
    expect(old, mod);
    expect(
        mod,
        wrapList(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', 1, 'c', 2])
        ]));

    mod = old.delete(field('a.d'));
    expect(old, mod);
    expect(
        mod,
        wrapList(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', 1, 'c', 2])
        ]));

    mod = old.delete(field('a.b.c'));
    expect(old, mod);
    expect(
        mod,
        wrapList(<dynamic>[
          'a',
          map<dynamic>(<dynamic>['b', 1, 'c', 2])
        ]));
  });

  test('testDeletesNestedKeys', () {
    final Map<String, Object> orig = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        1,
        'c',
        map<dynamic>(<dynamic>['d', 2, 'e', 3])
      ])
    ]);
    ObjectValue old = wrapObject(orig);
    ObjectValue mod = old.delete(field('a.c.d'));

    expect(old, isNot(mod));
    expect(old, wrapObject(orig));

    final Map<String, Object> second = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        1,
        'c',
        map<dynamic>(<dynamic>['e', 3])
      ])
    ]);
    expect(mod, wrapObject(second));

    old = mod;
    mod = old.delete(field('a.c'));

    expect(mod, isNot(old));
    expect(old, wrapObject(second));

    final Map<String, Object> third = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['b', 1])
    ]);
    expect(mod, wrapObject(third));

    old = mod;
    mod = old.delete(field('a'));

    expect(mod, isNot(old));
    expect(old, wrapObject(third));
    expect(mod, ObjectValue.empty);
  });

  test('testArrays', () {
    final ArrayValue expected = ArrayValue.fromList(
        <FieldValue>[StringValue.valueOf('value'), BoolValue.valueOf(true)]);
    final FieldValue actual = wrap(<dynamic>['value', true]);
    expect(actual, expected);
  });

  test('testValueEquality', () {
    EqualsTester()
        .addEqualityGroup(<FieldValue>[wrap(true), BoolValue.valueOf(true)])
        .addEqualityGroup(<FieldValue>[wrap(false), BoolValue.valueOf(false)])
        .addEqualityGroup(<FieldValue>[wrap(null), NullValue.nullValue()])
        //.addEqualityGroup(<FieldValue>[wrap(0.0 / 0.0), DoubleValue.nan])

        // -0.0 and 0.0 compareTo the same but are not equal.
        .addItem(wrap(-0.0))
        .addItem(wrap(0.0))
        .addEqualityGroup(<FieldValue>[wrap(1), IntegerValue.valueOf(1)])
        // Doubles and Longs aren't equal.
        .addEqualityGroup(<FieldValue>[wrap(1.0), DoubleValue.valueOf(1.0)])
        .addEqualityGroup(<FieldValue>[wrap(1.1), DoubleValue.valueOf(1.1)])
        .addEqualityGroup(<FieldValue>[
          wrap(blob(<int>[0, 1, 2])),
          BlobValue.valueOf(blob(<int>[0, 1, 2]))
        ])
        .addItem(wrap(blob(<int>[0, 1])))
        .addEqualityGroup(
            <FieldValue>[wrap('string'), StringValue.valueOf('string')])
        .addItem(StringValue.valueOf('strin'))
        // latin small letter e + combining acute accent
        .addItem(StringValue.valueOf('e\u0301b'))
        // latin small letter e with acute accent
        .addItem(StringValue.valueOf('\u00e9a'))
        .addEqualityGroup(<FieldValue>[
          wrap(date1),
          TimestampValue.valueOf(Timestamp.fromDate(date1))
        ])
        .addItem(TimestampValue.valueOf(Timestamp.fromDate(date2)))
        // NOTE: ServerTimestampValues can't be parsed via wrap().
        .addEqualityGroup(<ServerTimestampValue>[
          ServerTimestampValue(Timestamp.fromDate(date1), null),
          ServerTimestampValue(Timestamp.fromDate(date1), null)
        ])
        .addItem(ServerTimestampValue(Timestamp.fromDate(date2), null))
        .addEqualityGroup(<FieldValue>[
          wrap(GeoPoint(0.0, 1.0)),
          GeoPointValue.valueOf(GeoPoint(0.0, 1.0))
        ])
        .addItem(GeoPointValue.valueOf(GeoPoint(1.0, 0.0)))
        .addEqualityGroup(<FieldValue>[
          wrap(ref('coll/doc1')),
          ReferenceValue.valueOf(dbId('project'), key('coll/doc1'))
        ])
        .addItem(
            ReferenceValue.valueOf(dbId('project', 'bar'), key('coll/doc2')))
        .addItem(
            ReferenceValue.valueOf(dbId('project', 'baz'), key('coll/doc2')))
        .addEqualityGroup(<FieldValue>[
          wrap(<String>['foo', 'bar']),
          wrap(<String>['foo', 'bar'])
        ])
        .addItem(wrap(<String>['foo', 'bar', 'baz']))
        .addItem(wrap(<String>['foo']))
        .addEqualityGroup(<FieldValue>[
          wrapObject(map(<dynamic>['bar', 1, 'foo', 2])),
          wrapObject(map(<dynamic>['foo', 2, 'bar', 1]))
        ])
        .addItem(wrapObject(map(<dynamic>['bar', 2, 'foo', 1])))
        .addItem(wrapObject(map(<dynamic>['bar', 1])))
        .addItem(wrapObject(map(<dynamic>['foo', 1])))
        .testEquals();
  });

  test('testValueOrdering', () {
    ComparatorTester<dynamic>()
        // do not test for compatibility with equals(): +0/-0 break it.
        .permitInconsistencyWithEquals()

        // null first
        .addItem(wrap(null))

        // booleans
        .addItem(wrap(false))
        .addItem(wrap(true))

        // numbers
        .addItem(wrap(double.nan))
        .addItem(wrap(double.negativeInfinity))
        .addItem(wrap(-double.maxFinite))
        .addItem(wrap(-1.1))
        .addItem(wrap(-1.0))
        .addItem(wrap(-DoubleValue.minNormal))
        .addItem(wrap(-double.minPositive))
        // Zeros all compare the same.
        .addEqualityGroup(<Object>[wrap(-0.0), wrap(0.0), wrap(0)])
        .addItem(wrap(double.minPositive))
        .addItem(wrap(DoubleValue.minNormal))
        .addItem(wrap(0.1))
        .addEqualityGroup(<Object>[wrap(1.0), wrap(1)])
        .addItem(wrap(1.1))

        // dates
        .addItem(wrap(date1))
        .addItem(wrap(date2))

        // server timestamps come after all concrete timestamps.
        // NOTE: server timestamps can't be parsed with wrap().
        .addItem(ServerTimestampValue(Timestamp.fromDate(date1), null))
        .addItem(ServerTimestampValue(Timestamp.fromDate(date2), null))

        // strings
        .addItem(wrap(''))
        .addItem(wrap(String.fromCharCodes(<int>[0x0, 0xD7FF, 0xE000, 0xFFFF])))
        .addItem(wrap('(╯°□°）╯︵ ┻━┻'))
        .addItem(wrap('a'))
        .addItem(wrap('abc def'))
        // latin small letter e + combining acute accent + latin small letter b
        .addItem(wrap('e\u0301b'))
        .addItem(wrap('æ'))
        // latin small letter e with acute accent + latin small letter a
        .addItem(wrap('\u00e9a'))

        // blobs
        .addItem(wrap(blob()))
        .addItem(wrap(blob(<int>[0])))
        .addItem(wrap(blob(<int>[0, 1, 2, 3, 4])))
        .addItem(wrap(blob(<int>[0, 1, 2, 4, 3])))
        .addItem(wrap(blob(<int>[255])))

        // resource names
        .addItem(ReferenceValue.valueOf(dbId('p1', 'd1'), key('c1/doc1')))
        .addItem(ReferenceValue.valueOf(dbId('p1', 'd1'), key('c1/doc2')))
        .addItem(ReferenceValue.valueOf(dbId('p1', 'd1'), key('c10/doc1')))
        .addItem(ReferenceValue.valueOf(dbId('p1', 'd1'), key('c2/doc1')))
        .addItem(ReferenceValue.valueOf(dbId('p1', 'd2'), key('c1/doc1')))
        .addItem(ReferenceValue.valueOf(dbId('p2', 'd1'), key('c1/doc1')))

        // geo points
        .addItem(wrap(GeoPoint(-90.0, -180.0)))
        .addItem(wrap(GeoPoint(-90.0, 0.0)))
        .addItem(wrap(GeoPoint(-90.0, 180.0)))
        .addItem(wrap(GeoPoint(0.0, -180.0)))
        .addItem(wrap(GeoPoint(0.0, 0.0)))
        .addItem(wrap(GeoPoint(0.0, 180.0)))
        .addItem(wrap(GeoPoint(1.0, -180.0)))
        .addItem(wrap(GeoPoint(1.0, 0.0)))
        .addItem(wrap(GeoPoint(1.0, 180.0)))
        .addItem(wrap(GeoPoint(90.0, -180.0)))
        .addItem(wrap(GeoPoint(90.0, 0.0)))
        .addItem(wrap(GeoPoint(90.0, 180.0)))

        // arrays
        .addItem(wrap(<String>['bar']))
        .addItem(wrap(<dynamic>['foo', 1]))
        .addItem(wrap(<dynamic>['foo', 2]))
        .addItem(wrap(<dynamic>['foo', '0']))

        // objects
        .addItem(wrapObject(map(<dynamic>['bar', 0])))
        .addItem(wrapObject(map(<dynamic>['bar', 0, 'foo', 1])))
        .addItem(wrapObject(map(<dynamic>['foo', 1])))
        .addItem(wrapObject(map(<dynamic>['foo', 2])))
        .addItem(wrapObject(map(<String>['foo', '0'])))
        .testCompare();
  });
}

// ignore: always_specify_types
const wrap = TestUtil.wrap;
// ignore: always_specify_types
const blob = TestUtil.blob;
// ignore: always_specify_types
const field = TestUtil.field;
// ignore: always_specify_types
const map = TestUtil.map;
// ignore: always_specify_types
const wrapObject = TestUtil.wrapMap;
// ignore: always_specify_types
const wrapList = TestUtil.wrapList;
// ignore: always_specify_types
const ref = TestUtil.ref;
// ignore: always_specify_types
const dbId = TestUtil.dbId;
// ignore: always_specify_types
const key = TestUtil.key;
