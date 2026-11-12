import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/target_index_matcher.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';

void validateServesTarget(Query query, List<Object> fieldsAndKinds) {
  final FieldIndex expectedIndex =
      fieldIndex('collId', fieldsAndKinds: fieldsAndKinds);
  final TargetIndexMatcher targetIndexMatcher =
      TargetIndexMatcher(query.toTarget());
  expect(targetIndexMatcher.servedByIndex(expectedIndex), isTrue);
}

void validateDoesNotServeTarget(Query query, List<Object> fieldsAndKinds) {
  final FieldIndex expectedIndex =
      fieldIndex('collId', fieldsAndKinds: fieldsAndKinds);
  final TargetIndexMatcher targetIndexMatcher =
      TargetIndexMatcher(query.toTarget());
  expect(targetIndexMatcher.servedByIndex(expectedIndex), isFalse);
}

void validateBuildTargetIndexCreateFullMatchIndex(Query query) {
  final Target target = query.toTarget();
  final TargetIndexMatcher targetIndexMatcher = TargetIndexMatcher(target);
  expect(targetIndexMatcher.hasMultipleInequality, isFalse);
  final FieldIndex? actualIndex = targetIndexMatcher.buildTargetIndex();
  expect(actualIndex, isNotNull);
  expect(targetIndexMatcher.servedByIndex(actualIndex!), isTrue);
  // Check the index created is a FULL MATCH index
  expect(actualIndex.segments.length >= target.segmentCount, isTrue);
}

