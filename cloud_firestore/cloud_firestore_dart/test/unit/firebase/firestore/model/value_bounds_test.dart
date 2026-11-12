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
import 'package:cloud_firestore_dart/src/firebase/firestore/core/filter/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/order_by.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/firestore_index_value_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_entry.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

Uint8List encode(FieldValue value, [SegmentKind kind = SegmentKind.ascending]) {
  final IndexByteEncoder encoder = IndexByteEncoder();
  FirestoreIndexValueWriter.instance
      .writeIndexValue(value, encoder.forKind(kind));
  return encoder.encodedBytes;
}

/// Not upstream (the bound helpers of `Values` are covered there through the
/// index manager tests): the bounds of each type, and the two `Target` methods
/// TargetTest does not reach.
void main() {
  // One or more values per type, the types in the order of the backend.
  final List<List<Object?>> types = <List<Object?>>[
    <Object?>[null],
    <Object?>[MinKey.instance],
    <Object?>[false, true],
    <Object?>[double.nan, -1, 1.5, Int32Value(7), Decimal128Value('1e3')],
    <Object?>[Timestamp(0, 0), Timestamp(100, 0)],
    <Object?>[BsonTimestamp(0, 0), BsonTimestamp(5, 6)],
    <Object?>['', 'a', '￿'],
    <Object?>[
      blob(),
      blob(<int>[255]),
      Blob.bsonBinary(200, Uint8List.fromList(<int>[1]))
    ],
    <Object?>[ref('a/b'), ref('z/z')],
    <Object?>[const BsonObjectId(''), const BsonObjectId('ffff')],
    <Object?>[const GeoPoint(-90, -180), const GeoPoint(90, 180)],
    <Object?>[const RegexValue('', ''), const RegexValue('z', 'i')],
    <Object?>[
      <Object?>[],
      <Object?>['z']
    ],
    <Object?>[
      VectorValue(<double>[]),
      VectorValue(<double>[1, 2])
    ],
    <Object?>[
      <String, Object?>{},
      <String, Object?>{'z': 1}
    ],
    <Object?>[MaxKey.instance],
  ];

  test('the lower bound of a type is not above any value of the type', () {
    for (final List<Object?> type in types) {
      final FieldValue lower = ValueBounds.getLowerBound(wrap(type.first));
      for (final Object? value in type) {
        expect(ValueBounds.getLowerBound(wrap(value)), lower,
            reason: 'same bound for $value');
        expect(lower.compareTo(wrap(value)), lessThanOrEqualTo(0),
            reason: '$value');
      }
    }
  });

  test('the upper bound of a type is the lower bound of the next type', () {
    for (int i = 0; i < types.length; i++) {
      final FieldValue upper = ValueBounds.getUpperBound(wrap(types[i].first));
      for (final Object? value in types[i]) {
        expect(ValueBounds.getUpperBound(wrap(value)), upper,
            reason: 'same bound for $value');
        expect(upper.compareTo(wrap(value)), greaterThan(0), reason: '$value');
      }
      if (i + 1 < types.length) {
        expect(upper, ValueBounds.getLowerBound(wrap(types[i + 1].first)),
            reason: 'after ${types[i].first}');
      } else {
        expect(upper, ValueBounds.internalMaxValue);
      }
    }
  });

  test('a pending server timestamp has the bounds of a map', () {
    final FieldValue pending = ServerTimestampValue(Timestamp(1, 0), null);
    expect(ValueBounds.getLowerBound(pending), wrap(<String, Object?>{}));
    expect(ValueBounds.getUpperBound(pending), wrap(MaxKey.instance));
  });

  test('the internal min and max values bracket every value', () {
    for (final List<Object?> type in types) {
      for (final Object? value in type) {
        final FieldValue wrapped = wrap(value);
        expect(ValueBounds.internalMinValue.compareTo(wrapped),
            lessThanOrEqualTo(0),
            reason: '$value');
        expect(ValueBounds.internalMaxValue.compareTo(wrapped), 1,
            reason: '$value');
        expect(wrapped.compareTo(ValueBounds.internalMaxValue), -1,
            reason: '$value');
      }
    }
    expect(ValueBounds.internalMaxValue.compareTo(ValueBounds.internalMaxValue),
        0);
    expect(ValueBounds.internalMaxValue, InternalMaxValue.instance);
  });

  test('the bounds sort the same way in the index encoding', () {
    for (final List<Object?> type in types) {
      for (final Object? value in type) {
        final Uint8List encoded = encode(wrap(value));
        if (wrap(value) is ReferenceValue) {
          // See the next test.
          continue;
        }
        expect(
            compareByteArrays(
                encode(ValueBounds.getLowerBound(wrap(value))), encoded),
            lessThanOrEqualTo(0),
            reason: 'lower bound of $value');
        expect(
            compareByteArrays(
                encode(ValueBounds.getUpperBound(wrap(value))), encoded),
            greaterThan(0),
            reason: 'upper bound of $value');
        expect(compareByteArrays(encode(ValueBounds.internalMaxValue), encoded),
            greaterThan(0),
            reason: 'max vs $value');
      }
    }
  });

  test('the lower bound of references sorts after every reference in the index',
      () {
    // Same as upstream, a consequence of references having no terminator in
    // the index encoding: the lower bound is the reference without segments,
    // whose value separator (0xffff) sorts after the segment label of any
    // real reference. In memory it sorts first.
    final FieldValue reference = wrap(ref('a/b'));
    final FieldValue lower = ValueBounds.getLowerBound(reference);
    expect(lower.compareTo(reference), lessThan(0));
    expect(compareByteArrays(encode(lower), encode(reference)), greaterThan(0));
    // The upper bound is on the right side.
    expect(
        compareByteArrays(
            encode(ValueBounds.getUpperBound(reference)), encode(reference)),
        greaterThan(0));
  });

  test('the index writer encodes the internal max value', () {
    for (final SegmentKind kind in <SegmentKind>[
      SegmentKind.ascending,
      SegmentKind.descending
    ]) {
      final IndexByteEncoder encoder = IndexByteEncoder();
      FirestoreIndexValueWriter.instance.writeMaxValue(encoder.forKind(kind));
      expect(encode(ValueBounds.internalMaxValue, kind), encoder.encodedBytes);
    }
  });

  test('lowerBoundCompare and upperBoundCompare', () {
    final FieldValue one = wrap(1);
    final FieldValue two = wrap(2);
    expect(ValueBounds.lowerBoundCompare(one, true, two, true), -1);
    expect(ValueBounds.lowerBoundCompare(two, false, one, true), 1);
    // For the same value an inclusive lower bound starts earlier...
    expect(ValueBounds.lowerBoundCompare(one, true, one, false), -1);
    expect(ValueBounds.lowerBoundCompare(one, false, one, true), 1);
    expect(ValueBounds.lowerBoundCompare(one, true, one, true), 0);
    expect(ValueBounds.lowerBoundCompare(one, false, one, false), 0);
    // ...and an inclusive upper bound ends later.
    expect(ValueBounds.upperBoundCompare(one, true, two, true), -1);
    expect(ValueBounds.upperBoundCompare(one, true, one, false), 1);
    expect(ValueBounds.upperBoundCompare(one, false, one, true), -1);
    expect(ValueBounds.upperBoundCompare(one, false, one, false), 0);
  });

  group('Target', () {
    test('getNotInValues returns the equality prefix and the != value', () {
      final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
        'a',
        SegmentKind.ascending,
        'b',
        SegmentKind.ascending,
        'c',
        SegmentKind.ascending
      ]);

      Target target = query('c')
          .filter(filter('a', '==', 'a'))
          .filter(filter('b', '!=', 'b'))
          .toTarget();
      expect(target.getNotInValues(index), <FieldValue>[wrap('a'), wrap('b')]);

      target =
          query('c').filter(filter('a', 'not-in', <Object>[1, 2])).toTarget();
      expect(target.getNotInValues(index), <FieldValue>[
        wrap(<Object>[1, 2])
      ]);

      // No != or not-in filter.
      target = query('c').filter(filter('a', '==', 'a')).toTarget();
      expect(target.getNotInValues(index), isNull);
      // The filter is not on a field of the index.
      target = query('c').filter(filter('z', '!=', 'a')).toTarget();
      expect(target.getNotInValues(index), isNull);
    });

    test('getArrayValues needs an array segment and a matching filter', () {
      final Target target =
          query('c').filter(filter('a', 'array-contains', 1)).toTarget();
      expect(
          target.getArrayValues(fieldIndex('c',
              fieldsAndKinds: <Object>['a', SegmentKind.ascending])),
          isNull);
      expect(
          target.getArrayValues(fieldIndex('c',
              fieldsAndKinds: <Object>['b', SegmentKind.contains])),
          isNull);
    });

    test('segmentCount counts each field once and the array segment apart', () {
      expect(query('c').toTarget().segmentCount, 0);
      expect(
          query('c')
              .filter(filter('a', '>', 1))
              .filter(filter('a', '<', 5))
              .toTarget()
              .segmentCount,
          1);
      expect(
          query('c')
              .filter(filter('a', 'array-contains', 1))
              .orderBy(orderBy('a'))
              .orderBy(orderBy('b', 'desc'))
              .toTarget()
              .segmentCount,
          3);
      // The document key is not a segment.
      expect(
          query('c')
              .filter(filter('__name__', '==', ref('c/doc')))
              .orderBy(orderBy('__name__'))
              .toTarget()
              .segmentCount,
          0);
      // Filters inside composite filters count.
      expect(
          query('c')
              .filter(orFilters(<Filter>[
                filter('a', '==', 1),
                andFilters(<Filter>[filter('b', '==', 2), filter('c', '==', 3)])
              ]))
              .toTarget()
              .segmentCount,
          3);
    });

    test('keyOrder is the direction of the last order by', () {
      expect(query('c').toTarget().keyOrder, OrderByDirection.ascending);
      expect(query('c').orderBy(orderBy('a', 'desc')).toTarget().keyOrder,
          OrderByDirection.descending);
      expect(
          query('c')
              .orderBy(orderBy('a', 'desc'))
              .orderBy(orderBy('__name__'))
              .toTarget()
              .keyOrder,
          OrderByDirection.ascending);
    });
  });
}
