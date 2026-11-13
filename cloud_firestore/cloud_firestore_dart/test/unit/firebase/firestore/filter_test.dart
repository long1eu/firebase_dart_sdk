// Ported from the Android SDK's FilterTest (src/test, package root). Java's
// Filter.x(FieldPath, value) overloads are the xField(FieldPath, value)
// methods here.

import 'package:cloud_firestore_dart/src/firebase/firestore/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:test/test.dart';

void main() {
  test('equalTo', () {
    final Filter filter = Filter.equalTo('x', 'v');
    expect(filter, filter);
    expect(filter, Filter.equalToField(FieldPath.of(<String>['x']), 'v'));
    expect(filter, isNot(Filter.equalTo('x', 'z')));
    expect(filter, isNot(Filter.equalTo('y', 'v')));
    expect(filter, isNot(Filter.notEqualTo('x', 'v')));
  });

  test('notEqualTo', () {
    final Filter filter = Filter.notEqualTo('x', 'v');
    expect(filter, filter);
    expect(filter, Filter.notEqualToField(FieldPath.of(<String>['x']), 'v'));
    expect(filter, isNot(Filter.notEqualTo('x', 'z')));
    expect(filter, isNot(Filter.notEqualTo('y', 'v')));
    expect(filter, isNot(Filter.equalTo('x', 'v')));
  });

  test('greaterThan', () {
    final Filter filter = Filter.greaterThan('x', 'v');
    expect(filter, filter);
    expect(filter, Filter.greaterThanField(FieldPath.of(<String>['x']), 'v'));
    expect(filter, isNot(Filter.greaterThan('x', 'z')));
    expect(filter, isNot(Filter.greaterThan('y', 'v')));
    expect(filter, isNot(Filter.lessThan('x', 'v')));
  });

  test('greaterThanOrEqualTo', () {
    final Filter filter = Filter.greaterThanOrEqualTo('x', 'v');
    expect(filter, filter);
    expect(
      filter,
      Filter.greaterThanOrEqualToField(FieldPath.of(<String>['x']), 'v'),
    );
    expect(filter, isNot(Filter.greaterThanOrEqualTo('x', 'z')));
    expect(filter, isNot(Filter.greaterThanOrEqualTo('y', 'v')));
    expect(filter, isNot(Filter.lessThanOrEqualTo('x', 'v')));
  });

  test('lessThan', () {
    final Filter filter = Filter.lessThan('x', 'v');
    expect(filter, filter);
    expect(filter, Filter.lessThanField(FieldPath.of(<String>['x']), 'v'));
    expect(filter, isNot(Filter.lessThan('x', 'z')));
    expect(filter, isNot(Filter.lessThan('y', 'v')));
    expect(filter, isNot(Filter.greaterThan('x', 'v')));
  });

  test('lessThanOrEqualTo', () {
    final Filter filter = Filter.lessThanOrEqualTo('x', 'v');
    expect(filter, filter);
    expect(
      filter,
      Filter.lessThanOrEqualToField(FieldPath.of(<String>['x']), 'v'),
    );
    expect(filter, isNot(Filter.lessThanOrEqualTo('x', 'z')));
    expect(filter, isNot(Filter.lessThanOrEqualTo('y', 'v')));
    expect(filter, isNot(Filter.greaterThanOrEqualTo('x', 'v')));
  });

  test('arrayContains', () {
    final Filter filter = Filter.arrayContains('x', 'v');
    expect(filter, filter);
    expect(filter, Filter.arrayContainsField(FieldPath.of(<String>['x']), 'v'));
    expect(filter, isNot(Filter.arrayContains('x', 'z')));
    expect(filter, isNot(Filter.arrayContains('y', 'v')));
    expect(filter, isNot(Filter.equalTo('x', 'v')));
  });

  test('arrayContainsAny', () {
    final Filter filter = Filter.arrayContainsAny('x', <Object?>['v1', 'v2']);
    expect(filter, filter);
    expect(
      filter,
      Filter.arrayContainsAnyField(FieldPath.of(<String>['x']), <Object?>[
        'v1',
        'v2',
      ]),
    );
    expect(filter, isNot(Filter.arrayContainsAny('x', <Object?>['v2', 'v1'])));
    expect(filter, isNot(Filter.arrayContainsAny('x', <Object?>['v2', 'v3'])));
    expect(filter, isNot(Filter.arrayContainsAny('y', <Object?>['v1', 'v2'])));
    expect(filter, isNot(Filter.equalTo('x', 'v')));
  });

  test('inArray', () {
    final Filter filter = Filter.inArray('x', <Object?>['v1', 'v2']);
    expect(filter, filter);
    expect(
      filter,
      Filter.inArrayField(FieldPath.of(<String>['x']), <Object?>['v1', 'v2']),
    );
    expect(filter, isNot(Filter.inArray('x', <Object?>['v2', 'v1'])));
    expect(filter, isNot(Filter.inArray('x', <Object?>['v2', 'v3'])));
    expect(filter, isNot(Filter.inArray('y', <Object?>['v1', 'v2'])));
    expect(filter, isNot(Filter.notInArray('x', <Object?>['v1', 'v2'])));
  });

  test('notInArray', () {
    final Filter filter = Filter.notInArray('x', <Object?>['v1', 'v2']);
    expect(filter, filter);
    expect(
      filter,
      Filter.notInArrayField(FieldPath.of(<String>['x']), <Object?>[
        'v1',
        'v2',
      ]),
    );
    expect(filter, isNot(Filter.notInArray('x', <Object?>['v2', 'v1'])));
    expect(filter, isNot(Filter.notInArray('x', <Object?>['v2', 'v3'])));
    expect(filter, isNot(Filter.notInArray('y', <Object?>['v1', 'v2'])));
    expect(filter, isNot(Filter.inArray('x', <Object?>['v1', 'v2'])));
  });

  test('or', () {
    final Filter filter = Filter.or(<Filter>[
      Filter.inArray('x', <Object?>['v1', 'v2']),
      Filter.inArray('y', <Object?>['v3', 'v4']),
    ]);
    expect(
      filter,
      Filter.or(<Filter>[
        Filter.inArrayField(FieldPath.of(<String>['x']), <Object?>['v1', 'v2']),
        Filter.inArrayField(FieldPath.of(<String>['y']), <Object?>['v3', 'v4']),
      ]),
    );
    expect(
      filter,
      isNot(
        Filter.and(<Filter>[
          Filter.inArray('x', <Object?>['v1', 'v2']),
          Filter.inArray('y', <Object?>['v3', 'v4']),
        ]),
      ),
    );
    expect(
      filter,
      isNot(
        Filter.or(<Filter>[
          Filter.inArray('y', <Object?>['v3', 'v4']),
          Filter.inArray('x', <Object?>['v1', 'v2']),
        ]),
      ),
    );
  });

  test('and', () {
    final Filter filter = Filter.and(<Filter>[
      Filter.inArray('x', <Object?>['v1', 'v2']),
      Filter.inArray('y', <Object?>['v3', 'v4']),
    ]);
    expect(
      filter,
      Filter.and(<Filter>[
        Filter.inArrayField(FieldPath.of(<String>['x']), <Object?>['v1', 'v2']),
        Filter.inArrayField(FieldPath.of(<String>['y']), <Object?>['v3', 'v4']),
      ]),
    );
    expect(
      filter,
      isNot(
        Filter.or(<Filter>[
          Filter.inArray('x', <Object?>['v1', 'v2']),
          Filter.inArray('y', <Object?>['v3', 'v4']),
        ]),
      ),
    );
    expect(
      filter,
      isNot(
        Filter.and(<Filter>[
          Filter.inArray('y', <Object?>['v3', 'v4']),
          Filter.inArray('x', <Object?>['v1', 'v2']),
        ]),
      ),
    );
  });
}