/// Port of TargetIndexMatcherTest of the Android SDK.
void main() {
  final List<Query> queriesWithEqualities = <Query>[
    query('collId').filter(filter('a', '==', 'a')),
    query('collId').filter(filter('a', 'in', <Object>['a']))
  ];

  final List<Query> queriesWithInequalities = <Query>[
    query('collId').filter(filter('a', '<', 'a')),
    query('collId').filter(filter('a', '<=', 'a')),
    query('collId').filter(filter('a', '>=', 'a')),
    query('collId').filter(filter('a', '>', 'a')),
    query('collId').filter(filter('a', '!=', 'a')),
    query('collId').filter(filter('a', 'not-in', <Object>['a']))
  ];

  final List<Query> queriesWithArrayContains = <Query>[
    query('collId').filter(filter('a', 'array-contains', 'a')),
    query('collId').filter(filter('a', 'array-contains-any', <Object>['a']))
  ];

  final List<Query> queriesWithOrderBys = <Query>[
    query('collId').orderBy(orderBy('a')),
    query('collId').orderBy(orderBy('a', 'desc')),
    query('collId').orderBy(orderBy('a', 'asc')),
    query('collId').orderBy(orderBy('a')).orderBy(orderBy('__name__')),
    query('collId')
        .filter(filter('a', 'array-contains', 'a'))
        .orderBy(orderBy('b'))
  ];

  test('canUseMergeJoin', () {
    Query q = query('collId')
        .filter(filter('a', '==', 1))
        .filter(filter('b', '==', 2));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
    validateServesTarget(q, <Object>['b', SegmentKind.ascending]);

    q = query('collId')
        .filter(filter('a', '==', 1))
        .filter(filter('b', '==', 2))
        .orderBy(orderBy('__name__', 'desc'));
    validateServesTarget(q, <Object>[
      'a',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.descending
    ]);
    validateServesTarget(q, <Object>[
      'b',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.descending
    ]);
  });

  test('canUsePartialIndex', () {
    Query q = query('collId').orderBy(orderBy('a'));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);

    q = query('collId').orderBy(orderBy('a')).orderBy(orderBy('b'));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
    validateServesTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('cannotUsePartialIndexWithMissingArrayContains', () {
    Query q = query('collId')
        .filter(filter('a', 'array-contains', 'a'))
        .orderBy(orderBy('b'));
    validateServesTarget(
        q, <Object>['a', SegmentKind.contains, 'b', SegmentKind.ascending]);

    q = query('collId').orderBy(orderBy('b'));
    validateDoesNotServeTarget(
        q, <Object>['a', SegmentKind.contains, 'b', SegmentKind.ascending]);
  });

  test('cannotUseOverspecifiedIndex', () {
    Query q = query('collId').orderBy(orderBy('a'));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
    validateDoesNotServeTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('equalitiesWithDefaultOrder', () {
    for (final Query q in queriesWithEqualities) {
      validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['b', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('inequalitiesWithDefaultOrder', () {
    for (final Query q in queriesWithInequalities) {
      validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['b', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('inequalityUsesSingleFieldIndex', () {
    Query q = query('collId')
        .filter(filter('a', '>', 1))
        .filter(filter('a', '<', 10));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
  });

  test('inQueryUsesMergeJoin', () {
    Query q = query('collId')
        .filter(filter('a', 'in', <Object>[1, 2]))
        .filter(filter('b', '==', 5));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
    validateServesTarget(q, <Object>['b', SegmentKind.ascending]);
    validateServesTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('withArrayContains', () {
    for (final Query q in queriesWithArrayContains) {
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.ascending]);
      validateServesTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('testArrayContainsIsIndependent', () {
    Query q = query('collId')
        .filter(filter('value', 'array-contains', 'foo'))
        .orderBy(orderBy('value'));
    validateServesTarget(q, <Object>[
      'value',
      SegmentKind.contains,
      'value',
      SegmentKind.ascending
    ]);
    validateServesTarget(q, <Object>[
      'value',
      SegmentKind.ascending,
      'value',
      SegmentKind.contains
    ]);
  });

  test('withArrayContainsAndOrderBy', () {
    Query queriesMultipleFilters = query('collId')
        .filter(filter('a', 'array-contains', 'a'))
        .filter(filter('a', '>', 'b'))
        .orderBy(orderBy('a', 'asc'));
    validateServesTarget(queriesMultipleFilters,
        <Object>['a', SegmentKind.contains, 'a', SegmentKind.ascending]);
  });

  test('withEqualityAndDescendingOrder', () {
    Query q = query('collId')
        .filter(filter('a', '==', 1))
        .orderBy(orderBy('__name__', 'desc'));
    validateServesTarget(q, <Object>[
      'a',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.descending
    ]);
  });

  test('withMultipleEqualities', () {
    Query queriesMultipleFilters = query('collId')
        .filter(filter('a1', '==', 'a'))
        .filter(filter('a2', '==', 'b'));
    validateServesTarget(queriesMultipleFilters,
        <Object>['a1', SegmentKind.ascending, 'a2', SegmentKind.ascending]);
    validateServesTarget(queriesMultipleFilters,
        <Object>['a2', SegmentKind.ascending, 'a1', SegmentKind.ascending]);
    validateDoesNotServeTarget(queriesMultipleFilters, <Object>[
      'a1',
      SegmentKind.ascending,
      'a2',
      SegmentKind.ascending,
      'a3',
      SegmentKind.ascending
    ]);
  });

  test('withMultipleEqualitiesAndInequality', () {
    Query queriesMultipleFilters = query('collId')
        .filter(filter('equality1', '==', 'a'))
        .filter(filter('equality2', '==', 'b'))
        .filter(filter('inequality', '>=', 'c'));
    validateServesTarget(queriesMultipleFilters, <Object>[
      'equality1',
      SegmentKind.ascending,
      'equality2',
      SegmentKind.ascending,
      'inequality',
      SegmentKind.ascending
    ]);
    validateServesTarget(queriesMultipleFilters, <Object>[
      'equality2',
      SegmentKind.ascending,
      'equality1',
      SegmentKind.ascending,
      'inequality',
      SegmentKind.ascending
    ]);
    validateDoesNotServeTarget(queriesMultipleFilters, <Object>[
      'equality2',
      SegmentKind.ascending,
      'inequality',
      SegmentKind.ascending,
      'equality1',
      SegmentKind.ascending
    ]);

    queriesMultipleFilters = query('collId')
        .filter(filter('equality1', '==', 'a'))
        .filter(filter('inequality', '>=', 'c'))
        .filter(filter('equality2', '==', 'b'));
    validateServesTarget(queriesMultipleFilters, <Object>[
      'equality1',
      SegmentKind.ascending,
      'equality2',
      SegmentKind.ascending,
      'inequality',
      SegmentKind.ascending
    ]);
    validateServesTarget(queriesMultipleFilters, <Object>[
      'equality2',
      SegmentKind.ascending,
      'equality1',
      SegmentKind.ascending,
      'inequality',
      SegmentKind.ascending
    ]);
    validateDoesNotServeTarget(queriesMultipleFilters, <Object>[
      'equality1',
      SegmentKind.ascending,
      'inequality',
      SegmentKind.ascending,
      'equality2',
      SegmentKind.ascending
    ]);
  });

  test('withOrderBy', () {
    Query q = query('collId').orderBy(orderBy('a'));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
    validateDoesNotServeTarget(q, <Object>['a', SegmentKind.descending]);

    q = query('collId').orderBy(orderBy('a', 'desc'));
    validateDoesNotServeTarget(q, <Object>['a', SegmentKind.ascending]);
    validateServesTarget(q, <Object>['a', SegmentKind.descending]);

    q = query('collId').orderBy(orderBy('a')).orderBy(orderBy('__name__'));
    validateServesTarget(q, <Object>[
      'a',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.ascending
    ]);
    validateDoesNotServeTarget(q, <Object>[
      'a',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.descending
    ]);
  });

  test('withNotEquals', () {
    Query q = query('collId').filter(filter('a', '!=', 1));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);

    q = query('collId')
        .filter(filter('a', '!=', 1))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'));
    validateServesTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('withMultipleFilters', () {
    Query queriesMultipleFilters = query('collId')
        .filter(filter('a', '==', 'a'))
        .filter(filter('b', '>', 'b'));
    validateServesTarget(
        queriesMultipleFilters, <Object>['a', SegmentKind.ascending]);
    validateServesTarget(queriesMultipleFilters,
        <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('multipleFiltersRequireMatchingPrefix', () {
    Query queriesMultipleFilters = query('collId')
        .filter(filter('a', '==', 'a'))
        .filter(filter('b', '>', 'b'));

    validateServesTarget(
        queriesMultipleFilters, <Object>['b', SegmentKind.ascending]);
    validateDoesNotServeTarget(queriesMultipleFilters,
        <Object>['c', SegmentKind.ascending, 'a', SegmentKind.ascending]);
  });

  test('withMultipleFiltersAndOrderBy', () {
    Query queriesMultipleFilters = query('collId')
        .filter(filter('a1', '==', 'a'))
        .filter(filter('a2', '>', 'b'))
        .orderBy(orderBy('a2', 'asc'));
    validateServesTarget(queriesMultipleFilters,
        <Object>['a1', SegmentKind.ascending, 'a2', SegmentKind.ascending]);
  });

  test('withMultipleInequalities', () {
    Query q = query('collId')
        .filter(filter('a', '>=', 1))
        .filter(filter('a', '==', 5))
        .filter(filter('a', '<=', 10));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
  });

  test('withMultipleNotIn', () {
    Query q = query('collId')
        .filter(filter('a', 'not-in', <Object>[1, 2, 3]))
        .filter(filter('a', '>=', 2));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
  });

  test('withMultipleOrderBys', () {
    Query q = query('collId')
        .orderBy(orderBy('fff'))
        .orderBy(orderBy('bar', 'desc'))
        .orderBy(orderBy('__name__'));
    validateServesTarget(q, <Object>[
      'fff',
      SegmentKind.ascending,
      'bar',
      SegmentKind.descending,
      '__name__',
      SegmentKind.ascending
    ]);
    validateDoesNotServeTarget(q, <Object>[
      'fff',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.ascending,
      'bar',
      SegmentKind.descending
    ]);

    q = query('collId')
        .orderBy(orderBy('foo'))
        .orderBy(orderBy('bar'))
        .orderBy(orderBy('__name__', 'desc'));
    validateServesTarget(q, <Object>[
      'foo',
      SegmentKind.ascending,
      'bar',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.descending
    ]);
    validateDoesNotServeTarget(q, <Object>[
      'foo',
      SegmentKind.ascending,
      '__name__',
      SegmentKind.descending,
      'bar',
      SegmentKind.ascending
    ]);
  });

  test('withInAndNotIn', () {
    Query q = query('collId')
        .filter(filter('a', 'not-in', <Object>[1, 2, 3]))
        .filter(filter('b', 'in', <Object>[1, 2, 3]));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
    validateServesTarget(q, <Object>['b', SegmentKind.ascending]);
    validateServesTarget(
        q, <Object>['b', SegmentKind.ascending, 'a', SegmentKind.ascending]);
    // If provided, equalities have to come first
    validateDoesNotServeTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('withEqualityAndDifferentOrderBy', () {
    Query q = query('collId')
        .filter(filter('foo', '==', ''))
        .filter(filter('bar', '==', ''))
        .orderBy(orderBy('qux'));
    validateServesTarget(q, <Object>[
      'foo',
      SegmentKind.ascending,
      'bar',
      SegmentKind.ascending,
      'qux',
      SegmentKind.ascending
    ]);

    q = query('collId')
        .filter(filter('aaa', '==', ''))
        .filter(filter('qqq', '==', ''))
        .filter(filter('ccc', '==', ''))
        .orderBy(orderBy('fff', 'desc'))
        .orderBy(orderBy('bbb'));
    validateServesTarget(q, <Object>[
      'aaa',
      SegmentKind.ascending,
      'qqq',
      SegmentKind.ascending,
      'ccc',
      SegmentKind.ascending,
      'fff',
      SegmentKind.descending
    ]);
  });

  test('withEqualsAndNotIn', () {
    Query q = query('collId')
        .filter(filter('a', '==', 1))
        .filter(filter('b', 'not-in', <Object>[1, 2, 3]));
    validateServesTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('withInAndOrderBy', () {
    Query q = query('collId')
        .filter(filter('a', 'not-in', <Object>[1, 2, 3]))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'));
    validateServesTarget(
        q, <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);
  });

  test('withInAndOrderBySameField', () {
    Query q = query('collId')
        .filter(filter('a', 'in', <Object>[1, 2, 3]))
        .orderBy(orderBy('a'));
    validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
  });

  test('withEqualityAndInequalityOnTheSameField', () {
    validateServesTarget(
        query('collId')
            .filter(filter('a', '>=', 5))
            .filter(filter('a', '==', 0)),
        <Object>['a', SegmentKind.ascending]);

    validateServesTarget(
        query('collId')
            .filter(filter('a', '>=', 5))
            .filter(filter('a', '==', 0))
            .orderBy(orderBy('a')),
        <Object>['a', SegmentKind.ascending]);

    validateServesTarget(
        query('collId')
            .filter(filter('a', '>=', 5))
            .filter(filter('a', '==', 0))
            .orderBy(orderBy('a'))
            .orderBy(orderBy(DocumentKey.keyFieldName)),
        <Object>['a', SegmentKind.ascending]);

    validateServesTarget(
        query('collId')
            .filter(filter('a', '>=', 5))
            .filter(filter('a', '==', 0))
            .orderBy(orderBy('a'))
            .orderBy(orderBy(DocumentKey.keyFieldName, 'desc')),
        <Object>['a', SegmentKind.ascending]);

    validateServesTarget(
        query('collId')
            .filter(filter('a', '>=', 5))
            .filter(filter('a', '==', 0))
            .orderBy(orderBy('a', 'asc'))
            .orderBy(orderBy('b', 'asc')),
        <Object>['a', SegmentKind.ascending, 'b', SegmentKind.ascending]);

    validateServesTarget(
        query('collId')
            .filter(filter('a', '>=', 5))
            .filter(filter('a', '==', 0))
            .orderBy(orderBy('a', 'desc'))
            .orderBy(orderBy(DocumentKey.keyFieldName, 'desc')),
        <Object>['a', SegmentKind.descending]);
  });

  test('testBuildTargetIndexWithQueriesWithEqualities', () {
    for (final Query q in queriesWithEqualities) {
      validateBuildTargetIndexCreateFullMatchIndex(q);
    }
  });

  test('testBuildTargetIndexWithQueriesWithInequalities', () {
    for (final Query q in queriesWithInequalities) {
      validateBuildTargetIndexCreateFullMatchIndex(q);
    }
  });

  test('testBuildTargetIndexWithQueriesWithArrayContains', () {
    for (final Query q in queriesWithArrayContains) {
      validateBuildTargetIndexCreateFullMatchIndex(q);
    }
  });

  test('testBuildTargetIndexWithQueriesWithOrderBys', () {
    for (final Query q in queriesWithOrderBys) {
      validateBuildTargetIndexCreateFullMatchIndex(q);
    }
  });

  test('testBuildTargetIndexWithInequalityUsesSingleFieldIndex', () {
    Query q = query('collId')
        .filter(filter('a', '>', 1))
        .filter(filter('a', '<', 10));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithCollection', () {
    Query q = query('collId');
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithArrayContainsAndOrderBy', () {
    Query q = query('collId')
        .filter(filter('a', 'array-contains', 'a'))
        .filter(filter('a', '>', 'b'))
        .orderBy(orderBy('a', 'asc'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithEqualityAndDescendingOrder', () {
    Query q = query('collId')
        .filter(filter('a', '==', 1))
        .orderBy(orderBy('__name__', 'desc'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithMultipleEqualities', () {
    Query q = query('collId')
        .filter(filter('a1', '==', 'a'))
        .filter(filter('a2', '==', 'b'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithMultipleEqualitiesAndInequality', () {
    Query q = query('collId')
        .filter(filter('equality1', '==', 'a'))
        .filter(filter('equality2', '==', 'b'))
        .filter(filter('inequality', '>=', 'c'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
    q = query('collId')
        .filter(filter('equality1', '==', 'a'))
        .filter(filter('inequality', '>=', 'c'))
        .filter(filter('equality2', '==', 'b'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithMultipleFilters', () {
    Query q = query('collId')
        .filter(filter('a', '==', 'a'))
        .filter(filter('b', '>', 'b'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
    q = query('collId')
        .filter(filter('a1', '==', 'a'))
        .filter(filter('a2', '>', 'b'))
        .orderBy(orderBy('a2', 'asc'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
    q = query('collId')
        .filter(filter('a', '>=', 1))
        .filter(filter('a', '==', 5))
        .filter(filter('a', '<=', 10));
    validateBuildTargetIndexCreateFullMatchIndex(q);
    q = query('collId')
        .filter(filter('a', 'not-in', <Object>[1, 2, 3]))
        .filter(filter('a', '>=', 2));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithMultipleOrderBys', () {
    Query q = query('collId')
        .orderBy(orderBy('fff'))
        .orderBy(orderBy('bar', 'desc'))
        .orderBy(orderBy('__name__'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
    q = query('collId')
        .orderBy(orderBy('foo'))
        .orderBy(orderBy('bar'))
        .orderBy(orderBy('__name__', 'desc'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithInAndNotIn', () {
    Query q = query('collId')
        .filter(filter('a', 'not-in', <Object>[1, 2, 3]))
        .filter(filter('b', 'in', <Object>[1, 2, 3]));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithEqualityAndDifferentOrderBy', () {
    Query q = query('collId')
        .filter(filter('foo', '==', ''))
        .filter(filter('bar', '==', ''))
        .orderBy(orderBy('qux'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
    q = query('collId')
        .filter(filter('aaa', '==', ''))
        .filter(filter('qqq', '==', ''))
        .filter(filter('ccc', '==', ''))
        .orderBy(orderBy('fff', 'desc'))
        .orderBy(orderBy('bbb'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithEqualsAndNotIn', () {
    Query q = query('collId')
        .filter(filter('a', '==', 1))
        .filter(filter('b', 'not-in', <Object>[1, 2, 3]));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithInAndOrderBy', () {
    Query q = query('collId')
        .filter(filter('a', 'not-in', <Object>[1, 2, 3]))
        .orderBy(orderBy('a'))
        .orderBy(orderBy('b'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('testBuildTargetIndexWithInAndOrderBySameField', () {
    Query q = query('collId')
        .filter(filter('a', 'in', <Object>[1, 2, 3]))
        .orderBy(orderBy('a'));
    validateBuildTargetIndexCreateFullMatchIndex(q);
  });

  test('equalitiesWithAscendingOrder', () {
    for (final Query q in queriesWithEqualities
        .map((Query e) => e.orderBy(orderBy('a', 'asc')))) {
      validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['b', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('equalitiesWithDescendingOrder', () {
    for (final Query q in queriesWithEqualities
        .map((Query e) => e.orderBy(orderBy('a', 'desc')))) {
      validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['b', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('inequalitiesWithAscendingOrder', () {
    for (final Query q in queriesWithInequalities
        .map((Query e) => e.orderBy(orderBy('a', 'asc')))) {
      validateServesTarget(q, <Object>['a', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['b', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('inequalitiesWithDescendingOrder', () {
    for (final Query q in queriesWithInequalities
        .map((Query e) => e.orderBy(orderBy('a', 'desc')))) {
      validateServesTarget(q, <Object>['a', SegmentKind.descending]);
      validateDoesNotServeTarget(q, <Object>['b', SegmentKind.ascending]);
      validateDoesNotServeTarget(q, <Object>['a', SegmentKind.contains]);
    }
  });

  test('validatesCollection', () {
    {
      final TargetIndexMatcher targetIndexMatcher =
          TargetIndexMatcher(query('collId').toTarget());
      final FieldIndex index = fieldIndex('collId');
      expect(() => targetIndexMatcher.servedByIndex(index), returnsNormally);
    }

    {
      final TargetIndexMatcher targetIndexMatcher = TargetIndexMatcher(
          Query(ResourcePath.empty, collectionGroup: 'collId').toTarget());
      final FieldIndex index = fieldIndex('collId');
      expect(() => targetIndexMatcher.servedByIndex(index), returnsNormally);
    }

    {
      final TargetIndexMatcher targetIndexMatcher =
          TargetIndexMatcher(query('collId2').toTarget());
      final FieldIndex index = fieldIndex('collId');
      expect(
          () => targetIndexMatcher.servedByIndex(index),
          throwsA(isA<AssertionError>().having((AssertionError e) => e.message,
              'message', 'Collection IDs do not match')));
    }
  });

  test('testBuildTargetIndexReturnsNullForMultipleInequality', () {
    final Query q = query('collId')
        .filter(filter('a', '>=', 1))
        .filter(filter('b', '<=', 10));
    final Target target = q.toTarget();
    final TargetIndexMatcher targetIndexMatcher = TargetIndexMatcher(target);
    expect(targetIndexMatcher.hasMultipleInequality, isTrue);
    final FieldIndex? actualIndex = targetIndexMatcher.buildTargetIndex();
    expect(actualIndex, isNull);
  });
}
