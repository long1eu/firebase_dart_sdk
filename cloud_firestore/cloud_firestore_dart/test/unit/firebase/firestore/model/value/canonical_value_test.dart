// The canonical strings of values, the part of the canonical id of a query
// that the cache stores. Ported from the JS SDK test/unit/model/values.test.ts
// 'canonicalizes values'; the strings must never change.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/canonical_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    hide FieldValue;
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

void main() {
  String canonicalId(Object? value) => canonifyValue(wrap(value));

  test('canonicalizes values', () {
    expect(canonicalId(null), 'null');
    expect(canonicalId(true), 'true');
    expect(canonicalId(false), 'false');
    expect(canonicalId(1), '1');
    expect(canonicalId(1.1), '1.1');
    expect(canonicalId(const Timestamp(30, 1000)), 'time(30,1000)');
    expect(canonicalId('a'), 'a');
    expect(canonicalId(blob(<int>[1, 2, 3])), 'AQID');
    expect(
      canonifyValue(
        ReferenceValue.valueOf(
          DatabaseId.forDatabase('p1', 'd1'),
          key('c1/doc1'),
        ),
      ),
      'c1/doc1',
    );
    expect(canonicalId(const GeoPoint(30, 60)), 'geo(30,60)');
    expect(canonicalId(<int>[1, 2, 3]), '[1,2,3]');
    expect(
      canonicalId(<String, Object?>{'a': 1, 'b': 2, 'c': '3'}),
      '{a:1,b:2,c:3}',
    );
    expect(
      canonicalId(VectorValue(<double>[1, 1.0, -2, 3.14])),
      '{__type__:__vector__,value:[1,1,-2,3.14]}',
    );
    expect(
      canonicalId(<String, Object?>{
        'a': <Object?>[
          'b',
          <String, Object?>{'c': const GeoPoint(30, 60)},
        ],
      }),
      '{a:[b,{c:geo(30,60)}]}',
    );
    expect(
      canonicalId(RegexValue('a', 'b')),
      '{__regex__:{options:b,pattern:a}}',
    );
    expect(canonicalId(BsonObjectId('foo')), '{__oid__:foo}');
    expect(
      canonicalId(BsonTimestamp(1, 2)),
      '{__request_timestamp__:{increment:2,seconds:1}}',
    );
    expect(canonicalId(Int32Value(1)), '{__int__:1}');
    expect(canonicalId(Decimal128Value('-1.2e3')), '{__decimal128__:-1.2e3}');
    expect(
      canonicalId(Blob.bsonBinary(1, Uint8List.fromList(<int>[1, 2, 3]))),
      '{__binary__:AQECAw==}',
    );
    expect(canonicalId(MinKey.instance), '{__min__:null}');
    expect(canonicalId(MaxKey.instance), '{__max__:null}');
  });

  test('the keys of a map are sorted', () {
    expect(
      canonicalId(<String, Object?>{'b': 1, 'a': 2, 'B': 3, 'aa': 4}),
      '{B:3,a:2,aa:4,b:1}',
    );
    expect(canonicalId(<String, Object?>{}), '{}');
    expect(canonicalId(<Object?>[]), '[]');
  });

  test('doubles are written as JS writes numbers', () {
    // `'' + value` in JS.
    const List<(double, String)> cases = <(double, String)>[
      (1.0, '1'),
      (-2.0, '-2'),
      (0.0, '0'),
      (-0.0, '0'),
      (1.5, '1.5'),
      (0.1, '0.1'),
      (1e-7, '1e-7'),
      (0.000001, '0.000001'),
      (1e20, '100000000000000000000'),
      (123456789012345680000.0, '123456789012345680000'),
      (1e21, '1e+21'),
      (1.5e300, '1.5e+300'),
      (9007199254740993.0, '9007199254740992'),
      (double.maxFinite, '1.7976931348623157e+308'),
      (double.minPositive, '5e-324'),
      (double.infinity, 'Infinity'),
      (double.negativeInfinity, '-Infinity'),
    ];
    for (final (double value, String expected) in cases) {
      expect(canonifyDouble(value), expected, reason: '$value');
    }
    expect(canonifyDouble(double.nan), 'NaN');
    expect(canonicalId(double.nan), 'NaN');
  });

  test('integers are written in full', () {
    expect(canonicalId(9223372036854775807), '9223372036854775807');
    expect(canonicalId(-9223372036854775808), '-9223372036854775808');
  });

  test('a pending server timestamp is written as its map', () {
    expect(
      canonifyValue(ServerTimestampValue(const Timestamp(5, 6), null)),
      '{__local_write_time__:time(5,6),__type__:server_timestamp}',
    );
    expect(
      canonifyValue(ServerTimestampValue(const Timestamp(5, 6), wrap('old'))),
      '{__local_write_time__:time(5,6),__previous_value__:old,'
      '__type__:server_timestamp}',
    );
  });

  test('does not depend on the toString of a value', () {
    // What the canonical id of a query was built from before.
    expect(
      canonicalId(const Timestamp(30, 1000)),
      isNot(contains('Timestamp')),
    );
    expect(canonicalId(const GeoPoint(30, 60)), isNot(contains('GeoPoint')));
    expect(canonicalId(blob(<int>[1])), isNot(contains('Blob')));
  });
}
