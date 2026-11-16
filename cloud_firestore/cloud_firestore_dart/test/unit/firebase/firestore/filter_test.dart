// Ported from the Android SDK's FilterTest (src/test, package root). Java's
// Filter.x(FieldPath, value) overloads are the xField(FieldPath, value)
// methods here.

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:test/test.dart';

void main() {
  test('equalTo', () {
    final Filter filter = Filter('x', isEqualTo: 'v');
    expect(filter, filter);
    expect(filter, Filter(FieldPath(<String>['x']), isEqualTo: 'v'));
    expect(filter, isNot(Filter('x', isEqualTo: 'z')));
    expect(filter, isNot(Filter('y', isEqualTo: 'v')));
    expect(filter, isNot(Filter('x', isNotEqualTo: 'v')));
  });

  test('notEqualTo', () {
    final Filter filter = Filter('x', isNotEqualTo: 'v');
    expect(filter, filter);
    expect(filter, Filter(FieldPath(<String>['x']), isNotEqualTo: 'v'));
    expect(filter, isNot(Filter('x', isNotEqualTo: 'z')));
    expect(filter, isNot(Filter('y', isNotEqualTo: 'v')));
    expect(filter, isNot(Filter('x', isEqualTo: 'v')));
  });

  test('greaterThan', () {
    final Filter filter = Filter('x', isGreaterThan: 'v');
    expect(filter, filter);
    expect(filter, Filter(FieldPath(<String>['x']), isGreaterThan: 'v'));
    expect(filter, isNot(Filter('x', isGreaterThan: 'z')));
    expect(filter, isNot(Filter('y', isGreaterThan: 'v')));
    expect(filter, isNot(Filter('x', isLessThan: 'v')));
  });

  test('greaterThanOrEqualTo', () {
    final Filter filter = Filter('x', isGreaterThanOrEqualTo: 'v');
    expect(filter, filter);
    expect(
      filter,
      Filter(FieldPath(<String>['x']), isGreaterThanOrEqualTo: 'v'),
    );
    expect(filter, isNot(Filter('x', isGreaterThanOrEqualTo: 'z')));
    expect(filter, isNot(Filter('y', isGreaterThanOrEqualTo: 'v')));
    expect(filter, isNot(Filter('x', isLessThanOrEqualTo: 'v')));
  });

  test('lessThan', () {
    final Filter filter = Filter('x', isLessThan: 'v');
    expect(filter, filter);
    expect(filter, Filter(FieldPath(<String>['x']), isLessThan: 'v'));
    expect(filter, isNot(Filter('x', isLessThan: 'z')));
    expect(filter, isNot(Filter('y', isLessThan: 'v')));
    expect(filter, isNot(Filter('x', isGreaterThan: 'v')));
  });

  test('lessThanOrEqualTo', () {
    final Filter filter = Filter('x', isLessThanOrEqualTo: 'v');
    expect(filter, filter);
    expect(filter, Filter(FieldPath(<String>['x']), isLessThanOrEqualTo: 'v'));
    expect(filter, isNot(Filter('x', isLessThanOrEqualTo: 'z')));
    expect(filter, isNot(Filter('y', isLessThanOrEqualTo: 'v')));
    expect(filter, isNot(Filter('x', isGreaterThanOrEqualTo: 'v')));
  });

  test('arrayContains', () {
    final Filter filter = Filter('x', arrayContains: 'v');
    expect(filter, filter);
    expect(filter, Filter(FieldPath(<String>['x']), arrayContains: 'v'));
    expect(filter, isNot(Filter('x', arrayContains: 'z')));
    expect(filter, isNot(Filter('y', arrayContains: 'v')));
    expect(filter, isNot(Filter('x', isEqualTo: 'v')));
  });

  test('arrayContainsAny', () {
    final Filter filter = Filter('x', arrayContainsAny: <Object?>['v1', 'v2']);
    expect(filter, filter);
    expect(
      filter,
      Filter(FieldPath(<String>['x']), arrayContainsAny: <Object?>['v1', 'v2']),
    );
    expect(filter, isNot(Filter('x', arrayContainsAny: <Object?>['v2', 'v1'])));
    expect(filter, isNot(Filter('x', arrayContainsAny: <Object?>['v2', 'v3'])));
    expect(filter, isNot(Filter('y', arrayContainsAny: <Object?>['v1', 'v2'])));
    expect(filter, isNot(Filter('x', isEqualTo: 'v')));
  });

  test('inArray', () {
    final Filter filter = Filter('x', whereIn: <Object?>['v1', 'v2']);
    expect(filter, filter);
    expect(
      filter,
      Filter(FieldPath(<String>['x']), whereIn: <Object?>['v1', 'v2']),
    );
    expect(filter, isNot(Filter('x', whereIn: <Object?>['v2', 'v1'])));
    expect(filter, isNot(Filter('x', whereIn: <Object?>['v2', 'v3'])));
    expect(filter, isNot(Filter('y', whereIn: <Object?>['v1', 'v2'])));
    expect(filter, isNot(Filter('x', whereNotIn: <Object?>['v1', 'v2'])));
  });

  test('notInArray', () {
    final Filter filter = Filter('x', whereNotIn: <Object?>['v1', 'v2']);
    expect(filter, filter);
    expect(
      filter,
      Filter(FieldPath(<String>['x']), whereNotIn: <Object?>['v1', 'v2']),
    );
    expect(filter, isNot(Filter('x', whereNotIn: <Object?>['v2', 'v1'])));
    expect(filter, isNot(Filter('x', whereNotIn: <Object?>['v2', 'v3'])));
    expect(filter, isNot(Filter('y', whereNotIn: <Object?>['v1', 'v2'])));
    expect(filter, isNot(Filter('x', whereIn: <Object?>['v1', 'v2'])));
  });

  test('or', () {
    final Filter filter = Filter.or(<Filter>[
      Filter('x', whereIn: <Object?>['v1', 'v2']),
      Filter('y', whereIn: <Object?>['v3', 'v4']),
    ]);
    expect(
      filter,
      Filter.or(<Filter>[
        Filter(FieldPath(<String>['x']), whereIn: <Object?>['v1', 'v2']),
        Filter(FieldPath(<String>['y']), whereIn: <Object?>['v3', 'v4']),
      ]),
    );
    expect(
      filter,
      isNot(
        Filter.and(<Filter>[
          Filter('x', whereIn: <Object?>['v1', 'v2']),
          Filter('y', whereIn: <Object?>['v3', 'v4']),
        ]),
      ),
    );
    expect(
      filter,
      isNot(
        Filter.or(<Filter>[
          Filter('y', whereIn: <Object?>['v3', 'v4']),
          Filter('x', whereIn: <Object?>['v1', 'v2']),
        ]),
      ),
    );
  });

  test('and', () {
    final Filter filter = Filter.and(<Filter>[
      Filter('x', whereIn: <Object?>['v1', 'v2']),
      Filter('y', whereIn: <Object?>['v3', 'v4']),
    ]);
    expect(
      filter,
      Filter.and(<Filter>[
        Filter(FieldPath(<String>['x']), whereIn: <Object?>['v1', 'v2']),
        Filter(FieldPath(<String>['y']), whereIn: <Object?>['v3', 'v4']),
      ]),
    );
    expect(
      filter,
      isNot(
        Filter.or(<Filter>[
          Filter('x', whereIn: <Object?>['v1', 'v2']),
          Filter('y', whereIn: <Object?>['v3', 'v4']),
        ]),
      ),
    );
    expect(
      filter,
      isNot(
        Filter.and(<Filter>[
          Filter('y', whereIn: <Object?>['v3', 'v4']),
          Filter('x', whereIn: <Object?>['v1', 'v2']),
        ]),
      ),
    );
  });
}
