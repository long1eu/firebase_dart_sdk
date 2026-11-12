import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';
import 'package:test/test.dart';

import '../../../../util/core_helpers.dart';
import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

void verifyBound(Bound bound, bool inclusive,
    [List<Object?> values = const <Object?>[]]) {
  expect(bound.inclusive, inclusive, reason: 'inclusive');
  final List<FieldValue> position = bound.position;
  expect(position.length, values.length, reason: 'size');
  for (int i = 0; i < values.length; ++i) {
    final FieldValue expectedValue = wrap(values[i]);
    expect(position[i], expectedValue,
        reason: 'Values should be equal: Expected: $expectedValue, '
            'Actual: ${position[i]}');
  }
}

/// Port of the index bound cases of TargetTest of the Android SDK.
void main() {
  test('emptyQueryBound', () {
    final Target target = query('c').toTarget();
    final FieldIndex index = fieldIndex('c');

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true);
  });

  test('equalsQueryBound', () {
    final Target target =
        query('c').filter(filter('foo', '==', 'bar')).toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['bar']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['bar']);
  });

  test('lessThanQueryBound', () {
    final Target target =
        query('c').filter(filter('foo', '<', 'bar')).toTarget();
    final FieldIndex index = fieldIndex('c',
        fieldsAndKinds: <Object>['foo', SegmentKind.descending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, false, <Object?>['bar']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['']);
  });

  test('lessThanOrEqualsQueryBound', () {
    final Target target =
        query('c').filter(filter('foo', '<=', 'bar')).toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['bar']);
  });

  test('greaterThanQueryBound', () {
    final Target target =
        query('c').filter(filter('foo', '>', 'bar')).toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, false, <Object?>['bar']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, false, <Object?>[blob()]);
  });

  test('greaterThanOrEqualsQueryBound', () {
    final Target target =
        query('c').filter(filter('foo', '>=', 'bar')).toTarget();
    final FieldIndex index = fieldIndex('c',
        fieldsAndKinds: <Object>['foo', SegmentKind.descending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, false, <Object?>[blob()]);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['bar']);
  });

  test('arrayContainsQueryBound', () {
    final Target target =
        query('c').filter(filter('foo', 'array-contains', 'bar')).toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.contains]);

    expect(target.getArrayValues(index), <FieldValue>[wrap('bar')]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true);
  });

  test('arrayContainsAnyQueryBound', () {
    final Target target = query('c')
        .filter(filter('foo', 'array-contains-any', <Object>['bar', 'baz']))
        .toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.contains]);

    expect(
        target.getArrayValues(index), <FieldValue>[wrap('bar'), wrap('baz')]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true);
  });

  test('orderByQueryBound', () {
    final Target target = query('c').orderBy(orderBy('foo')).toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    expect(lowerBound.position.length, 1);
    expect(lowerBound.position[0], ValueBounds.internalMinValue);
    expect(lowerBound.inclusive, isTrue);

    final Bound upperBound = target.getUpperBound(index);
    expect(upperBound.position.length, 1);
    expect(upperBound.position[0], ValueBounds.internalMaxValue);
    expect(upperBound.inclusive, isTrue);
  });

  test('filterWithOrderByQueryBound', () {
    final Target target = query('c')
        .filter(filter('foo', '>', 'bar'))
        .orderBy(orderBy('foo'))
        .toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, false, <Object?>['bar']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, false, <Object?>[blob()]);
  });

  test('startAtQueryBound', () {
    final Target target = query('c')
        .orderBy(orderBy('foo'))
        .startAt(bound(true, <Object>['bar']))
        .toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['bar']);

    final Bound upperBound = target.getUpperBound(index);
    expect(upperBound.position.length, 1);
    expect(upperBound.position[0], ValueBounds.internalMaxValue);
    expect(upperBound.inclusive, isTrue);
  });

  test('startAtWithFilterQueryBound', () {
    // Tests that the startAt and the filter get merged to form a narrow bound
    final Target target = query('c')
        .filter(filter('a', '>=', 'a1'))
        .filter(filter('b', '==', 'b1'))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'))
        .startAt(bound(true, <Object>['a1', 'b1']))
        .toTarget();
    final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.ascending
    ]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['a1', 'b1']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, false, <Object?>[blob(), 'b1']);
  });

  test('startAfterWithFilterQueryBound', () {
    final Target target = query('c')
        .filter(filter('a', '>=', 'a1'))
        .filter(filter('b', '==', 'b1'))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'))
        .startAt(bound(false, <Object>['a2', 'b1']))
        .toTarget();
    final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.ascending
    ]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, false, <Object?>['a2', 'b1']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, false, <Object?>[blob(), 'b1']);
  });

  test('startAfterDoesNotChangeBoundIfNotApplicable', () {
    final Target target = query('c')
        .filter(filter('a', '>=', 'a2'))
        .filter(filter('b', '==', 'b2'))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'))
        .startAt(bound(false, <Object>['a1', 'b1']))
        .toTarget();
    final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.ascending
    ]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['a2', 'b2']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, false, <Object?>[blob(), 'b2']);
  });

  test('endAtQueryBound', () {
    final Target target = query('c')
        .orderBy(orderBy('foo'))
        .endAt(bound(true, <Object>['bar']))
        .toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['foo', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    expect(lowerBound.position.length, 1);
    expect(lowerBound.position[0], ValueBounds.internalMinValue);
    expect(lowerBound.inclusive, isTrue);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['bar']);
  });

  test('endAtWithFilterQueryBound', () {
    // Tests that the endAt and the filter get merged to form a narrow bound
    final Target target = query('c')
        .filter(filter('a', '<=', 'a2'))
        .filter(filter('b', '==', 'b2'))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'))
        .endAt(bound(true, <Object>['a1', 'b1']))
        .toTarget();
    final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.ascending
    ]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['', 'b2']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['a1', 'b1']);
  });

  test('endBeforeWithFilterQueryBound', () {
    final Target target = query('c')
        .filter(filter('a', '<=', 'a2'))
        .filter(filter('b', '==', 'b2'))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'))
        .endAt(bound(false, <Object>['a1', 'b1']))
        .toTarget();
    final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.ascending
    ]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['', 'b2']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, false, <Object?>['a1', 'b1']);
  });

  test('endBeforeDoesNotChangeBoundIfNotApplicable', () {
    final Target target = query('c')
        .filter(filter('a', '<=', 'a1'))
        .filter(filter('b', '==', 'b1'))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'))
        .endAt(bound(false, <Object>['a2', 'b2']))
        .toTarget();
    final FieldIndex index = fieldIndex('c', fieldsAndKinds: <Object>[
      'a',
      SegmentKind.ascending,
      'b',
      SegmentKind.ascending
    ]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['', 'b1']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['a1', 'b1']);
  });

  test('partialIndexMatchQueryBound', () {
    final Target target = query('c')
        .filter(filter('a', '==', 'a'))
        .filter(filter('b', '==', 'b'))
        .toTarget();
    final FieldIndex index =
        fieldIndex('c', fieldsAndKinds: <Object>['a', SegmentKind.ascending]);

    final Bound lowerBound = target.getLowerBound(index);
    verifyBound(lowerBound, true, <Object?>['a']);

    final Bound upperBound = target.getUpperBound(index);
    verifyBound(upperBound, true, <Object?>['a']);
  });
}
