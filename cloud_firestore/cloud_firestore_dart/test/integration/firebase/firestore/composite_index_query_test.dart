// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

// Port of the upstream CompositeIndexQueryTest. Upstream runs these in a shared production collection with predefined
// composite indexes (and a per test id filter); the emulator needs no indexes, so every test here uses a fresh
// collection instead of the CompositeIndexTestHelper.
void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/composite_index_query';

  setUp(IntegrationTestUtil.testFirestore);

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<CollectionReference> withTestDocs(
          Map<String, Map<String, Object?>> docs) =>
      IntegrationTestUtil.testCollectionWithDocs(docs);

  void expectIds(QuerySnapshot snapshot, List<String> expectedIds) {
    expect(IntegrationTestUtil.querySnapshotToIds(snapshot), expectedIds);
  }

  Future<void> assertOnlineAndOfflineResultsMatch(
      CollectionReference collection, Query query, List<String> expected) {
    return IntegrationTestUtil.checkOnlineAndOfflineResultsMatch(
        collection, query, expected);
  }

  final Map<String, Map<String, Object?>> books =
      <String, Map<String, Object?>>{
    'a': <String, Object?>{
      'author': 'authorA',
      'title': 'titleA',
      'pages': 100,
      'year': 1980,
      'rating': 5.0,
    },
    'b': <String, Object?>{
      'author': 'authorB',
      'title': 'titleB',
      'pages': 50,
      'year': 2020,
      'rating': 4.0,
    },
  };

  test('testOrQueriesWithCompositeIndexes', () async {
    final CollectionReference collection =
        await withTestDocs(<String, Map<String, Object?>>{
      'doc1': <String, Object?>{'a': 1, 'b': 0},
      'doc2': <String, Object?>{'a': 2, 'b': 1},
      'doc3': <String, Object?>{'a': 3, 'b': 2},
      'doc4': <String, Object?>{'a': 1, 'b': 3},
      'doc5': <String, Object?>{'a': 1, 'b': 1},
    });

    // With one inequality: a>2 || b==1.
    Query query = collection.where(Filter.or(<Filter>[
      Filter.greaterThan('a', 2),
      Filter.equalTo('b', 1),
    ]));
    await assertOnlineAndOfflineResultsMatch(
        collection, query, <String>['doc5', 'doc2', 'doc3']);

    // With limit (implicit order by ASC): (a==1) || (b > 0) LIMIT 2
    query = collection
        .where(Filter.or(<Filter>[
          Filter.equalTo('a', 1),
          Filter.greaterThan('b', 0),
        ]))
        .limit(2);
    await assertOnlineAndOfflineResultsMatch(
        collection, query, <String>['doc1', 'doc2']);

    // With limit (explicit order by): (a==1) || (b > 0) LIMIT_TO_LAST 2
    query = collection
        .where(Filter.or(<Filter>[
          Filter.equalTo('a', 1),
          Filter.greaterThan('b', 0),
        ]))
        .limitToLast(2)
        .orderBy('b');
    await assertOnlineAndOfflineResultsMatch(
        collection, query, <String>['doc3', 'doc4']);

    // With limit (explicit order by ASC): (a==2) || (b == 1) ORDER BY a LIMIT 1
    query = collection
        .where(Filter.or(<Filter>[
          Filter.equalTo('a', 2),
          Filter.equalTo('b', 1),
        ]))
        .limit(1)
        .orderBy('a');
    await assertOnlineAndOfflineResultsMatch(
        collection, query, <String>['doc5']);

    // With limit (explicit order by DESC): (a==2) || (b == 1) ORDER BY a LIMIT_TO_LAST 1
    query = collection
        .where(Filter.or(<Filter>[
          Filter.equalTo('a', 2),
          Filter.equalTo('b', 1),
        ]))
        .limitToLast(1)
        .orderBy('a');
    await assertOnlineAndOfflineResultsMatch(
        collection, query, <String>['doc2']);
  });

  test('testCanRunAggregateCollectionGroupQuery', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    final String group = 'b${db.collection('foo').document().id}';
    final List<String> docPaths = <String>[
      r'abc/123/${collectionGroup}/cg-doc1',
      r'abc/123/${collectionGroup}/cg-doc2',
      r'${collectionGroup}/cg-doc3',
      r'${collectionGroup}/cg-doc4',
      r'def/456/${collectionGroup}/cg-doc5',
      r'${collectionGroup}/virtual-doc/nested-coll/not-cg-doc',
      r'x${collectionGroup}/not-cg-doc',
      r'${collectionGroup}x/not-cg-doc',
      r'abc/123/${collectionGroup}x/not-cg-doc',
      r'abc/123/x${collectionGroup}/not-cg-doc',
      r'abc/${collectionGroup}',
    ];
    final WriteBatch batch = db.batch();
    for (final String path in docPaths) {
      batch.set(db.document(path.replaceAll(r'${collectionGroup}', group)),
          <String, Object?>{'a': 2});
    }
    await batch.commit();

    final AggregateQuerySnapshot snapshot =
        await db.collectionGroup(group).aggregate(<AggregateField>[
      AggregateField.count(),
      AggregateField.sum('a'),
      AggregateField.average('a'),
    ]).get(AggregateSource.server);
    // cg-doc1 .. cg-doc5.
    expect(snapshot.get(AggregateField.count()), 5);
    expect(snapshot.get(AggregateField.sum('a')), 10);
    expect(snapshot.get(AggregateField.average('a')), 2.0);
  });

  test('testCanPerformMaxAggregations', () async {
    final CollectionReference collection = await withTestDocs(books);

    final AggregateField f1 = AggregateField.sum('pages');
    final AggregateField f2 = AggregateField.average('pages');
    final AggregateField f3 = AggregateField.count();
    final AggregateField f4 = AggregateField.sum('year');
    final AggregateField f5 = AggregateField.average('rating');

    final AggregateQuerySnapshot snapshot = await collection.aggregate(
        <AggregateField>[f1, f2, f3, f4, f5]).get(AggregateSource.server);

    expect(snapshot.get(f1), 150);
    expect(snapshot.get(f2), 75.0);
    expect(snapshot.get(f3), 2);
    expect(snapshot.get(f4), 4000);
    expect(snapshot.get(f5), 4.5);
  });

  test('testCanGetCorrectTypeForSum', () async {
    final CollectionReference collection = await withTestDocs(books);

    final AggregateQuerySnapshot snapshot =
        await collection.aggregate(<AggregateField>[
      AggregateField.sum('pages'),
      AggregateField.sum('year'),
      AggregateField.sum('rating'),
    ]).get(AggregateSource.server);

    expect(snapshot.get(AggregateField.sum('pages')), isA<int>());
    expect(snapshot.get(AggregateField.sum('year')), isA<int>());
    expect(snapshot.get(AggregateField.sum('rating')), isA<double>());
  });

  test('testPerformsAggregationWhenUsingArrayContainsAnyOperator',
      skip: IntegrationTestUtil.skipOnEnterprise(
          'the sum over no documents is null instead of 0'), () async {
    final CollectionReference collection =
        await withTestDocs(<String, Map<String, Object?>>{
      'a': <String, Object?>{
        'author': 'authorA',
        'title': 'titleA',
        'pages': 100,
        'year': 1980,
        'rating': <int>[5, 1000],
      },
      'b': <String, Object?>{
        'author': 'authorB',
        'title': 'titleB',
        'pages': 50,
        'year': 2020,
        'rating': <int>[4],
      },
      'c': <String, Object?>{
        'author': 'authorC',
        'title': 'titleC',
        'pages': 100,
        'year': 1980,
        'rating': <int>[2222, 3],
      },
      'd': <String, Object?>{
        'author': 'authorD',
        'title': 'titleD',
        'pages': 50,
        'year': 2020,
        'rating': <int>[0],
      },
    });

    final AggregateQuerySnapshot snapshot = await collection
        .whereArrayContainsAny(
            'rating', <Object?>[5, 3]).aggregate(<AggregateField>[
      AggregateField.sum('rating'),
      AggregateField.average('rating'),
      AggregateField.sum('pages'),
      AggregateField.average('pages'),
      AggregateField.count(),
    ]).get(AggregateSource.server);

    expect(snapshot.get(AggregateField.sum('rating')), 0);
    expect(snapshot.get(AggregateField.average('rating')), isNull);
    expect(snapshot.get(AggregateField.sum('pages')), 200);
    expect(snapshot.get(AggregateField.average('pages')), 100.0);
    expect(snapshot.get(AggregateField.count()), 2);
  });

  group('Multiple inequality', () {
    test('testMultipleInequalityOnDifferentFields', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 0, 'v': 0},
        'doc2': <String, Object?>{'key': 'b', 'sort': 3, 'v': 1},
        'doc3': <String, Object?>{'key': 'c', 'sort': 1, 'v': 3},
        'doc4': <String, Object?>{'key': 'd', 'sort': 2, 'v': 2},
      });

      QuerySnapshot snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .whereGreaterThan('v', 2)
          .get();
      expectIds(snapshot, <String>['doc3']);

      // Duplicate inequality fields.
      snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .whereGreaterThan('sort', 1)
          .get();
      expectIds(snapshot, <String>['doc4']);

      // With multiple IN.
      snapshot = await collection
          .whereGreaterThanOrEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .whereIn('v', <Object?>[2, 3, 4]).whereIn(
              'sort', <Object?>[2, 3]).get();
      expectIds(snapshot, <String>['doc4']);

      // With NOT-IN.
      snapshot = await collection
          .whereGreaterThanOrEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .whereNotIn('v', <Object?>[2, 4, 5]).get();
      expectIds(snapshot, <String>['doc1', 'doc3']);

      // With orderBy.
      snapshot = await collection
          .whereGreaterThanOrEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .orderBy('v', Direction.descending)
          .get();
      expectIds(snapshot, <String>['doc3', 'doc4', 'doc1']);

      // With limit.
      snapshot = await collection
          .whereGreaterThanOrEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .orderBy('v', Direction.descending)
          .limit(2)
          .get();
      expectIds(snapshot, <String>['doc3', 'doc4']);

      // With limitToLast.
      snapshot = await collection
          .whereGreaterThanOrEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .orderBy('v', Direction.descending)
          .limitToLast(2)
          .get();
      expectIds(snapshot, <String>['doc4', 'doc1']);
    });

    test('testMultipleInequalityOnSpecialValues', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 0, 'v': 0},
        'doc2': <String, Object?>{'key': 'b', 'sort': double.nan, 'v': 1},
        'doc3': <String, Object?>{'key': 'c', 'sort': null, 'v': 3},
        'doc4': <String, Object?>{'key': 'd', 'v': 2},
        'doc5': <String, Object?>{'key': 'e', 'sort': 0},
        'doc6': <String, Object?>{'key': 'f', 'sort': 1, 'v': 1},
      });

      QuerySnapshot snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .get();
      expectIds(snapshot, <String>['doc5', 'doc6']);

      snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 2)
          .whereLessThanOrEqualTo('v', 1)
          .get();
      expectIds(snapshot, <String>['doc6']);
    });

    test('testMultipleInequalityWithArrayMembership', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{
          'key': 'a',
          'sort': 0,
          'v': <int>[0]
        },
        'doc2': <String, Object?>{
          'key': 'b',
          'sort': 1,
          'v': <int>[0, 1, 3]
        },
        'doc3': <String, Object?>{'key': 'c', 'sort': 1, 'v': <int>[]},
        'doc4': <String, Object?>{
          'key': 'd',
          'sort': 2,
          'v': <int>[1]
        },
        'doc5': <String, Object?>{
          'key': 'e',
          'sort': 3,
          'v': <int>[2, 4]
        },
        'doc6': <String, Object?>{
          'key': 'f',
          'sort': 4,
          'v': <double>[double.nan]
        },
        'doc7': <String, Object?>{
          'key': 'g',
          'sort': 4,
          'v': <Object?>[null]
        },
      });

      QuerySnapshot snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1)
          .whereArrayContains('v', 0)
          .get();
      expectIds(snapshot, <String>['doc2']);

      snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1)
          .whereArrayContainsAny('v', <Object?>[0, 1]).get();
      expectIds(snapshot, <String>['doc2', 'doc4']);
    });

    Map<String, Object?> nestedObject(int number) => <String, Object?>{
          'name': 'room $number',
          'metadata': <String, Object?>{'createdAt': number},
          'field': 'field $number',
          'field.dot': number,
          r'field\slash': number,
        };

    test('testMultipleInequalityWithNestedField', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': nestedObject(400),
        'doc2': nestedObject(200),
        'doc3': nestedObject(100),
        'doc4': nestedObject(300),
      });

      QuerySnapshot snapshot = await collection
          .whereLessThanOrEqualTo('metadata.createdAt', 500)
          .whereGreaterThan('metadata.createdAt', 100)
          .whereNotEqualTo('name', 'room 200')
          .orderBy('name')
          .get();
      expectIds(snapshot, <String>['doc4', 'doc1']);

      snapshot = await collection
          .whereGreaterThanOrEqualTo('field', 'field 100')
          .whereNotEqualToField(FieldPath.of(<String>['field.dot']), 300)
          .whereLessThan(r'field\slash', 400)
          .orderBy('name', Direction.descending)
          .get();
      expectIds(snapshot, <String>['doc2', 'doc3']);
    });

    test('testMultipleInequalityWithCompositeFilters', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 0, 'v': 5},
        'doc2': <String, Object?>{'key': 'aa', 'sort': 4, 'v': 4},
        'doc3': <String, Object?>{'key': 'c', 'sort': 3, 'v': 3},
        'doc4': <String, Object?>{'key': 'b', 'sort': 2, 'v': 2},
        'doc5': <String, Object?>{'key': 'b', 'sort': 2, 'v': 1},
        'doc6': <String, Object?>{'key': 'b', 'sort': 0, 'v': 0},
      });

      final Filter filter = Filter.or(<Filter>[
        Filter.and(<Filter>[
          Filter.equalTo('key', 'b'),
          Filter.lessThanOrEqualTo('sort', 2),
        ]),
        Filter.and(<Filter>[
          Filter.notEqualTo('key', 'b'),
          Filter.greaterThan('v', 4),
        ]),
      ]);

      QuerySnapshot snapshot = await collection.where(filter).get();
      // Implicitly ordered by: 'key' asc, 'sort' asc, 'v' asc, __name__ asc.
      expectIds(snapshot, <String>['doc1', 'doc6', 'doc5', 'doc4']);

      snapshot = await collection
          .where(filter)
          .orderBy('sort', Direction.descending)
          .orderBy('key')
          .get();
      // Ordered by: 'sort' desc, 'key' asc, 'v' asc, __name__ asc.
      expectIds(snapshot, <String>['doc5', 'doc4', 'doc1', 'doc6']);

      snapshot = await collection
          .where(Filter.and(<Filter>[
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.equalTo('key', 'b'),
                Filter.lessThanOrEqualTo('sort', 4),
              ]),
              Filter.and(<Filter>[
                Filter.notEqualTo('key', 'b'),
                Filter.greaterThanOrEqualTo('v', 4),
              ]),
            ]),
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.greaterThan('key', 'b'),
                Filter.greaterThanOrEqualTo('sort', 1),
              ]),
              Filter.and(<Filter>[
                Filter.lessThan('key', 'b'),
                Filter.greaterThan('v', 0),
              ]),
            ]),
          ]))
          .get();
      // Implicitly ordered by: 'key' asc, 'sort' asc, 'v' asc, __name__ asc.
      expectIds(snapshot, <String>['doc1', 'doc2']);
    });

    test('testMultipleInequalityFieldsWillBeImplicitlyOrderedLexicographically',
        () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 0, 'v': 5},
        'doc2': <String, Object?>{'key': 'aa', 'sort': 4, 'v': 4},
        'doc3': <String, Object?>{'key': 'b', 'sort': 3, 'v': 3},
        'doc4': <String, Object?>{'key': 'b', 'sort': 2, 'v': 2},
        'doc5': <String, Object?>{'key': 'b', 'sort': 2, 'v': 1},
        'doc6': <String, Object?>{'key': 'b', 'sort': 0, 'v': 0},
      });

      QuerySnapshot snapshot = await collection
          .whereNotEqualTo('key', 'a')
          .whereGreaterThan('sort', 1)
          .whereIn('v', <Object?>[1, 2, 3, 4]).get();
      // Implicitly ordered by: 'key' asc, 'sort' asc, __name__ asc.
      expectIds(snapshot, <String>['doc2', 'doc4', 'doc5', 'doc3']);

      snapshot = await collection
          .whereGreaterThan('sort', 1)
          .whereNotEqualTo('key', 'a')
          .whereIn('v', <Object?>[1, 2, 3, 4]).get();
      expectIds(snapshot, <String>['doc2', 'doc4', 'doc5', 'doc3']);
    });

    test('testMultipleInequalityWithMultipleExplicitOrderBy', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 5, 'v': 0},
        'doc2': <String, Object?>{'key': 'aa', 'sort': 4, 'v': 0},
        'doc3': <String, Object?>{'key': 'b', 'sort': 3, 'v': 1},
        'doc4': <String, Object?>{'key': 'b', 'sort': 2, 'v': 1},
        'doc5': <String, Object?>{'key': 'bb', 'sort': 1, 'v': 1},
        'doc6': <String, Object?>{'key': 'c', 'sort': 0, 'v': 2},
      });

      Query base() => collection
          .whereGreaterThan('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1);

      QuerySnapshot snapshot = await base().orderBy('v').get();
      // Ordered by: 'v' asc, 'key' asc, 'sort' asc, __name__ asc.
      expectIds(snapshot, <String>['doc2', 'doc4', 'doc3', 'doc5']);

      snapshot = await base().orderBy('v').orderBy('sort').get();
      // Ordered by: 'v' asc, 'sort' asc, 'key' asc, __name__ asc.
      expectIds(snapshot, <String>['doc2', 'doc5', 'doc4', 'doc3']);

      snapshot = await base().orderBy('v', Direction.descending).get();
      // The implicit order by matches the direction of the last explicit order by.
      // Ordered by: 'v' desc, 'key' desc, 'sort' desc, __name__ desc.
      expectIds(snapshot, <String>['doc5', 'doc3', 'doc4', 'doc2']);

      snapshot =
          await base().orderBy('v', Direction.descending).orderBy('sort').get();
      // Ordered by: 'v' desc, 'sort' asc, 'key' asc, __name__ asc.
      expectIds(snapshot, <String>['doc5', 'doc4', 'doc3', 'doc2']);
    });

    test('testMultipleInequalityInAggregateQuery', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 5, 'v': 0},
        'doc2': <String, Object?>{'key': 'aa', 'sort': 4, 'v': 0},
        'doc3': <String, Object?>{'key': 'b', 'sort': 3, 'v': 1},
        'doc4': <String, Object?>{'key': 'b', 'sort': 2, 'v': 1},
        'doc5': <String, Object?>{'key': 'bb', 'sort': 1, 'v': 1},
      });

      final AggregateQuerySnapshot snapshot1 = await collection
          .whereGreaterThan('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1)
          .orderBy('v')
          .count()
          .get(AggregateSource.server);
      expect(snapshot1.get(AggregateField.count()), 4);

      final AggregateQuerySnapshot snapshot2 = await collection
          .whereGreaterThan('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1)
          .whereNotEqualTo('v', 0)
          .aggregate(<AggregateField>[
        AggregateField.count(),
        AggregateField.sum('sort'),
        AggregateField.average('v'),
      ]).get(AggregateSource.server);
      expect(snapshot2.get(AggregateField.count()), 3);
      expect(snapshot2.get(AggregateField.sum('sort')), 6);
      expect(snapshot2.get(AggregateField.average('v')), 1.0);
    });

    test('testMultipleInequalityFieldsWithDocumentKey', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 5},
        'doc2': <String, Object?>{'key': 'aa', 'sort': 4},
        'doc3': <String, Object?>{'key': 'b', 'sort': 3},
        'doc4': <String, Object?>{'key': 'b', 'sort': 2},
        'doc5': <String, Object?>{'key': 'bb', 'sort': 1},
      });

      QuerySnapshot snapshot = await collection
          .whereGreaterThan('sort', 1)
          .whereNotEqualTo('key', 'a')
          .whereLessThanField(FieldPath.documentId(), 'doc5')
          .get();
      // The document key in an inequality is implicitly ordered last.
      // Implicitly ordered by: 'key' asc, 'sort' asc, __name__ asc.
      expectIds(snapshot, <String>['doc2', 'doc4', 'doc3']);

      snapshot = await collection
          .whereLessThanField(FieldPath.documentId(), 'doc5')
          .whereGreaterThan('sort', 1)
          .whereNotEqualTo('key', 'a')
          .get();
      // Changing the order of the filters does not change the implicit order.
      expectIds(snapshot, <String>['doc2', 'doc4', 'doc3']);

      snapshot = await collection
          .whereLessThanField(FieldPath.documentId(), 'doc5')
          .whereGreaterThan('sort', 1)
          .whereNotEqualTo('key', 'a')
          .orderBy('sort', Direction.descending)
          .get();
      // Ordered by: 'sort' desc, 'key' desc, __name__ desc.
      expectIds(snapshot, <String>['doc2', 'doc3', 'doc4']);
    });

    test('testMultipleInequalityReadFromCacheWhenOffline', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 'a', 'sort': 1},
        'doc2': <String, Object?>{'key': 'aa', 'sort': 4},
        'doc3': <String, Object?>{'key': 'b', 'sort': 3},
        'doc4': <String, Object?>{'key': 'b', 'sort': 2},
      });

      final Query query = collection
          .whereNotEqualTo('key', 'a')
          .whereLessThanOrEqualTo('sort', 3);

      // Populate the cache.
      final QuerySnapshot snapshot1 = await query.get();
      expect(snapshot1.documents.length, 2);
      expect(snapshot1.metadata.isFromCache, isFalse);

      await collection.firestore.disableNetwork();

      final QuerySnapshot snapshot2 = await query.get();
      expect(snapshot2.documents.length, 2);
      expect(snapshot2.metadata.isFromCache, isTrue);
      // Implicitly ordered by: 'key' asc, 'sort' asc, __name__ asc.
      expectIds(snapshot2, <String>['doc4', 'doc3']);
    });

    test('testMultipleInequalityFromCacheAndFromServer', () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1, 'b': 0},
        'doc2': <String, Object?>{'a': 2, 'b': 1},
        'doc3': <String, Object?>{'a': 3, 'b': 2},
        'doc4': <String, Object?>{'a': 1, 'b': 3},
        'doc5': <String, Object?>{'a': 1, 'b': 1},
      });

      // Implicit AND: a != 1 && b < 2.
      await assertOnlineAndOfflineResultsMatch(
          collection,
          collection.whereNotEqualTo('a', 1).whereLessThan('b', 2),
          <String>['doc2']);

      // Explicit AND: a != 1 && b < 2.
      await assertOnlineAndOfflineResultsMatch(
          collection,
          collection.where(Filter.and(<Filter>[
            Filter.notEqualTo('a', 1),
            Filter.lessThan('b', 2),
          ])),
          <String>['doc2']);

      // Explicit AND: a < 3 && b not-in [2, 3], implicitly ordered by: a asc, b asc, __name__ asc.
      await assertOnlineAndOfflineResultsMatch(
          collection,
          collection.where(Filter.and(<Filter>[
            Filter.lessThan('a', 3),
            Filter.notInArray('b', <Object?>[2, 3]),
          ])),
          <String>['doc1', 'doc5', 'doc2']);

      // a < 3 && b != 0, ordered by: b desc, a desc, __name__ desc.
      await assertOnlineAndOfflineResultsMatch(
          collection,
          collection
              .whereLessThan('a', 3)
              .whereNotEqualTo('b', 0)
              .orderBy('b', Direction.descending)
              .limit(2),
          <String>['doc4', 'doc2']);

      // Explicit OR: a > 2 || b < 1.
      await assertOnlineAndOfflineResultsMatch(
          collection,
          collection.where(Filter.or(<Filter>[
            Filter.greaterThan('a', 2),
            Filter.lessThan('b', 1),
          ])),
          <String>['doc1', 'doc3']);
    });

    test('testMultipleInequalityRejectsIfDocumentKeyIsNotTheLastOrderByField',
        () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 1}
      });

      // Implicitly ordered by: __name__ asc, 'key' asc.
      final Query query = collection
          .whereNotEqualTo('key', 42)
          .orderByField(FieldPath.documentId());
      await expectLater(
          query.get(),
          throwsA(isA<FirestoreError>().having(
              (FirestoreError e) => e.message.toLowerCase(),
              'message',
              contains(
                  'order by clause cannot contain more fields after the key'))));
    });

    test(
        'testMultipleInequalityRejectsIfDocumentKeyAppearsOnlyInEqualityFilter',
        () async {
      final CollectionReference collection =
          await withTestDocs(<String, Map<String, Object?>>{
        'doc1': <String, Object?>{'key': 1}
      });

      final Query query = collection
          .whereNotEqualTo('key', 42)
          .whereEqualToField(FieldPath.documentId(), 'doc1');
      await expectLater(
          query.get(),
          throwsA(isA<FirestoreError>().having(
              (FirestoreError e) => e.message,
              'message',
              contains(
                  'Equality on key is not allowed if there are other inequality fields and key does not appear in inequalities.'))));
    });
  });
}
