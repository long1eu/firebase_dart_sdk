import 'package:cloud_firestore_dart/src/firebase/firestore/core/bound.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

/// The comparison cases of target.test.ts of the JS SDK, which run each filter against an ascending and a descending
/// index; Android's TargetTest (target_index_bounds_test.dart) has one direction per filter.
void main() {
  void verifyBound(Bound bound, bool inclusive, Object? value) {
    expect(bound.inclusive, inclusive, reason: 'inclusive');
    final List<FieldValue> position = bound.position;
    expect(position, hasLength(1));
    expect(position[0], wrap(value));
  }

  // (operator, direction, lower bound inclusive, lower value, upper bound inclusive, upper value)
  for (final (
        String op,
        SegmentKind kind,
        bool lowerIn,
        Object? lower,
        bool upperIn,
        Object? upper,
      )
      in <(String, SegmentKind, bool, Object?, bool, Object?)>[
        ('==', SegmentKind.ascending, true, 'bar', true, 'bar'),
        ('==', SegmentKind.descending, true, 'bar', true, 'bar'),
        ('<', SegmentKind.ascending, true, '', false, 'bar'),
        ('<', SegmentKind.descending, false, 'bar', true, ''),
        ('<=', SegmentKind.ascending, true, '', true, 'bar'),
        ('<=', SegmentKind.descending, true, 'bar', true, ''),
        ('>', SegmentKind.ascending, false, 'bar', false, blob()),
        ('>', SegmentKind.descending, false, blob(), false, 'bar'),
        ('>=', SegmentKind.ascending, true, 'bar', false, blob()),
        ('>=', SegmentKind.descending, false, blob(), true, 'bar'),
      ]) {
    test("'$op' query with ${kind.name} index", () {
      final Target target = query(
        'c',
      ).filter(filter('foo', op, 'bar')).toTarget();
      final FieldIndex index = fieldIndex(
        'c',
        fieldsAndKinds: <Object>['foo', kind],
      );

      verifyBound(target.getLowerBound(index), lowerIn, lower);
      verifyBound(target.getUpperBound(index), upperIn, upper);
    });
  }
}
