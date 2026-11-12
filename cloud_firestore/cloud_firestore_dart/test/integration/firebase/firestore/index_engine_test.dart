// Persistent cache indexes end to end on the emulator: an index is configured and filled, and cache queries (served by
// the index) are compared with the server for every operator, OR / IN, array membership, cursors, limits and
// limitToLast, with and without pending writes. See test/util/index_engine_harness.dart.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:test/test.dart';

import '../../../util/index_engine_harness.dart';
import '../../../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/index_engine';

  late Firestore firestore;
  int collectionIndex = 0;

  setUp(() async {
    firestore = await IntegrationTestUtil.testFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  CollectionReference<Map<String, Object?>> testCollection() {
    return firestore.collection(
      'index-${DateTime.now().microsecondsSinceEpoch}-${collectionIndex++}',
    );
  }

  final Docs docs = <String, Map<String, Object?>>{
    'd01': <String, Object?>{
      'a': 1,
      'b': 'x',
      'tags': <Object?>['red', 1],
    },
    'd02': <String, Object?>{
      'a': 2,
      'b': 'x',
      'tags': <Object?>['blue'],
    },
    'd03': <String, Object?>{
      'a': 2,
      'b': 'y',
      'tags': <Object?>['red', 'blue'],
    },
    'd04': <String, Object?>{'a': 3, 'b': 'y', 'tags': <Object?>[]},
    'd05': <String, Object?>{
      'a': 3.5,
      'b': 'z',
      'tags': <Object?>[2],
    },
    'd06': <String, Object?>{'a': 4, 'b': 'z'},
    'd07': <String, Object?>{
      'a': 5,
      'tags': <Object?>['green', 'red'],
    },
    'd08': <String, Object?>{'a': null, 'b': 'x', 'tags': 'red'},
    'd09': <String, Object?>{'a': 'text', 'b': 'y'},
    'd10': <String, Object?>{
      'b': 'w',
      'tags': <Object?>['blue', 1],
    },
    'd11': <String, Object?>{
      'a': 2,
      'b': 'w',
      'tags': <Object?>['green'],
    },
    'd12': <String, Object?>{
      'a': -1,
      'b': 'x',
      'tags': <Object?>['red'],
    },
  };

  final List<List<String>> indexes = <List<String>>[
    <String>['a'],
    <String>['a desc'],
    <String>['b'],
    <String>['b desc'],
    <String>['tags contains'],
    <String>['a', 'b'],
    <String>['b', 'a desc'],
    <String>['tags contains', 'a'],
  ];

  test('cache queries served by an index agree with the server', () async {
    await checkIndexedQueries(
      firestore: firestore,
      collection: testCollection(),
      docs: docs,
      indexes: indexes,
      queries: <IndexedQuery>[
        // Comparison operators.
        IndexedQuery('a == 2', (c) => c.whereEqualTo('a', 2)),
        IndexedQuery('a != 2', (c) => c.whereNotEqualTo('a', 2)),
        IndexedQuery('a < 3', (c) => c.whereLessThan('a', 3)),
        IndexedQuery('a <= 3', (c) => c.whereLessThanOrEqualTo('a', 3)),
        IndexedQuery('a > 2', (c) => c.whereGreaterThan('a', 2)),
        IndexedQuery('a >= 2', (c) => c.whereGreaterThanOrEqualTo('a', 2)),
        IndexedQuery(
          '2 <= a < 4',
          (c) => c.whereGreaterThanOrEqualTo('a', 2).whereLessThan('a', 4),
        ),
        IndexedQuery('a == null', (c) => c.whereEqualTo('a', null)),
        IndexedQuery('a != null', (c) => c.whereNotEqualTo('a', null)),
        IndexedQuery('b >= "y"', (c) => c.whereGreaterThanOrEqualTo('b', 'y')),
        // IN and NOT IN.
        IndexedQuery(
          'a in [1, 3, 5]',
          (c) => c.whereIn('a', <Object?>[1, 3, 5]),
        ),
        IndexedQuery(
          'a not-in [2, 3]',
          (c) => c.whereNotIn('a', <Object?>[2, 3]),
        ),
        IndexedQuery(
          'b in [x, z], a desc',
          (c) => c
              .whereIn('b', <Object?>['x', 'z'])
              .orderBy('a', Direction.descending),
          // An IN is one sub target per value, sorted and limited in memory.
        ),
        // Array membership.
        IndexedQuery(
          'tags array-contains red',
          (c) => c.whereArrayContains('tags', 'red'),
        ),
        IndexedQuery(
          'tags array-contains-any [blue, 1]',
          (c) => c.whereArrayContainsAny('tags', <Object?>['blue', 1]),
        ),
        IndexedQuery(
          'tags array-contains red, a > 0',
          (c) => c.whereArrayContains('tags', 'red').whereGreaterThan('a', 0),
        ),
        // Several fields.
        IndexedQuery(
          'a == 2 and b == x',
          (c) => c.whereEqualTo('a', 2).whereEqualTo('b', 'x'),
        ),
        IndexedQuery(
          'b == x, order by a desc',
          (c) => c.whereEqualTo('b', 'x').orderBy('a', Direction.descending),
        ),
        IndexedQuery(
          'a >= 2 order by a, b',
          (c) => c.whereGreaterThanOrEqualTo('a', 2).orderBy('a').orderBy('b'),
        ),
        // OR.
        IndexedQuery(
          'a == 1 or b == y',
          (c) => c.where(
            Filter.or(<Filter>[
              Filter.equalTo('a', 1),
              Filter.equalTo('b', 'y'),
            ]),
          ),
        ),
        IndexedQuery(
          'a > 3 or tags array-contains blue',
          (c) => c.where(
            Filter.or(<Filter>[
              Filter.greaterThan('a', 3),
              Filter.arrayContains('tags', 'blue'),
            ]),
          ),
        ),
        IndexedQuery(
          '(a == 2 and b == x) or (a in [3, 4] and b == z)',
          (c) => c.where(
            Filter.or(<Filter>[
              Filter.and(<Filter>[
                Filter.equalTo('a', 2),
                Filter.equalTo('b', 'x'),
              ]),
              Filter.and(<Filter>[
                Filter.inArray('a', <Object?>[3, 4]),
                Filter.equalTo('b', 'z'),
              ]),
            ]),
          ),
        ),
        // An OR with a limit is sorted and limited in memory: a partial index.
        IndexedQuery(
          'a == 2 or b == z, limit 2',
          (c) => c
              .where(
                Filter.or(<Filter>[
                  Filter.equalTo('a', 2),
                  Filter.equalTo('b', 'z'),
                ]),
              )
              .limit(2),
          index: IndexType.partial,
        ),
        // Order, cursors and limits.
        IndexedQuery('order by a', (c) => c.orderBy('a')),
        IndexedQuery(
          'order by a desc',
          (c) => c.orderBy('a', Direction.descending),
        ),
        IndexedQuery(
          'order by a, startAt 2',
          (c) => c.orderBy('a').startAt(<Object?>[2]),
        ),
        IndexedQuery(
          'order by a, startAfter 2',
          (c) => c.orderBy('a').startAfter(<Object?>[2]),
        ),
        IndexedQuery(
          'order by a, endAt 3',
          (c) => c.orderBy('a').endAt(<Object?>[3]),
        ),
        IndexedQuery(
          'order by a, endBefore 3',
          (c) => c.orderBy('a').endBefore(<Object?>[3]),
        ),
        IndexedQuery(
          'order by a desc, startAfter 3, endAt 1',
          (c) => c
              .orderBy('a', Direction.descending)
              .startAfter(<Object?>[3])
              .endAt(<Object?>[1]),
        ),
        IndexedQuery(
          'order by b, a desc, startAt [x, 2]',
          (c) => c.orderBy('b').orderBy('a', Direction.descending).startAt(
            <Object?>['x', 2],
          ),
        ),
        IndexedQuery('order by a, limit 3', (c) => c.orderBy('a').limit(3)),
        IndexedQuery(
          'a >= 2, limit 2',
          (c) => c.whereGreaterThanOrEqualTo('a', 2).limit(2),
        ),
        IndexedQuery(
          'order by a, limitToLast 3',
          (c) => c.orderBy('a').limitToLast(3),
        ),
        IndexedQuery(
          'b == x, order by a, limitToLast 2',
          (c) => c.whereEqualTo('b', 'x').orderBy('a').limitToLast(2),
        ),
        IndexedQuery(
          'order by a desc, startAt 4, limitToLast 2',
          (c) => c
              .orderBy('a', Direction.descending)
              .startAt(<Object?>[4])
              .limitToLast(2),
        ),
        // Only part of the query is covered by an index: `b` has one, `c` does not exist in any.
        IndexedQuery(
          'b == x and c == 1 (partial index)',
          (c) => c.whereEqualTo('b', 'x').whereEqualTo('c', 1),
          index: IndexType.partial,
        ),
        // No index at all: scanned.
        IndexedQuery(
          'c == 1 (no index)',
          (c) => c.whereEqualTo('c', 1),
          index: IndexType.none,
        ),
      ],
      pendingWrites: (CollectionReference<Map<String, Object?>> c) async {
        // A new document, a changed one (it moves in every order and gets the field `c`), one that loses its
        // indexed fields, and a deleted one.
        c.doc('p01').set(<String, Object?>{
          'a': 2,
          'b': 'x',
          'c': 1,
          'tags': <Object?>['red', 'blue'],
        }).ignore();
        c.doc('d01').update(<String, Object?>{
          'a': 10,
          'b': 'z',
          'c': 1,
          'tags': <Object?>['blue'],
        }).ignore();
        c.doc('d04').set(<String, Object?>{'other': true}).ignore();
        c.doc('d03').delete().ignore();
      },
      affectedByPendingWrites: <String>[
        'a == 2',
        'a > 2',
        'tags array-contains red',
        'a == 1 or b == y',
        'order by a',
        'order by a, limitToLast 3',
        'c == 1 (no index)',
      ],
    );
  });
}
