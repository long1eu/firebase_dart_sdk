// Copyright 2023 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/filter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/source.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

// NOTE: the OR queries and multiple inequality filters sent by these tests
// need a backend that supports them. Support in the Firestore emulator is
// unverified (older emulator versions reject them), and in production the
// queries with several inequality fields (or an inequality inside an OR) need
// a composite index; the tests with multiple inequalities say which one. These
// tests are modelled on upstream's QueryTest (OR queries), ValidationTest and
// CompositeIndexQueryTest.

typedef Docs = Map<String, Map<String, Object?>>;

const testFirestore = IntegrationTestUtil.testFirestore;
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;
const querySnapshotToIds = IntegrationTestUtil.querySnapshotToIds;

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/or_query';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  /// Checks that the results of the backend and the local (cache) evaluation
  /// of [query] agree and are [expected], in order.
  Future<void> checkOnlineAndOfflineResultsMatch(
    Query query,
    List<String> expected,
  ) async {
    final QuerySnapshot server = await query.get(Source.server);
    expect(querySnapshotToIds(server), expected, reason: 'server');
    final QuerySnapshot cache = await query.get(Source.cache);
    expect(querySnapshotToIds(cache), expected, reason: 'cache');
  }

  test('testOrQueries', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1, 'b': 0},
        'doc2': <String, Object?>{'a': 2, 'b': 1},
        'doc3': <String, Object?>{'a': 3, 'b': 2},
        'doc4': <String, Object?>{'a': 1, 'b': 3},
        'doc5': <String, Object?>{'a': 1, 'b': 1},
      },
    );

    // Two equalities: a==1 || b==1.
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[Filter.equalTo('a', 1), Filter.equalTo('b', 1)]),
      ),
      <String>['doc1', 'doc2', 'doc4', 'doc5'],
    );

    // (a==1 && b==0) || (a==3 && b==2)
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.and(<Filter>[Filter.equalTo('a', 1), Filter.equalTo('b', 0)]),
          Filter.and(<Filter>[Filter.equalTo('a', 3), Filter.equalTo('b', 2)]),
        ]),
      ),
      <String>['doc1', 'doc3'],
    );

    // a==1 && (b==0 || b==3).
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.and(<Filter>[
          Filter.equalTo('a', 1),
          Filter.or(<Filter>[Filter.equalTo('b', 0), Filter.equalTo('b', 3)]),
        ]),
      ),
      <String>['doc1', 'doc4'],
    );

    // (a==2 || b==2) && (a==3 || b==3)
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.and(<Filter>[
          Filter.or(<Filter>[Filter.equalTo('a', 2), Filter.equalTo('b', 2)]),
          Filter.or(<Filter>[Filter.equalTo('a', 3), Filter.equalTo('b', 3)]),
        ]),
      ),
      <String>['doc3'],
    );

    // With a limit and without an orderBy (__name__ is the tie breaker).
    await checkOnlineAndOfflineResultsMatch(
      collection
          .where(
            Filter.or(<Filter>[Filter.equalTo('a', 2), Filter.equalTo('b', 1)]),
          )
          .limit(1),
      <String>['doc2'],
    );
  });

  test('testOrQueriesWithIn', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1, 'b': 0},
        'doc2': <String, Object?>{'b': 1},
        'doc3': <String, Object?>{'a': 3, 'b': 2},
        'doc4': <String, Object?>{'a': 1, 'b': 3},
        'doc5': <String, Object?>{'a': 1},
        'doc6': <String, Object?>{'a': 2},
      },
    );

    // a==2 || b in [2,3]
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.equalTo('a', 2),
          Filter.inArray('b', <int>[2, 3]),
        ]),
      ),
      <String>['doc3', 'doc4', 'doc6'],
    );
  });

  test('testOrQueriesWithArrayMembership', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{
          'a': 1,
          'b': <int>[0],
        },
        'doc2': <String, Object?>{
          'b': <int>[1],
        },
        'doc3': <String, Object?>{
          'a': 3,
          'b': <int>[2, 7],
        },
        'doc4': <String, Object?>{
          'a': 1,
          'b': <int>[3, 7],
        },
        'doc5': <String, Object?>{'a': 1},
        'doc6': <String, Object?>{'a': 2},
      },
    );

    // a==2 || b array-contains 7
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.equalTo('a', 2),
          Filter.arrayContains('b', 7),
        ]),
      ),
      <String>['doc3', 'doc4', 'doc6'],
    );

    // a==2 || b array-contains-any [0, 3]
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.equalTo('a', 2),
          Filter.arrayContainsAny('b', <int>[0, 3]),
        ]),
      ),
      <String>['doc1', 'doc4', 'doc6'],
    );
  });

  test('testMultipleInOps', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1, 'b': 0},
        'doc2': <String, Object?>{'b': 1},
        'doc3': <String, Object?>{'a': 3, 'b': 2},
        'doc4': <String, Object?>{'a': 1, 'b': 3},
        'doc5': <String, Object?>{'a': 1},
        'doc6': <String, Object?>{'a': 2},
      },
    );

    // Two IN operations on different fields with disjunction.
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.inArray('a', <int>[2, 3]),
          Filter.inArray('b', <int>[0, 2]),
        ]),
      ),
      <String>['doc1', 'doc3', 'doc6'],
    );

    // Two IN operations on the same field with disjunction.
    // a IN [0,3] || a IN [0,2] should union them (similar to: a IN [0,2,3]).
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.inArray('a', <int>[0, 3]),
          Filter.inArray('a', <int>[0, 2]),
        ]),
      ),
      <String>['doc3', 'doc6'],
    );

    // Two IN operations in a conjunction (not an OR query).
    await checkOnlineAndOfflineResultsMatch(
      collection.whereIn('a', <int>[1, 3]).whereIn('b', <int>[0, 2]),
      <String>['doc1', 'doc3'],
    );
  });

  test('testUsingInWithArrayContainsAny', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{
          'a': 1,
          'b': <int>[0],
        },
        'doc2': <String, Object?>{
          'b': <int>[1],
        },
        'doc3': <String, Object?>{
          'a': 3,
          'b': <int>[2, 7],
          'c': 10,
        },
        'doc4': <String, Object?>{
          'a': 1,
          'b': <int>[3, 7],
        },
        'doc5': <String, Object?>{'a': 1},
        'doc6': <String, Object?>{'a': 2, 'c': 20},
      },
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.inArray('a', <int>[2, 3]),
          Filter.arrayContainsAny('b', <int>[0, 7]),
        ]),
      ),
      <String>['doc1', 'doc3', 'doc4', 'doc6'],
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.and(<Filter>[
            Filter.inArray('a', <int>[2, 3]),
            Filter.equalTo('c', 10),
          ]),
          Filter.arrayContainsAny('b', <int>[0, 7]),
        ]),
      ),
      <String>['doc1', 'doc3', 'doc4'],
    );
  });

  test('testUsingInWithArrayContains', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{
          'a': 1,
          'b': <int>[0],
        },
        'doc2': <String, Object?>{
          'b': <int>[1],
        },
        'doc3': <String, Object?>{
          'a': 3,
          'b': <int>[2, 7],
        },
        'doc4': <String, Object?>{
          'a': 1,
          'b': <int>[3, 7],
        },
        'doc5': <String, Object?>{'a': 1},
        'doc6': <String, Object?>{'a': 2},
      },
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.inArray('a', <int>[2, 3]),
          Filter.arrayContains('b', 3),
        ]),
      ),
      <String>['doc3', 'doc4', 'doc6'],
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.and(<Filter>[
          Filter.inArray('a', <int>[2, 3]),
          Filter.arrayContains('b', 7),
        ]),
      ),
      <String>['doc3'],
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.or(<Filter>[
          Filter.inArray('a', <int>[2, 3]),
          Filter.and(<Filter>[
            Filter.arrayContains('b', 3),
            Filter.equalTo('a', 1),
          ]),
        ]),
      ),
      <String>['doc3', 'doc4', 'doc6'],
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.and(<Filter>[
          Filter.inArray('a', <int>[2, 3]),
          Filter.or(<Filter>[
            Filter.arrayContains('b', 7),
            Filter.equalTo('a', 1),
          ]),
        ]),
      ),
      <String>['doc3'],
    );
  });

  test('testOrderByEquality', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{
          'a': 1,
          'b': <int>[0],
        },
        'doc2': <String, Object?>{
          'b': <int>[1],
        },
        'doc3': <String, Object?>{
          'a': 3,
          'b': <int>[2, 7],
          'c': 10,
        },
        'doc4': <String, Object?>{
          'a': 1,
          'b': <int>[3, 7],
        },
        'doc5': <String, Object?>{'a': 1},
        'doc6': <String, Object?>{'a': 2, 'c': 20},
      },
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(Filter.equalTo('a', 1)).orderBy('a'),
      <String>['doc1', 'doc4', 'doc5'],
    );

    await checkOnlineAndOfflineResultsMatch(
      collection.where(Filter.inArray('a', <int>[2, 3])).orderBy('a'),
      <String>['doc6', 'doc3'],
    );
  });

  test(
    'testOrQueryWithAnInequalityOrdersImplicitlyAndRequiresTheField',
    () async {
      final CollectionReference collection = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'doc1': <String, Object?>{'a': 1, 'b': 0},
          'doc2': <String, Object?>{'a': 2, 'b': 1},
          'doc3': <String, Object?>{'a': 3, 'b': 2},
          'doc4': <String, Object?>{'b': 1},
        },
      );

      // a>1 || b==1 has an implicit "orderBy a": doc4 matches the filter but has
      // no value for a, so it is not returned.
      await checkOnlineAndOfflineResultsMatch(
        collection.where(
          Filter.or(<Filter>[
            Filter.greaterThan('a', 1),
            Filter.equalTo('b', 1),
          ]),
        ),
        <String>['doc2', 'doc3'],
      );
    },
  );

  test('testOrQueryListenerSeesLocalWrites', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1},
        'doc2': <String, Object?>{'a': 2},
      },
    );
    final Query query = collection.where(
      Filter.or(<Filter>[Filter.equalTo('a', 1), Filter.equalTo('a', 3)]),
    );

    final StreamIterator<QuerySnapshot> snapshots =
        StreamIterator<QuerySnapshot>(query.getSnapshots());

    Future<void> waitForIds(List<String> ids) async {
      while (await snapshots.moveNext()) {
        if (querySnapshotToIds(snapshots.current).join(',') == ids.join(',')) {
          return;
        }
      }
      fail('The listener closed before it saw $ids');
    }

    await waitForIds(<String>['doc1']);
    await collection.document('doc2').set(<String, Object?>{'a': 3});
    await waitForIds(<String>['doc1', 'doc2']);
    await snapshots.cancel();
  });

  test('testCountWithOrFilter', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1, 'b': 0},
        'doc2': <String, Object?>{'a': 2, 'b': 1},
        'doc3': <String, Object?>{'a': 3, 'b': 2},
      },
    );
    final AggregateQuerySnapshot count = await collection
        .where(
          Filter.or(<Filter>[Filter.equalTo('a', 1), Filter.equalTo('b', 2)]),
        )
        .count()
        .get();
    expect(count.getCount(), 2);
  });

  // ---------------------------------------------------------------------------
  // Multiple inequality filters (production needs a composite index for the
  // queries below; the emulator does not enforce indexes). Modelled on upstream
  // CompositeIndexQueryTest.
  // ---------------------------------------------------------------------------

  Docs multiInequalityDocs() => <String, Map<String, Object?>>{
    'doc1': <String, Object?>{'key': 'a', 'sort': 0, 'v': 5},
    'doc2': <String, Object?>{'key': 'aa', 'sort': 4, 'v': 4},
    'doc3': <String, Object?>{'key': 'c', 'sort': 3, 'v': 3},
    'doc4': <String, Object?>{'key': 'b', 'sort': 2, 'v': 2},
    'doc5': <String, Object?>{'key': 'b', 'sort': 2, 'v': 1},
    'doc6': <String, Object?>{'key': 'b', 'sort': 0, 'v': 0},
  };

  test('testMultipleInequalityOnDifferentFields', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      multiInequalityDocs(),
    );

    // Implicitly ordered by: key asc, sort asc, v asc, __name__ asc. Needs a
    // composite index in production.
    await checkOnlineAndOfflineResultsMatch(
      collection
          .whereGreaterThan('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1)
          .whereLessThan('v', 5),
      <String>['doc2', 'doc5', 'doc4', 'doc3'],
    );

    // Explicit orderBy: sort DESC first, then the implicit key and v.
    await checkOnlineAndOfflineResultsMatch(
      collection
          .whereGreaterThan('key', 'a')
          .whereGreaterThanOrEqualTo('sort', 1)
          .whereLessThan('v', 5)
          .orderBy('sort', Direction.descending),
      <String>['doc2', 'doc3', 'doc4', 'doc5'],
    );
  });

  test('testMultipleInequalityWithCompositeFilters', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      multiInequalityDocs(),
    );

    final Query query = collection.where(
      Filter.or(<Filter>[
        Filter.and(<Filter>[
          Filter.equalTo('key', 'b'),
          Filter.lessThanOrEqualTo('sort', 2),
        ]),
        Filter.and(<Filter>[
          Filter.notEqualTo('key', 'b'),
          Filter.greaterThan('v', 4),
        ]),
      ]),
    );
    // Implicitly ordered by: key asc, sort asc, v asc, __name__ asc.
    await checkOnlineAndOfflineResultsMatch(query, <String>[
      'doc1',
      'doc6',
      'doc5',
      'doc4',
    ]);

    // Ordered by: sort desc, key asc, v asc, __name__ asc.
    await checkOnlineAndOfflineResultsMatch(
      query.orderBy('sort', Direction.descending).orderBy('key'),
      <String>['doc5', 'doc4', 'doc1', 'doc6'],
    );
  });

  test(
    'testMultipleInequalityFieldsAreImplicitlyOrderedLexicographically',
    () async {
      final CollectionReference collection = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'doc1': <String, Object?>{'a': 0, 'b': 5, 'c': 5, 'd': 0},
          'doc2': <String, Object?>{'a': 1, 'b': 4, 'c': 4, 'd': 1},
          'doc3': <String, Object?>{'a': 2, 'b': 3, 'c': 3, 'd': 2},
          'doc4': <String, Object?>{'a': 3, 'b': 2, 'c': 2, 'd': 3},
        },
      );

      // Implicitly ordered by: a asc, b asc, c asc, __name__ asc.
      await checkOnlineAndOfflineResultsMatch(
        collection
            .whereGreaterThan('c', 2)
            .whereGreaterThan('b', 2)
            .whereLessThan('a', 3),
        <String>['doc1', 'doc2', 'doc3'],
      );
    },
  );

  test('testMultipleInequalityReadFromCacheWhenOffline', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      multiInequalityDocs(),
    );
    final Firestore firestore = collection.firestore;

    final Query query = collection
        .whereNotEqualTo('key', 'a')
        .whereLessThanOrEqualTo('sort', 3)
        .whereGreaterThan('v', 0);
    final QuerySnapshot server = await query.get();
    final List<String> onlineIds = querySnapshotToIds(server);

    await IntegrationTestUtil.disableNetwork(firestore);
    final QuerySnapshot cached = await query.get();
    expect(cached.metadata.isFromCache, isTrue);
    expect(querySnapshotToIds(cached), onlineIds);
    await IntegrationTestUtil.enableNetwork(firestore);
  });
  // JS query.test.ts "can use query overloads" (OR Queries): the same filters,
  // limits and orders, combined in different ways.
  test('can use query overloads', () async {
    final CollectionReference collection = await testCollectionWithDocs(
      <String, Map<String, Object?>>{
        'doc1': <String, Object?>{'a': 1, 'b': 0},
        'doc2': <String, Object?>{'a': 2, 'b': 1},
        'doc3': <String, Object?>{'a': 3, 'b': 2},
        'doc4': <String, Object?>{'a': 1, 'b': 3},
        'doc5': <String, Object?>{'a': 1, 'b': 1},
      },
    );

    // a == 1
    await checkOnlineAndOfflineResultsMatch(
      collection.whereEqualTo('a', 1),
      <String>['doc1', 'doc4', 'doc5'],
    );

    // Implicit AND: a == 1 && b == 3
    await checkOnlineAndOfflineResultsMatch(
      collection.whereEqualTo('a', 1).whereEqualTo('b', 3),
      <String>['doc4'],
    );

    // Explicit AND: a == 1 && b == 3
    await checkOnlineAndOfflineResultsMatch(
      collection.where(
        Filter.and(<Filter>[Filter.equalTo('a', 1), Filter.equalTo('b', 3)]),
      ),
      <String>['doc4'],
    );

    // a == 1, limit 2
    await checkOnlineAndOfflineResultsMatch(
      collection.whereEqualTo('a', 1).limit(2),
      <String>['doc1', 'doc4'],
    );

    // Explicit OR: a == 1 || b == 1 with limit 2
    await checkOnlineAndOfflineResultsMatch(
      collection
          .where(
            Filter.or(<Filter>[Filter.equalTo('a', 1), Filter.equalTo('b', 1)]),
          )
          .limit(2),
      <String>['doc1', 'doc2'],
    );

    // Only limit 2
    await checkOnlineAndOfflineResultsMatch(collection.limit(2), <String>[
      'doc1',
      'doc2',
    ]);

    // Limit 2 and order by b desc
    await checkOnlineAndOfflineResultsMatch(
      collection.limit(2).orderBy('b', Direction.descending),
      <String>['doc4', 'doc3'],
    );
  });
}
