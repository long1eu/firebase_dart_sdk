// Property: the order of values is a total order that is consistent with
// equality and hashCode, and the index value encoding sorts the same way.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart'
    show BsonTimestamp, Decimal128Value, Int32Value;
import 'package:cloud_firestore_dart/src/firebase/firestore/index/firestore_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../util/property.dart';
import '../../util/test_util.dart' as util;

Uint8List encode(FieldValue value, SegmentKind kind) {
  final IndexByteEncoder encoder = IndexByteEncoder();
  FirestoreIndexValueWriter.instance.writeIndexValue(
    value,
    encoder.forKind(kind),
  );
  return encoder.encodedBytes;
}

int compareBytes(List<int> a, List<int> b) {
  for (int i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) {
      return a[i] < b[i] ? -1 : 1;
    }
  }
  return a.length.compareTo(b.length);
}

/// A list of user values, each with its model value.
class Values {
  Values(this.user) : model = user.map(util.wrap).toList();

  final List<Object?> user;
  final List<FieldValue> model;

  @override
  String toString() => describe(user);
}

Values someValues(Gen gen) => Values(<Object?>[
  for (int i = 0; i < 4 + gen.size * 4; i++)
    gen.value(bson: true, reference: util.ref),
]);

/// Reports the first pair of [values] for which [holds] is false.
void forAllPairs(
  Values values,
  String? Function(FieldValue a, FieldValue b) violation,
) {
  for (int i = 0; i < values.model.length; i++) {
    for (int j = 0; j < values.model.length; j++) {
      final String? problem = violation(values.model[i], values.model[j]);
      if (problem != null) {
        fail(
          '$problem\n    a = ${describe(values.user[i])}\n'
          '    b = ${describe(values.user[j])}',
        );
      }
    }
  }
}

/// [value] with every number replaced by the double the index stores.
Object? asDoubles(Object? value) {
  if (value is int) {
    return value.toDouble();
  } else if (value is Int32Value) {
    return value.value.toDouble();
  } else if (value is Decimal128Value) {
    return double.parse(value.stringValue);
  } else if (value is List) {
    return value.map(asDoubles).toList();
  } else if (value is Map) {
    return <Object?, Object?>{
      for (final MapEntry<Object?, Object?> e in value.entries)
        e.key: asDoubles(e.value),
    };
  }
  return value;
}

/// Whether [a] and [b] only differ in numbers that are the same double.
bool sameAsDoubles(Object? a, Object? b) =>
    util.wrap(asDoubles(a)).compareTo(util.wrap(asDoubles(b))) == 0;

