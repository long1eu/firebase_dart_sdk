// Fuzz: the order and equality of values on near collisions.
//
// value_order_property_test.dart checks the order laws on random values,
// which rarely tie. Here the values come from a small pool of values that
// compare equal, or almost, across types (1, 1.0, Int32 1, Decimal128 "1.0"
// and "1.000...1", the NaNs, -0.0, timestamps and BSON timestamps, blobs and
// BSON binaries, ...) and from arrays and maps of them, so that ties and
// common prefixes are frequent. Every triple of values is checked:
// antisymmetry, transitivity (of < and of ==), and the agreement of ==,
// hashCode and compareTo.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show
        Blob,
        BsonObjectId,
        BsonTimestamp,
        Decimal128Value,
        GeoPoint,
        Int32Value,
        MaxKey,
        MinKey,
        RegexValue,
        Timestamp,
        VectorValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../util/property.dart';
import '../../util/test_util.dart' as util;

/// Values that tie, or almost, with others of the pool.
final List<Object? Function()> pool = <Object? Function()>[
  () => null,
  () => false,
  () => true,
  () => 0,
  () => 0.0,
  () => -0.0,
  () => 1,
  () => 1.0,
  () => -1,
  () => 2,
  () => 1.5,
  () => double.nan,
  () => double.infinity,
  () => double.negativeInfinity,
  () => 9007199254740992,
  () => 9007199254740993,
  () => 9007199254740992.0,
  () => 9223372036854775807,
  () => -9223372036854775808,
  () => 9223372036854775807.0,
  () => Int32Value(0),
  () => Int32Value(1),
  () => Int32Value(-1),
  () => Int32Value(2147483647),
  () => Decimal128Value('0'),
  () => Decimal128Value('-0'),
  () => Decimal128Value('0.0'),
  () => Decimal128Value('1'),
  () => Decimal128Value('1.0'),
  () => Decimal128Value('1E0'),
  () => Decimal128Value('10E-1'),
  () => Decimal128Value('1.000000000000000000000000000000001'),
  () => Decimal128Value('0.999999999999999999999999999999999'),
  () => Decimal128Value('1.5'),
  () => Decimal128Value('9007199254740993'),
  () => Decimal128Value('9223372036854775808'),
  () => Decimal128Value('NaN'),
  () => Decimal128Value('Infinity'),
  () => Decimal128Value('-Infinity'),
  () => '',
  () => 'a',
  () => 'a\u0000',
  () => 'é',
  () => 'é',
  () => '\u{10000}',
  () => '￿',
  () => Blob(Uint8List(0)),
  () => Blob(Uint8List.fromList(<int>[0])),
  () => Blob(Uint8List.fromList(<int>[1])),
  () => Blob.bsonBinary(1, Uint8List(0)),
  () => Blob.bsonBinary(1, Uint8List.fromList(<int>[0])),
  () => Blob.bsonBinary(128, Uint8List(0)),
  () => const Timestamp(0, 0),
  () => const Timestamp(0, 1000),
  () => const Timestamp(1, 0),
  () => BsonTimestamp(0, 0),
  () => BsonTimestamp(0, 1),
  () => BsonTimestamp(1, 0),
  () => const GeoPoint(0, 0),
  () => const GeoPoint(0, -0.0),
  () => const GeoPoint(-90, 180),
  () => util.ref('c/a'),
  () => util.ref('c/a/s/a'),
  () => util.ref('c/b'),
  () => VectorValue(const <double>[]),
  () => VectorValue(const <double>[1]),
  () => VectorValue(const <double>[0.0]),
  () => VectorValue(const <double>[-0.0]),
  () => VectorValue(const <double>[1, 2]),
  () => MinKey.instance,
  () => MaxKey.instance,
  () => const RegexValue('a', ''),
  () => const RegexValue('a', 'i'),
  () => const RegexValue('', ''),
  () => const BsonObjectId('507f1f77bcf86cd799439011'),
  () => const BsonObjectId('507f1f77bcf86cd799439012'),
];

extension on Gen {
  Object? poolValue([int depth = 2]) {
    switch (below(depth > 0 ? 10 : 8)) {
      case 8:
        return <Object?>[for (int i = below(3); i > 0; i--) poolValue(0)];
      case 9:
        return <String, Object?>{
          for (int i = below(3); i > 0; i--)
            pick(const <String>['a', 'b', '__type__', 'value', '__int__']):
                poolValue(depth - 1),
        };
      default:
        return pick(pool)();
    }
  }
}

class Values {
  Values(this.user) : model = user.map(util.wrap).toList();

  final List<Object?> user;
  final List<FieldValue> model;

  @override
  String toString() => describe(user);
}

String? lawViolation(FieldValue a, FieldValue b, FieldValue c) {
  final int ab = a.compareTo(b).sign;
  final int ba = b.compareTo(a).sign;
  final int bc = b.compareTo(c).sign;
  final int ac = a.compareTo(c).sign;
  if (ab != -ba) {
    return 'compare(a, b) = $ab but compare(b, a) = $ba';
  }
  if (a.compareTo(a) != 0) {
    return 'compare(a, a) = ${a.compareTo(a)}';
  }
  if (ab == 0 && bc == 0 && ac != 0) {
    return 'a = b and b = c but compare(a, c) = $ac';
  }
  if (ab <= 0 && bc <= 0 && (ab < 0 || bc < 0) && ac >= 0) {
    return 'a < b <= c or a <= b < c but compare(a, c) = $ac';
  }
  if (a == b) {
    if (ab != 0) {
      return 'a == b but compare(a, b) = $ab';
    }
    if (a.hashCode != b.hashCode) {
      return 'a == b but their hash codes differ';
    }
  }
  if ((a == b) != (b == a)) {
    return '== is not symmetric';
  }
  return null;
}

void main() {
  test('order and equality laws on near collisions', () {
    forAll<Values>(
      'near collisions',
      count: cases(60),
      generate: (Gen gen) =>
          Values(<Object?>[for (int i = 0; i < 24; i++) gen.poolValue()]),
      check: (Values values) {
        final List<FieldValue> model = values.model;
        for (int i = 0; i < model.length; i++) {
          for (int j = 0; j < model.length; j++) {
            for (int k = 0; k < model.length; k++) {
              final String? problem = lawViolation(
                model[i],
                model[j],
                model[k],
              );
              if (problem != null) {
                fail(
                  '$problem\n'
                  '    a = ${describe(values.user[i])}\n'
                  '    b = ${describe(values.user[j])}\n'
                  '    c = ${describe(values.user[k])}',
                );
              }
            }
          }
        }
      },
    );
  });

  test('every pair of pool values obeys the laws', () {
    final List<Object?> user = <Object?>[
      for (final Object? Function() make in pool) make(),
      for (final Object? Function() make in pool) <Object?>[make()],
      for (final Object? Function() make in pool)
        <String, Object?>{'a': make()},
    ];
    final List<FieldValue> model = user.map(util.wrap).toList();
    for (int i = 0; i < model.length; i++) {
      for (int j = 0; j < model.length; j++) {
        for (int k = 0; k < model.length; k++) {
          final String? problem = lawViolation(model[i], model[j], model[k]);
          if (problem != null) {
            fail(
              '$problem\n'
              '    a = ${describe(user[i])}\n'
              '    b = ${describe(user[j])}\n'
              '    c = ${describe(user[k])}',
            );
          }
        }
      }
    }
  });
}
