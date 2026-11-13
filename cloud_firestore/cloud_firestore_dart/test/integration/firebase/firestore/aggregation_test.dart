// Copyright 2022 Google LLC
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

import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_field.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_query_snapshot.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/aggregate_source.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/collection_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

typedef Docs = Map<String, Map<String, Object?>>;

const testFirestore = IntegrationTestUtil.testFirestore;
const testCollection = IntegrationTestUtil.testCollection;
const testCollectionWithDocs = IntegrationTestUtil.testCollectionWithDocs;

const int maxLong = 9223372036854775807;

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/aggregation';

  setUp(() => testFirestore());

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  final Docs books = <String, Map<String, Object?>>{
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

  Docs ratings(List<Object?> values) => <String, Map<String, Object?>>{
    for (int i = 0; i < values.length; i++)
      'doc$i': <String, Object?>{'rating': values[i]},
  };

  Future<AggregateQuerySnapshot> run(
    CollectionReference c,
    List<AggregateField> fields,
  ) => c.aggregate(fields).get(AggregateSource.server);

  group('count', () {
    test('testCanRunCount', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuerySnapshot s = await c.count().get(
        AggregateSource.server,
      );
      expect(s.getCount(), 2);
      expect(s.query, c.count());
    });

    test('testCanRunCountWithFilters', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'b'},
          'c': <String, Object?>{'k': 'b'},
        },
      );
      expect((await c.whereEqualTo('k', 'b').count().get()).getCount(), 2);
      expect((await c.whereEqualTo('k', 'a').count().get()).getCount(), 1);
      expect((await c.whereGreaterThan('k', 'a').count().get()).getCount(), 2);
    });

    test('testCanRunCountWithOrderBy', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'b'},
          'c': <String, Object?>{'other': 'c'},
        },
      );
      // The orderBy excludes the document that lacks the field.
      expect((await c.orderBy('k').count().get()).getCount(), 2);
      expect((await c.count().get()).getCount(), 3);
    });

    test('testCanRunCountAggregateWithFiltersAndLimits', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'a'},
          'c': <String, Object?>{'k': 'a'},
          'd': <String, Object?>{'k': 'd'},
        },
      );
      expect(
        (await c.whereEqualTo('k', 'a').limit(2).count().get()).getCount(),
        2,
      );
      expect(
        (await c.whereEqualTo('k', 'd').limit(1000).count().get()).getCount(),
        1,
      );
    });

    test('testCanRunCountWithLimitToLast', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'b'},
          'c': <String, Object?>{'k': 'c'},
          'd': <String, Object?>{'k': 'd'},
        },
      );
      expect((await c.orderBy('k').limitToLast(2).count().get()).getCount(), 2);
      expect(
        (await c.orderBy('k').limitToLast(1000).count().get()).getCount(),
        4,
      );
      expect(
        (await c
                .whereGreaterThan('k', 'a')
                .orderBy('k')
                .limitToLast(2)
                .count()
                .get())
            .getCount(),
        2,
      );
    });

    test('testCanRunCountCollectionGroupQuery', () async {
      final Firestore db = await testFirestore();
      final String group = 'b${db.collection('foo').document().id}';
      final List<String> paths = <String>[
        'abc/123/$group/cg-doc1',
        'abc/123/$group/cg-doc2',
        '$group/cg-doc3',
        '$group/cg-doc4',
        'def/456/$group/cg-doc5',
        '$group/virtual-doc/nested-coll/not-cg-doc',
        'x$group/not-cg-doc',
        '${group}x/not-cg-doc',
        'abc/123/${group}x/not-cg-doc',
        'abc/123/x$group/not-cg-doc',
        'abc/$group',
      ];
      final batch = db.batch();
      for (final String path in paths) {
        batch.set(db.document(path), <String, Object?>{'x': 1});
      }
      await batch.commit();

      final AggregateQuerySnapshot s = await db
          .collectionGroup(group)
          .count()
          .get();
      expect(s.getCount(), 5);
    });

    test('testCanRunCountOnNonExistentCollection', () async {
      final CollectionReference c = (await testFirestore()).collection(
        'random-coll',
      );
      expect((await c.count().get()).getCount(), 0);
      expect((await c.whereEqualTo('k', 100).count().get()).getCount(), 0);
    });

    test('testCountFailWithoutNetwork', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'b'},
          'c': <String, Object?>{'k': 'c'},
        },
      );
      await c.firestore.disableNetwork();
      await expectLater(
        c.count().get(AggregateSource.server),
        throwsA(
          isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.unavailable,
          ),
        ),
      );

      await c.firestore.enableNetwork();
      expect((await c.count().get()).getCount(), 3);
    });
  });

  group('aggregate', () {
    test('testCanRunSumAndAverage', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('pages'),
        AggregateField.average('pages'),
        AggregateField.sum('rating'),
        AggregateField.count(),
      ]);
      expect(s.get(AggregateField.sum('pages')), 150);
      expect(s.get(AggregateField.average('pages')), 75.0);
      expect(s.get(AggregateField.sum('rating')), 9.0);
      expect(s.getCount(), 2);
      expect(s.getInt(AggregateField.average('pages')), 75);
      expect(s.getDouble(AggregateField.sum('pages')), 150.0);
    });

    test('testCanGetDuplicateAggregations', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('pages'),
        AggregateField.sum('pages'),
        AggregateField.count(),
        AggregateField.count(),
      ]);
      expect(s.get(AggregateField.sum('pages')), 150);
      expect(s.getCount(), 2);
    });

    test(
      'testCannotPerformMoreThanMaxAggregations',
      skip: IntegrationTestUtil.skipOnEnterprise(
        'no limit of 5 aggregations per query',
      ),
      () async {
        final CollectionReference c = await testCollectionWithDocs(books);
        await expectLater(
          run(c, <AggregateField>[
            AggregateField.sum('pages'),
            AggregateField.average('pages'),
            AggregateField.count(),
            AggregateField.sum('foo'),
            AggregateField.sum('bar'),
            AggregateField.sum('baz'),
          ]),
          throwsA(
            isA<FirestoreError>()
                .having(
                  (FirestoreError e) => e.code,
                  'code',
                  FirestoreErrorCode.invalidArgument,
                )
                .having(
                  (FirestoreError e) => e.message,
                  'message',
                  contains('maximum number of aggregations'),
                ),
          ),
        );
      },
    );

    test('testThrowsWhenGettingUnrequestedAggregation', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('pages'),
        AggregateField.average('pages'),
        AggregateField.count(),
      ]);
      expect(() => s.get(AggregateField.sum('foo')), throwsArgumentError);
      expect(() => s.get(AggregateField.average('foo')), throwsArgumentError);
      expect(() => s.get(AggregateField.average('pages')), returnsNormally);
    });

    test('testPerformsAggregationsOnNestedMapValues', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{
            'metadata': <String, Object?>{'pages': 100, 'rating': 4.0},
          },
          'b': <String, Object?>{
            'metadata': <String, Object?>{'pages': 50, 'rating': 5.0},
          },
        },
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('metadata.pages'),
        AggregateField.average('metadata.pages'),
        AggregateField.average('metadata.rating'),
      ]);
      expect(s.get(AggregateField.sum('metadata.pages')), 150);
      expect(s.get(AggregateField.average('metadata.pages')), 75.0);
      expect(s.get(AggregateField.average('metadata.rating')), 4.5);
    });

    test('testPerformsAggregationWhenUsingInOperator', () async {
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'pages': 100, 'year': 1980},
          'b': <String, Object?>{'pages': 50, 'year': 2020},
          'c': <String, Object?>{'pages': 150, 'year': 2010},
        },
      );
      final AggregateQuerySnapshot s = await c
          .whereIn('year', <Object>[1980, 2020])
          .aggregate(<AggregateField>[
            AggregateField.sum('pages'),
            AggregateField.average('pages'),
            AggregateField.count(),
          ])
          .get();
      expect(s.get(AggregateField.sum('pages')), 150);
      expect(s.get(AggregateField.average('pages')), 75.0);
      expect(s.getCount(), 2);
    });

    test('testSumTypes', () async {
      final CollectionReference ints = await testCollectionWithDocs(
        ratings(<Object?>[1, 2, 3]),
      );
      final Object? intSum = (await run(ints, <AggregateField>[
        AggregateField.sum('rating'),
      ])).get(AggregateField.sum('rating'));
      expect(intSum, isA<int>());
      expect(intSum, 6);

      final CollectionReference doubles = await testCollectionWithDocs(
        ratings(<Object?>[0.5, 0.5]),
      );
      final Object? doubleSum = (await run(doubles, <AggregateField>[
        AggregateField.sum('rating'),
      ])).get(AggregateField.sum('rating'));
      expect(doubleSum, isA<double>());
      expect(doubleSum, 1.0);
    });

    test(
      'testPerformsSumThatOverflowsMaxLong',
      skip: IntegrationTestUtil.skipOnEnterprise(
        'the emulator fails an integer sum that overflows with "Long overflow" instead of returning a double',
      ),
      () async {
        final CollectionReference c = await testCollectionWithDocs(
          ratings(<Object?>[maxLong, maxLong]),
        );
        final Object? sum = (await run(c, <AggregateField>[
          AggregateField.sum('rating'),
        ])).get(AggregateField.sum('rating'));
        expect(sum, isA<double>());
        expect(sum, maxLong.toDouble() + maxLong.toDouble());
      },
    );

    test(
      'testPerformsSumThatCanOverflowIntegerValuesDuringAccumulation',
      () async {
        final CollectionReference c = await testCollectionWithDocs(
          ratings(<Object?>[maxLong, 1, -101]),
        );
        final Object? sum = (await run(c, <AggregateField>[
          AggregateField.sum('rating'),
        ])).get(AggregateField.sum('rating'));
        expect(sum, isA<int>());
        expect(sum, maxLong - 100);
      },
    );

    test(
      'testPerformsSumThatIsNegative',
      skip: IntegrationTestUtil.skipOnEnterprise(
        'the emulator fails an integer sum that overflows during accumulation with "Long overflow"',
      ),
      () async {
        final CollectionReference c = await testCollectionWithDocs(
          ratings(<Object?>[maxLong, -maxLong, -101, -10000]),
        );
        final AggregateQuerySnapshot s = await run(c, <AggregateField>[
          AggregateField.sum('rating'),
        ]);
        expect(s.get(AggregateField.sum('rating')), -10101);
      },
    );

    test('testPerformsSumThatIsInfinite', () async {
      final CollectionReference pos = await testCollectionWithDocs(
        ratings(<Object?>[double.maxFinite, double.maxFinite]),
      );
      AggregateQuerySnapshot s = await run(pos, <AggregateField>[
        AggregateField.sum('rating'),
      ]);
      expect(s.get(AggregateField.sum('rating')), double.infinity);
      expect(s.getDouble(AggregateField.sum('rating')), double.infinity);
      expect(s.getInt(AggregateField.sum('rating')), maxLong);

      final CollectionReference neg = await testCollectionWithDocs(
        ratings(<Object?>[-double.maxFinite, -double.maxFinite]),
      );
      s = await run(neg, <AggregateField>[AggregateField.sum('rating')]);
      expect(s.get(AggregateField.sum('rating')), double.negativeInfinity);
      expect(s.getInt(AggregateField.sum('rating')), -maxLong - 1);
    });

    test('testPerformsAggregationsWhenNaNExists', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5, 4, double.nan, 0]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('rating'),
        AggregateField.average('rating'),
      ]);
      expect(s.get(AggregateField.sum('rating')), isNaN);
      expect(s.get(AggregateField.average('rating')), isNaN);
      expect(s.getInt(AggregateField.average('rating')), 0);
    });

    test('testPerformsSumOfMinIEEE754', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5e-324]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('rating'),
      ]);
      expect(s.get(AggregateField.sum('rating')), 5e-324);
    });

    test(
      'testPerformsSumAndAverageOverZeroDocuments',
      skip: IntegrationTestUtil.skipOnEnterprise(
        'the sum over no documents is null instead of 0',
      ),
      () async {
        final CollectionReference c = await testCollectionWithDocs(books);
        final AggregateQuerySnapshot s = await c
            .whereGreaterThan('pages', 200)
            .aggregate(<AggregateField>[
              AggregateField.sum('pages'),
              AggregateField.average('pages'),
            ])
            .get();
        expect(s.get(AggregateField.sum('pages')), 0);
        expect(s.get(AggregateField.average('pages')), isNull);
        expect(s.getDouble(AggregateField.average('pages')), isNull);
        expect(s.getInt(AggregateField.average('pages')), isNull);
      },
    );

    test('testPerformsSumAndAverageOnlyOnNumericFields', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5, 4, '3', 6]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('rating'),
        AggregateField.average('rating'),
        AggregateField.count(),
      ]);
      expect(s.get(AggregateField.sum('rating')), 15);
      expect(s.get(AggregateField.average('rating')), 5.0);
      expect(s.getCount(), 4);
    });

    test('testPerformsAverageResults', () async {
      CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[10, 5, 0]),
      );
      expect(
        (await run(c, <AggregateField>[
          AggregateField.average('rating'),
        ])).get(AggregateField.average('rating')),
        5.0,
      );

      c = await testCollectionWithDocs(ratings(<Object?>[10, 1.5, 3, 5.5]));
      expect(
        (await run(c, <AggregateField>[
          AggregateField.average('rating'),
        ])).get(AggregateField.average('rating')),
        5.0,
      );

      c = await testCollectionWithDocs(ratings(<Object?>[10, 5, 0, 0]));
      expect(
        (await run(c, <AggregateField>[
          AggregateField.average('rating'),
        ])).get(AggregateField.average('rating')),
        3.75,
      );
    });

    test('testPerformsAverageOfMinIEEE754', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5e-324]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.average('rating'),
      ]);
      expect(s.get(AggregateField.average('rating')), 5e-324);
    });

    test('testPerformsAverageOverflowDuringAccumulation', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[double.maxFinite, double.maxFinite]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.average('rating'),
      ]);
      expect(s.get(AggregateField.average('rating')), double.infinity);
    });

    test('testAggregateQueryEquality', () async {
      final CollectionReference c = await testCollection('equality');
      expect(c.count(), c.count());
      expect(c.count().hashCode, c.count().hashCode);
      expect(
        c.aggregate(<AggregateField>[
          AggregateField.sum('a'),
          AggregateField.average('b'),
        ]),
        c.aggregate(<AggregateField>[
          AggregateField.sum('a'),
          AggregateField.average('b'),
        ]),
      );
      expect(c.count(), isNot(c.whereEqualTo('a', 1).count()));
      expect(
        c.aggregate(<AggregateField>[AggregateField.sum('a')]),
        isNot(c.aggregate(<AggregateField>[AggregateField.average('a')])),
      );
      expect(
        c.aggregate(<AggregateField>[AggregateField.sum('a')]),
        isNot(c.aggregate(<AggregateField>[AggregateField.sum('b')])),
      );
      expect(c.aggregate(<AggregateField>[AggregateField.count()]), c.count());
    });

    test('testAggregateSnapshotEquality', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuery q = c.aggregate(<AggregateField>[
        AggregateField.sum('pages'),
        AggregateField.count(),
      ]);
      final AggregateQuerySnapshot s1 = await q.get();
      final AggregateQuerySnapshot s2 = await q.get();
      expect(s1, s2);
      expect(s1.hashCode, s2.hashCode);
      expect(s1.query, q);
    });

    test('allowsAliasesLongerThan1500Bytes', () async {
      final String field = 'a' * 1499;
      final CollectionReference c = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{field: 1},
          'b': <String, Object?>{field: 2},
        },
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum(field),
      ]);
      expect(s.get(AggregateField.sum(field)), 3);
    });
  });

  group('Upstream CountTest / AggregationTest leftovers', () {
    test('testCountQueryEquals', () async {
      final CollectionReference coll1 = await testCollection('foo');
      final CollectionReference coll1Same = coll1.firestore.collection(
        coll1.path,
      );
      final AggregateQuery query1 = coll1.count();
      final AggregateQuery query1Same = coll1Same.count();
      AggregateQuery query2() => coll1
          .document('bar')
          .collection('baz')
          .whereEqualTo('a', 1)
          .limit(100)
          .count();
      AggregateQuery query3() => coll1
          .document('bar')
          .collection('baz')
          .whereEqualTo('b', 1)
          .orderBy('c')
          .count();

      expect(query1, query1Same);
      expect(query2(), query2());
      expect(query3(), query3());
      expect(query1.hashCode, query1Same.hashCode);
      expect(query2().hashCode, query2().hashCode);
      expect(query3().hashCode, query3().hashCode);

      expect(query1, isNot('string'));
      expect(query1, isNot(query2()));
      expect(query2(), isNot(query3()));
      expect(query1.hashCode, isNot(query2().hashCode));
      expect(query2().hashCode, isNot(query3().hashCode));
    });

    test('testAggregateQueryNotEquals', () async {
      final CollectionReference coll = await testCollection('foo');

      final AggregateQuery query1 = coll.aggregate(<AggregateField>[
        AggregateField.count(),
      ]);
      final AggregateQuery query2 = coll.aggregate(<AggregateField>[
        AggregateField.sum('baz'),
      ]);
      final AggregateQuery query3 = coll.aggregate(<AggregateField>[
        AggregateField.average('baz'),
      ]);
      expect(query1, isNot(query2));
      expect(query2, isNot(query3));
      expect(query3, isNot(query1));
      expect(query1.hashCode, isNot(query2.hashCode));
      expect(query2.hashCode, isNot(query3.hashCode));
      expect(query3.hashCode, isNot(query1.hashCode));

      final Query base = coll
          .document('bar')
          .collection('baz')
          .whereEqualTo('a', 1)
          .limit(100);
      final AggregateQuery query4 = base.aggregate(<AggregateField>[
        AggregateField.count(),
      ]);
      final AggregateQuery query5 = base.aggregate(<AggregateField>[
        AggregateField.sum('baz'),
      ]);
      final AggregateQuery query6 = base.aggregate(<AggregateField>[
        AggregateField.average('baz'),
      ]);
      expect(query4, isNot(query5));
      expect(query5, isNot(query6));
      expect(query6, isNot(query4));
      expect(query4.hashCode, isNot(query5.hashCode));
      expect(query5.hashCode, isNot(query6.hashCode));
      expect(query6.hashCode, isNot(query4.hashCode));
    });

    test('testCountSnapshotEquals', () async {
      final CollectionReference collection = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'b'},
          'c': <String, Object?>{'k': 'c'},
        },
      );

      final AggregateQuerySnapshot snapshot1 = await collection
          .whereEqualTo('k', 'b')
          .count()
          .get(AggregateSource.server);
      final AggregateQuerySnapshot snapshot1Same = await collection
          .whereEqualTo('k', 'b')
          .count()
          .get(AggregateSource.server);

      final AggregateQuerySnapshot snapshot2 = await collection
          .whereEqualTo('k', 'a')
          .count()
          .get(AggregateSource.server);
      await collection.document('d').set(<String, Object?>{'k': 'a'});
      final AggregateQuerySnapshot snapshot2Different = await collection
          .whereEqualTo('k', 'a')
          .count()
          .get(AggregateSource.server);

      expect(snapshot1, snapshot1Same);
      expect(snapshot1.hashCode, snapshot1Same.hashCode);
      expect(snapshot1.query, collection.whereEqualTo('k', 'b').count());

      expect(snapshot1, isNot('string'));
      expect(snapshot1, isNot(snapshot2));
      expect(snapshot1.hashCode, isNot(snapshot2.hashCode));
      expect(snapshot2, isNot(snapshot2Different));
      expect(snapshot2.hashCode, isNot(snapshot2Different.hashCode));
    });

    test('testTerminateDoesNotCrashWithFlyingCountQuery', () async {
      final CollectionReference collection = await testCollectionWithDocs(
        <String, Map<String, Object?>>{
          'a': <String, Object?>{'k': 'a'},
          'b': <String, Object?>{'k': 'b'},
          'c': <String, Object?>{'k': 'c'},
        },
      );

      // The result is intentionally not awaited: terminating with the query in flight must not crash.
      unawaited(
        collection
            .orderBy('k')
            .count()
            .get(AggregateSource.server)
            .then<void>((_) {}, onError: (Object _) {}),
      );
      await collection.firestore.terminate();
    });

    test('testTerminateDoesNotCrashWithFlyingAggregateQuery', () async {
      final CollectionReference collection = await testCollectionWithDocs(
        books,
      );

      unawaited(
        collection
            .aggregate(<AggregateField>[
              AggregateField.count(),
              AggregateField.sum('pages'),
              AggregateField.average('pages'),
            ])
            .get(AggregateSource.server)
            .then<void>((_) {}, onError: (Object _) {}),
      );
      await collection.firestore.terminate();
    });

    test('testCanGetCorrectTypeForAvg', () async {
      final CollectionReference collection = await testCollectionWithDocs(
        books,
      );

      final AggregateQuerySnapshot snapshot = await collection
          .aggregate(<AggregateField>[AggregateField.average('pages')])
          .get(AggregateSource.server);

      expect(snapshot.get(AggregateField.average('pages')), isA<double>());
    });
  });

  // Modelled on the JS SDK's aggregation.test.ts alias cases
  // (getAggregateFromServer with a user-keyed spec).
  group('aliases', () {
    test('can alias aggregations', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuery query = c
          .aggregateWithAliases(<String, AggregateField>{
            'foo': AggregateField.count(),
            'bar': AggregateField.sum('pages'),
            'baz': AggregateField.average('pages'),
            'pagesAgain': AggregateField.sum('pages'),
          });
      final AggregateQuerySnapshot snapshot = await query.get(
        AggregateSource.server,
      );
      expect(snapshot.data(), <String, Object?>{
        'foo': 2,
        'bar': 150,
        'baz': 75.0,
        'pagesAgain': 150,
      });
      expect(snapshot.query, query);
      expect(snapshot.getCount(), 2);
      expect(snapshot.get(AggregateField.sum('pages')), 150);
    });

    test('works with filters and null results', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuerySnapshot snapshot = await c
          .where('pages', isGreaterThan: 1000)
          .aggregateWithAliases(<String, AggregateField>{
            'n': AggregateField.count(),
            'avg': AggregateField.average('pages'),
          })
          .get(AggregateSource.server);
      expect(snapshot.data(), <String, Object?>{'n': 0, 'avg': null});
    });

    test(
      'allows special characters, backticks, backslashes and long aliases',
      () async {
        final CollectionReference c = await testCollectionWithDocs(books);
        final String longAlias = 'a' * 1500;
        final AggregateQuerySnapshot snapshot = await c
            .aggregateWithAliases(<String, AggregateField>{
              'with-un/su+pp[or]ted': AggregateField.count(),
              'with `backticks`': AggregateField.sum('pages'),
              r'with\backshash\es': AggregateField.sum('year'),
              longAlias: AggregateField.average('rating'),
              '': AggregateField.count(),
            })
            .get(AggregateSource.server);
        expect(snapshot.data(), <String, Object?>{
          'with-un/su+pp[or]ted': 2,
          'with `backticks`': 150,
          r'with\backshash\es': 4000,
          longAlias: 4.5,
          '': 2,
        });
      },
    );
  });

  // Cases of the Android AggregationTest and the JS aggregation.test.ts that
  // the groups above do not cover (see notes/parity/integration_test_map.md).
  group('upstream parity', () {
    test('testCanRunCountUsingAggregationMethod', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.count(),
      ]);
      expect(s.get(AggregateField.count()), 2);
      expect(s.getCount(), 2);
    });

    test('aggregate query does not use the converter', () async {
      final CollectionReference c = await testCollectionWithDocs(books);
      final Query<Object> converted = c
          .where('author', isEqualTo: 'authorA')
          .withConverter<Object>(
            FirestoreDataConverter<Object>.from(
              fromFirestore: (_, __) =>
                  throw StateError('should never be called'),
              toFirestore: (_, __) =>
                  throw StateError('should never be called'),
            ),
          );
      final AggregateQuerySnapshot s = await converted
          .aggregateWithAliases(<String, AggregateField>{
            'count': AggregateField.count(),
          })
          .get(AggregateSource.server);
      expect(s.data()['count'], 1);
    });

    test('testPerformsSumOfIntsAndFloatsThatResultsInAnInt', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5, 4.5, 3.5]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.sum('rating'),
      ]);
      expect(s.get(AggregateField.sum('rating')), 13);
      expect(s.getInt(AggregateField.sum('rating')), 13);
      expect(s.getDouble(AggregateField.sum('rating')), 13.0);
    });

    test(
      'testPerformsSumThatIsValidButCouldOverflowDuringAggregation',
      () async {
        // The sum is 0, but if the accumulation overflows the result is an
        // infinity.
        final CollectionReference c = await testCollectionWithDocs(
          ratings(<Object?>[
            double.maxFinite,
            double.maxFinite,
            -double.maxFinite,
            -double.maxFinite,
          ]),
        );
        final Object? sum = (await run(c, <AggregateField>[
          AggregateField.sum('rating'),
        ])).get(AggregateField.sum('rating'));
        expect(sum, isA<double>());
        expect(sum, anyOf(0.0, double.infinity, double.negativeInfinity));
      },
    );

    test('testPerformsAverageOfFloatsThatResultsInAnInt', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[10.5, 9.5]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.average('rating'),
      ]);
      expect(s.get(AggregateField.average('rating')), 10.0);
      expect(s.getInt(AggregateField.average('rating')), 10);
      expect(s.getDouble(AggregateField.average('rating')), 10.0);
    });

    test('testPerformsAverageOfFloatsThatResultsInAFloat', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5.5, 4.5, 3.5]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.average('rating'),
      ]);
      expect(s.get(AggregateField.average('rating')), 4.5);
      expect(s.getInt(AggregateField.average('rating')), 4);
      expect(s.getDouble(AggregateField.average('rating')), 4.5);
    });

    test('testPerformsAverageOfFloatsAndIntsThatResultsInAFloat', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[8.6, 9, 10]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.average('rating'),
      ]);
      expect(
        s.get(AggregateField.average('rating')),
        moreOrLessEquals(9.2, epsilon: 1e-14),
      );
      expect(
        s.getDouble(AggregateField.average('rating')),
        moreOrLessEquals(9.2, epsilon: 1e-14),
      );
      expect(s.getInt(AggregateField.average('rating')), 9);
    });

    test('testPerformsAverageCausingUnderflow', () async {
      final CollectionReference c = await testCollectionWithDocs(
        ratings(<Object?>[5e-324, 0]),
      );
      final AggregateQuerySnapshot s = await run(c, <AggregateField>[
        AggregateField.average('rating'),
      ]);
      expect(s.get(AggregateField.average('rating')), 0.0);
      expect(s.getDouble(AggregateField.average('rating')), 0.0);
      expect(s.getInt(AggregateField.average('rating')), 0);
    });
  });
}