void main() {
  // Pinned upstream quirks of the index encoding.
  test('quirk: numbers are indexed as doubles and can collide', () {
    // 2^53 and 2^53 + 1 are different integers and the same double.
    final FieldValue a = util.wrap(9007199254740992);
    final FieldValue b = util.wrap(9007199254740993);
    expect(a.compareTo(b), lessThan(0));
    expect(encode(a, SegmentKind.ascending), encode(b, SegmentKind.ascending));

    final FieldValue one = util.wrap(1);
    final FieldValue more = util.wrap(
      Decimal128Value('1.000000000000000000000000000000001'),
    );
    expect(one.compareTo(more), lessThan(0));
    expect(
      encode(one, SegmentKind.ascending),
      encode(more, SegmentKind.ascending),
    );
  });

  // The Android SDK indexes a reference to a nested document before its
  // ancestor, and BSON timestamps from 2038 on before all others; this port
  // does not (see firestore_index_value_writer_test.dart).
  test('references of different depths and late BSON timestamps are indexed '
      'in order', () {
    final FieldValue parent = util.wrap(util.ref('c/a'));
    final FieldValue child = util.wrap(util.ref('c/a/s/a'));
    expect(parent.compareTo(child), lessThan(0));
    expect(
      compareBytes(
        encode(parent, SegmentKind.ascending),
        encode(child, SegmentKind.ascending),
      ),
      lessThan(0),
    );

    final FieldValue early = util.wrap(BsonTimestamp(496, 4294967295));
    final FieldValue late = util.wrap(BsonTimestamp(4294967295, 137));
    expect(early.compareTo(late), lessThan(0));
    expect(
      compareBytes(
        encode(early, SegmentKind.ascending),
        encode(late, SegmentKind.ascending),
      ),
      lessThan(0),
    );
  });

  // Regression: a double was compared with an integer after converting the
  // integer to a double, so the order depended on the side of the operands.
  test('doubles and integers beyond 2^53 compare by their exact values', () {
    final FieldValue double53 = util.wrap(9007199254740992.0);
    final FieldValue int53 = util.wrap(9007199254740992);
    final FieldValue int53plus1 = util.wrap(9007199254740993);
    expect(double53.compareTo(int53), 0);
    expect(int53.compareTo(double53), 0);
    expect(double53.compareTo(int53plus1), lessThan(0));
    expect(int53plus1.compareTo(double53), greaterThan(0));

    final FieldValue maxInt = util.wrap(9223372036854775807);
    final FieldValue minInt = util.wrap(-9223372036854775808);
    final FieldValue double63 = util.wrap(9223372036854775808.0);
    final FieldValue doubleMinus63 = util.wrap(-9223372036854775808.0);
    expect(double63.compareTo(maxInt), greaterThan(0));
    expect(maxInt.compareTo(double63), lessThan(0));
    expect(doubleMinus63.compareTo(minInt), 0);
    expect(minInt.compareTo(doubleMinus63), 0);

    expect(util.wrap(1.5).compareTo(util.wrap(1)), greaterThan(0));
    expect(util.wrap(-1.5).compareTo(util.wrap(-1)), lessThan(0));
    expect(util.wrap(-0.0).compareTo(util.wrap(0)), 0);
    expect(util.wrap(0).compareTo(util.wrap(-0.0)), 0);
    expect(
      util.wrap(double.nan).compareTo(util.wrap(-9223372036854775808)),
      lessThan(0),
    );
    expect(
      util.wrap(-9223372036854775808).compareTo(util.wrap(double.nan)),
      greaterThan(0),
    );
    expect(util.wrap(double.negativeInfinity).compareTo(minInt), lessThan(0));
    expect(util.wrap(double.infinity).compareTo(maxInt), greaterThan(0));
  });

  test('compareTo is antisymmetric and reflexive', () {
    forAll<Values>(
      'antisymmetry',
      count: cases(150),
      generate: someValues,
      check: (Values values) =>
          forAllPairs(values, (FieldValue a, FieldValue b) {
            final int ab = a.compareTo(b).sign;
            final int ba = b.compareTo(a).sign;
            if (ab != -ba) {
              return 'compare(a, b) = $ab but compare(b, a) = $ba';
            }
            if (identical(a, b) && ab != 0) {
              return 'compare(a, a) = $ab';
            }
            return null;
          }),
    );
  });

  test('compareTo is transitive (a sorted list is sorted for every pair)', () {
    forAll<Values>(
      'transitivity',
      count: cases(150),
      generate: someValues,
      check: (Values values) {
        final List<int> order = <int>[
          for (int i = 0; i < values.model.length; i++) i,
        ]..sort((int a, int b) => values.model[a].compareTo(values.model[b]));
        for (int i = 0; i < order.length; i++) {
          for (int j = i + 1; j < order.length; j++) {
            final FieldValue a = values.model[order[i]];
            final FieldValue b = values.model[order[j]];
            if (a.compareTo(b) > 0) {
              fail(
                'sorted, but a > b\n'
                '    a = ${describe(values.user[order[i]])}\n'
                '    b = ${describe(values.user[order[j]])}',
              );
            }
          }
        }
      },
    );
  });

  test('equal values compare as equal and have equal hash codes', () {
    forAll<Values>(
      'equality',
      count: cases(150),
      generate: (Gen gen) {
        // Pairs of structurally equal values, generated twice from one seed.
        final List<Object?> user = <Object?>[];
        for (int i = 0; i < 6; i++) {
          final int seed = gen.below(1 << 30);
          user
            ..add(
              Gen(seed, size: gen.size).value(bson: true, reference: util.ref),
            )
            ..add(
              Gen(seed, size: gen.size).value(bson: true, reference: util.ref),
            );
        }
        return Values(user);
      },
      check: (Values values) {
        for (int i = 0; i < values.model.length; i += 2) {
          final FieldValue a = values.model[i];
          final FieldValue b = values.model[i + 1];
          final String shown = describe(values.user[i]);
          expect(a == b, isTrue, reason: 'a copy is not equal: $shown');
          expect(a.hashCode, b.hashCode, reason: 'hashCode of a copy: $shown');
          expect(a.compareTo(b), 0, reason: 'compare with a copy: $shown');
        }
        forAllPairs(values, (FieldValue a, FieldValue b) {
          if (a == b) {
            if (a.compareTo(b) != 0) {
              return 'a == b but compare(a, b) = ${a.compareTo(b)}';
            }
            if (a.hashCode != b.hashCode) {
              return 'a == b but the hash codes differ';
            }
          } else if (a.compareTo(b) == 0 && a.typeOrder != b.typeOrder) {
            return 'compare(a, b) == 0 for values of different types';
          }
          return null;
        });
      },
    );
  });

  test('values of different types sort by type', () {
    forAll<Values>(
      'type order',
      count: cases(100),
      generate: someValues,
      check: (Values values) => forAllPairs(values, (
        FieldValue a,
        FieldValue b,
      ) {
        if (a.typeOrder != b.typeOrder &&
            a.compareTo(b).sign != a.typeOrder.compareTo(b.typeOrder).sign) {
          return 'type order ${a.typeOrder} vs ${b.typeOrder} but '
              'compare(a, b) = ${a.compareTo(b)}';
        }
        return null;
      }),
    );
  });

  for (final SegmentKind kind in <SegmentKind>[
    SegmentKind.ascending,
    SegmentKind.descending,
  ]) {
    test('the ${kind.name} index encoding sorts like compareTo', () {
      forAll<Values>(
        'index encoding (${kind.name})',
        count: cases(150),
        generate: someValues,
        check: (Values values) {
          final List<Uint8List> encoded = <Uint8List>[
            for (final FieldValue value in values.model) encode(value, kind),
          ];
          for (int i = 0; i < encoded.length; i++) {
            for (int j = 0; j < encoded.length; j++) {
              final int expected = kind == SegmentKind.ascending
                  ? values.model[i].compareTo(values.model[j]).sign
                  : values.model[j].compareTo(values.model[i]).sign;
              final int actual = compareBytes(encoded[i], encoded[j]).sign;
              // Numbers are indexed as doubles (as upstream), so two
              // different numbers that are the same double encode
              // equally. They must never sort the other way round.
              if (actual == 0 &&
                  sameAsDoubles(values.user[i], values.user[j])) {
                continue;
              }
              if (expected != actual) {
                fail(
                  'compare gives $expected, the encoded bytes $actual\n'
                  '    a = ${describe(values.user[i])} -> ${encoded[i]}\n'
                  '    b = ${describe(values.user[j])} -> ${encoded[j]}',
                );
              }
            }
          }
        },
      );
    });
  }
}
