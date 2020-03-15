// File created by
// Lung Razvan <long1eu>
// on 27/09/2018

import 'dart:collection';

import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/comparator_test.dart';
import '../../../../util/equals_tester.dart';
import '../../../../util/test_util.dart';

// ignore_for_file: prefer_const_constructors

void main() {
  final DateTime date1 = DateTime(2016, 5, 20, 10, 20);
  final DateTime date2 = DateTime(2016, 10, 21, 15, 32);

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
    ObjectValue old = wrapMap(orig);
    ObjectValue mod = old.delete(field('a.c.d'));

    expect(old, isNot(mod));
    expect(old, wrapMap(orig));

    final Map<String, Object> second = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>[
        'b',
        1,
        'c',
        map<dynamic>(<dynamic>['e', 3])
      ])
    ]);
    expect(mod, wrapMap(second));

    old = mod;
    mod = old.delete(field('a.c'));

    expect(mod, isNot(old));
    expect(old, wrapMap(second));

    final Map<String, Object> third = map(<dynamic>[
      'a',
      map<dynamic>(<dynamic>['b', 1])
    ]);
    expect(mod, wrapMap(third));

    old = mod;
    mod = old.delete(field('a'));

    expect(mod, isNot(old));
    expect(old, wrapMap(third));
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
          wrapMap(map(<dynamic>['bar', 1, 'foo', 2])),
          wrapMap(map(<dynamic>['foo', 2, 'bar', 1]))
        ])
        .addItem(wrapMap(map(<dynamic>['bar', 2, 'foo', 1])))
        .addItem(wrapMap(map(<dynamic>['bar', 1])))
        .addItem(wrapMap(map(<dynamic>['foo', 1])))
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
        .addItem(wrapMap(map(<dynamic>['bar', 0])))
        .addItem(wrapMap(map(<dynamic>['bar', 0, 'foo', 1])))
        .addItem(wrapMap(map(<dynamic>['foo', 1])))
        .addItem(wrapMap(map(<dynamic>['foo', 2])))
        .addItem(wrapMap(map(<String>['foo', '0'])))
        .testCompare();
  });
}
