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
// Pipelines need an Enterprise edition database, so these tests do not use the
// shared (Standard edition) emulator of `FIRESTORE_EMULATOR_HOST`. Start the
// Enterprise edition emulator with `tool/start_enterprise_emulator.sh` and
// point `FIRESTORE_ENTERPRISE_EMULATOR_HOST` (host:port) at it. Without that
// variable every test in this file is skipped.
//
// The cases are a subset of the JS SDK's test/integration/api/pipeline.test.ts
// and query_to_pipeline.test.ts.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

const Map<String, Map<String, Object?>> books = <String, Map<String, Object?>>{
  'book1': <String, Object?>{
    'title': "The Hitchhiker's Guide to the Galaxy",
    'author': 'Douglas Adams',
    'genre': 'Science Fiction',
    'published': 1979,
    'rating': 4.2,
    'tags': <String>['comedy', 'space', 'adventure'],
    'awards': <String, Object?>{'hugo': true, 'nebula': false},
  },
  'book2': <String, Object?>{
    'title': 'Pride and Prejudice',
    'author': 'Jane Austen',
    'genre': 'Romance',
    'published': 1813,
    'rating': 4.5,
    'tags': <String>['classic', 'social commentary', 'love'],
    'awards': <String, Object?>{'none': true},
  },
  'book3': <String, Object?>{
    'title': 'One Hundred Years of Solitude',
    'author': 'Gabriel García Márquez',
    'genre': 'Magical Realism',
    'published': 1967,
    'rating': 4.3,
    'tags': <String>['family', 'history', 'fantasy'],
    'awards': <String, Object?>{'nobel': true, 'nebula': false},
  },
  'book4': <String, Object?>{
    'title': 'The Lord of the Rings',
    'author': 'J.R.R. Tolkien',
    'genre': 'Fantasy',
    'published': 1954,
    'rating': 4.7,
    'tags': <String>['adventure', 'magic', 'epic'],
    'awards': <String, Object?>{'hugo': false, 'nebula': false},
  },
  'book5': <String, Object?>{
    'title': "The Handmaid's Tale",
    'author': 'Margaret Atwood',
    'genre': 'Dystopian',
    'published': 1985,
    'rating': 4.1,
    'tags': <String>['feminism', 'totalitarianism', 'resistance'],
    'awards': <String, Object?>{'arthur c. clarke': true},
  },
  'book6': <String, Object?>{
    'title': 'Dune',
    'author': 'Frank Herbert',
    'genre': 'Science Fiction',
    'published': 1965,
    'rating': 4.6,
    'tags': <String>['politics', 'desert', 'ecology'],
    'awards': <String, Object?>{'hugo': true, 'nebula': true},
  },
};

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration_enterprise/pipeline';

  final String? skip = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  late Firestore firestore;
  late CollectionReference<Map<String, Object?>> collection;

  List<String?> ids(PipelineSnapshot snapshot) =>
      snapshot.results.map((PipelineResult r) => r.id).toList();

  List<Map<String, Object?>> rows(PipelineSnapshot snapshot) =>
      snapshot.results.map((PipelineResult r) => r.data()).toList();

  group('pipelines', () {
    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      collection = firestore.collection('books_${autoId()}');
      for (final MapEntry<String, Map<String, Object?>> book in books.entries) {
        await collection.document(book.key).set(book.value);
      }
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await IntegrationTestUtil.tearDown();
    });

    Pipeline source() => firestore.pipeline().collection(collection);

    test('returns the documents of a collection', () async {
      final PipelineSnapshot snapshot = await source()
          .sort(<Ordering>[field('__name__').ascending()]).execute();

      expect(ids(snapshot), books.keys);
      expect(snapshot.executionTime, isNotNull);
      final PipelineResult first = snapshot.results.first;
      expect(first.ref!.path, '${collection.path}/book1');
      expect(first.data(), books['book1']);
      expect(first.createTime, isNotNull);
      expect(first.updateTime, isNotNull);
      expect(first.get('awards.hugo'), isTrue);
    });

    test('returns no results and an execution time for an empty collection',
        () async {
      final PipelineSnapshot snapshot =
          await firestore.pipeline().collection('empty_${autoId()}').execute();
      expect(snapshot.results, isEmpty);
      expect(snapshot.executionTime, isNotNull);
    });

    test('accepts a collection path', () async {
      final PipelineSnapshot snapshot = await firestore
          .pipeline()
          .collection(collection.path)
          .limit(2)
          .execute();
      expect(snapshot.results, hasLength(2));
    });

    test('where, sort, select', () async {
      final PipelineSnapshot snapshot = await source()
          .where(field('rating').greaterThan(4.5))
          .sort(<Ordering>[field('rating').descending()]).select(<Object>[
        'title',
        field('author').toUpper().as('author'),
      ]).execute();

      expect(rows(snapshot), <Map<String, Object?>>[
        <String, Object?>{
          'title': 'The Lord of the Rings',
          'author': 'J.R.R. TOLKIEN'
        },
        <String, Object?>{'title': 'Dune', 'author': 'FRANK HERBERT'},
      ]);
      // A projected row is no longer a document.
      expect(snapshot.results.first.ref, isNull);
      expect(snapshot.results.first.createTime, isNull);
    });

    test('logical conditions', () async {
      PipelineSnapshot snapshot = await source()
          .where(and(field('genre').equal('Science Fiction'),
              field('published').lessThan(1970)))
          .execute();
      expect(ids(snapshot), <String>['book6']);

      snapshot = await source()
          .where(or(field('genre').equal('Romance'),
              field('genre').equal('Dystopian')))
          .sort(<Ordering>[field('__name__').ascending()]).execute();
      expect(ids(snapshot), <String>['book2', 'book5']);

      snapshot = await source()
          .where(not(field('rating').lessThanOrEqual(4.6)))
          .execute();
      expect(ids(snapshot), <String>['book4']);

      snapshot = await source()
          .where(field('genre').equalAny(<String>['Romance', 'Fantasy']))
          .sort(<Ordering>[field('__name__').ascending()]).execute();
      expect(ids(snapshot), <String>['book2', 'book4']);

      snapshot = await source()
          .where(field('genre').notEqualAny(
              <String>['Romance', 'Fantasy', 'Science Fiction', 'Dystopian']))
          .execute();
      expect(ids(snapshot), <String>['book3']);
    });

    test('array, map and existence functions', () async {
      PipelineSnapshot snapshot = await source()
          .where(field('tags').arrayContains('adventure'))
          .sort(<Ordering>[field('__name__').ascending()]).execute();
      expect(ids(snapshot), <String>['book1', 'book4']);

      snapshot = await source()
          .where(field('tags').arrayContainsAny(<String>['love', 'epic']))
          .sort(<Ordering>[field('__name__').ascending()]).execute();
      expect(ids(snapshot), <String>['book2', 'book4']);

      snapshot = await source()
          .where(field('tags').arrayContainsAll(<String>['comedy', 'space']))
          .execute();
      expect(ids(snapshot), <String>['book1']);

      snapshot =
          await source().where(field('awards.nobel').exists()).select(<Object>[
        field('tags').arrayLength().as('tagCount'),
        field('awards').mapGet('nobel').as('nobel'),
        field('awards.hugo').isAbsent().as('noHugo'),
      ]).execute();
      expect(rows(snapshot), <Map<String, Object?>>[
        <String, Object?>{'tagCount': 3, 'nobel': true, 'noHugo': true},
      ]);
    });

    test('arithmetic and string functions', () async {
      final PipelineSnapshot snapshot =
          await source().where(field('title').equal('Dune')).select(<Object>[
        field('published').add(1).as('add'),
        field('published').subtract(1965).as('subtract'),
        field('published').multiply(2).as('multiply'),
        field('published').divide(5).as('divide'),
        field('published').mod(10).as('mod'),
        field('title')
            .stringConcat(<Object?>[' by ', field('author')]).as('concat'),
        field('title').toLower().as('lower'),
        field('title').charLength().as('length'),
        field('title').startsWith('Du').as('starts'),
        field('title').endsWith('x').as('ends'),
        field('title').stringContains('un').as('contains'),
        field('title').like('D%').as('like'),
        field('title').regexMatch('D.*e').as('regexMatch'),
        field('author').regexContains('Herb').as('regexContains'),
        constant('  x ').trim().as('trim'),
        field('rating')
            .greaterThan(4.5)
            .conditional('great', 'good')
            .as('verdict'),
        field('__name__').documentId().as('id'),
      ]).execute();

      expect(rows(snapshot).single, <String, Object?>{
        'add': 1966,
        'subtract': 0,
        'multiply': 3930,
        'divide': 393,
        'mod': 5,
        'concat': 'Dune by Frank Herbert',
        'lower': 'dune',
        'length': 4,
        'starts': true,
        'ends': false,
        'contains': true,
        'like': true,
        'regexMatch': true,
        'regexContains': true,
        'trim': 'x',
        'verdict': 'great',
        'id': 'book6',
      });
    });

    test('aggregate over everything', () async {
      final PipelineSnapshot snapshot =
          await source().aggregate(<AliasedAggregate>[
        countAll().as('count'),
        field('rating').average().as('avg'),
        field('rating').maximum().as('max'),
        field('rating').minimum().as('min'),
        field('published').sum().as('sum'),
        field('genre').countDistinct().as('genres'),
        field('rating').greaterThan(4.4).countIf().as('great'),
        field('awards.hugo').count().as('withHugo'),
      ]).execute();

      final Map<String, Object?> row = rows(snapshot).single;
      expect(row['count'], 6);
      expect(row['avg'], closeTo(4.4, 1e-9));
      expect(row['max'], 4.7);
      expect(row['min'], 4.1);
      expect(row['sum'], 1979 + 1813 + 1967 + 1954 + 1985 + 1965);
      expect(row['genres'], 5);
      expect(row['great'], 3);
      expect(row['withHugo'], 3);
    });

    test('aggregate with groups', () async {
      final PipelineSnapshot snapshot = await source()
          .aggregate(
            <AliasedAggregate>[
              countAll().as('count'),
              field('rating').average().as('avg'),
            ],
            groups: <Object>['genre'],
          )
          .where(field('count').greaterThan(1))
          .execute();

      final Map<String, Object?> row = rows(snapshot).single;
      expect(row['genre'], 'Science Fiction');
      expect(row['count'], 2);
      expect(row['avg'], closeTo(4.4, 1e-9));
    });

    test('distinct', () async {
      final PipelineSnapshot snapshot = await source()
          .distinct(<Object>['genre']).sort(
              <Ordering>[field('genre').ascending()]).execute();
      expect(
          rows(snapshot).map((Map<String, Object?> r) => r['genre']), <String>[
        'Dystopian',
        'Fantasy',
        'Magical Realism',
        'Romance',
        'Science Fiction',
      ]);
    });

    test('limit and offset', () async {
      final PipelineSnapshot snapshot = await source()
          .sort(<Ordering>[field('published').ascending()])
          .offset(1)
          .limit(2)
          .execute();
      expect(ids(snapshot), <String>['book4', 'book6']);
    });

    test('addFields and removeFields', () async {
      final PipelineSnapshot snapshot = await source()
          .where(field('title').equal('Dune'))
          .addFields(<Selectable>[
        field('published').add(100).as('later')
      ]).removeFields(<Object>['tags', 'awards', field('author')]).execute();
      expect(rows(snapshot).single, <String, Object?>{
        'title': 'Dune',
        'genre': 'Science Fiction',
        'published': 1965,
        'rating': 4.6,
        'later': 2065,
      });
      // Still a document.
      expect(snapshot.results.single.id, 'book6');
    });

    test('unnest', () async {
      final PipelineSnapshot snapshot = await source()
          .where(field('title').equal('Dune'))
          .unnest(field('tags').as('tag'), indexField: 'index')
          .select(<Object>['tag', 'index']).execute();
      expect(
          rows(snapshot),
          unorderedEquals(<Map<String, Object?>>[
            <String, Object?>{'tag': 'politics', 'index': 0},
            <String, Object?>{'tag': 'desert', 'index': 1},
            <String, Object?>{'tag': 'ecology', 'index': 2},
          ]));
    });

    test('replaceWith', () async {
      final PipelineSnapshot snapshot = await source()
          .where(field('title').equal('Dune'))
          .replaceWith('awards')
          .execute();
      expect(rows(snapshot).single,
          <String, Object?>{'hugo': true, 'nebula': true});
    });

    test('union', () async {
      final PipelineSnapshot snapshot = await source()
          .where(field('genre').equal('Romance'))
          .union(source().where(field('genre').equal('Fantasy')))
          .execute();
      expect(ids(snapshot), unorderedEquals(<String>['book2', 'book4']));
    });

    test('sample', () async {
      final PipelineSnapshot snapshot =
          await source().sample(documents: 3).execute();
      expect(snapshot.results, hasLength(3));
    });

    test('documents', () async {
      final PipelineSnapshot snapshot =
          await firestore.pipeline().documents(<Object>[
        collection.document('book2'),
        '${collection.path}/book5',
      ]).sort(<Ordering>[field('__name__').ascending()]).execute();
      expect(ids(snapshot), <String>['book2', 'book5']);
    });

    test('collectionGroup', () async {
      final String groupId = 'group_${autoId()}';
      await firestore
          .collection('a/b/$groupId')
          .document('x')
          .set(<String, Object?>{'n': 1});
      await firestore
          .collection('c/d/$groupId')
          .document('y')
          .set(<String, Object?>{'n': 2});

      final PipelineSnapshot snapshot = await firestore
          .pipeline()
          .collectionGroup(groupId)
          .sort(<Ordering>[field('n').ascending()]).execute();
      expect(ids(snapshot), <String>['x', 'y']);
      expect(snapshot.results.first.ref!.path, 'a/b/$groupId/x');
    });

    test('literals', () async {
      final PipelineSnapshot snapshot = await firestore
          .pipeline()
          .literals(<Map<String, Object?>>[
            <String, Object?>{'name': 'a', 'n': 1},
            <String, Object?>{'name': 'b', 'n': constant(1).add(2)},
          ])
          .where(field('n').greaterThan(1))
          .execute();
      expect(rows(snapshot), <Map<String, Object?>>[
        <String, Object?>{'name': 'b', 'n': 3},
      ]);
    },
        // Verified with an admin (`Bearer owner`) REST call that the server
        // accepts this encoding; see also the serialization unit tests.
        skip: 'The emulator rejects the literals source for clients that are '
            'subject to security rules (permission-denied: No matching allow '
            'statements), even with allow-all rules.');

    test('findNearest', () async {
      final CollectionReference<Map<String, Object?>> vectors =
          firestore.collection('vectors_${autoId()}');
      await vectors.document('near').set(<String, Object?>{
        'embedding': FieldValue.vector(<double>[1, 1])
      });
      await vectors.document('far').set(<String, Object?>{
        'embedding': FieldValue.vector(<double>[10, 10])
      });
      await vectors.document('none').set(<String, Object?>{'other': 1});

      final PipelineSnapshot snapshot = await firestore
          .pipeline()
          .collection(vectors)
          .findNearest('embedding', <double>[1, 2], DistanceMeasure.euclidean,
              limit: 2, distanceField: 'distance')
          .execute();
      expect(ids(snapshot), <String>['near', 'far']);
      expect(snapshot.results.first.get('distance'), closeTo(1, 1e-9));
      expect(
          snapshot.results.first.get('embedding'), VectorValue(<double>[1, 1]));
    });

    test('constants of every type round trip', () async {
      final DocumentReference<Map<String, Object?>> reference =
          collection.document('book1');
      final Map<String, Object?> values = <String, Object?>{
        'null': null,
        'bool': true,
        'int': 42,
        'double': 1.5,
        'string': 'text',
        'timestamp': const Timestamp(1700000000, 123000),
        'geo': const GeoPoint(1.5, -2.5),
        'bytes': Blob(Uint8List.fromList(<int>[1, 2, 3])),
        'vector': VectorValue(<double>[1, 2]),
        'list': <Object?>[1, 'a', null],
        'map': <String, Object?>{
          'nested': <Object?>[true]
        },
      };
      final PipelineSnapshot snapshot = await source().limit(1).select(<Object>[
        for (final MapEntry<String, Object?> entry in values.entries)
          constant(entry.value).as(entry.key),
        constant(reference).as('ref'),
      ]).execute();

      final PipelineResult result = snapshot.results.single;
      values.forEach((String key, Object? value) {
        expect(result.get(key), value, reason: key);
      });
      expect((result.get('ref')! as DocumentReference<Object?>).path,
          reference.path);
    });

    group('more functions', () {
      Future<Map<String, Object?>> select(List<Selectable> selections) async {
        final PipelineSnapshot snapshot = await source()
            .where(field('title').equal('Dune'))
            .select(selections)
            .execute();
        return rows(snapshot).single;
      }

      test('math', () async {
        expect(
            await select(<Selectable>[
              constant(-2).abs().as('abs'),
              constant(1.2).ceil().as('ceil'),
              constant(1.8).floor().as('floor'),
              constant(1.26).round(1).as('round'),
              constant(2).pow(3).as('pow'),
              constant(16).sqrt().as('sqrt'),
              constant(0).exp().as('exp'),
              constant(1).ln().as('ln'),
              constant(8).log(2).as('log'),
              constant(1).logicalMaximum(<Object?>[3, 2]).as('max'),
              constant(1).logicalMinimum(<Object?>[3, 2]).as('min'),
            ]),
            <String, Object?>{
              'abs': 2,
              'ceil': 2.0,
              'floor': 1.0,
              'round': 1.3,
              'pow': 8.0,
              'sqrt': 4.0,
              'exp': 1.0,
              'ln': 0.0,
              'log': 3.0,
              'max': 3,
              'min': 1,
            });
      });

      test('strings', () async {
        expect(
            await select(<Selectable>[
              field('title').substring(1, 2).as('substring'),
              field('title').stringReverse().as('reverse'),
              field('title').stringRepeat(2).as('repeat'),
              field('title').stringIndexOf('n').as('indexOf'),
              field('title').stringReplaceAll('u', 'oo').as('replaceAll'),
              field('author').split(' ').as('split'),
              field('tags').join('+').as('join'),
              field('title').byteLength().as('bytes'),
              constant('xxaxx').ltrim('x').as('ltrim'),
              constant('xxaxx').rtrim('x').as('rtrim'),
              field('title').type().as('type'),
            ]),
            <String, Object?>{
              'substring': 'un',
              'reverse': 'enuD',
              'repeat': 'DuneDune',
              'indexOf': 2,
              'replaceAll': 'Doone',
              'split': <String>['Frank', 'Herbert'],
              'join': 'politics+desert+ecology',
              'bytes': 4,
              'ltrim': 'axx',
              'rtrim': 'xxa',
              'type': 'string',
            });
      });

      test('arrays and maps', () async {
        expect(
            await select(<Selectable>[
              field('tags').arrayGet(1).as('get'),
              field('tags').arrayReverse().as('reverse'),
              field('tags').arrayConcat(<Object?>[
                <String>['x']
              ]).as('concat'),
              field('tags').arrayFirst().as('first'),
              field('tags').arrayLast().as('last'),
              field('tags').arrayIndexOf('desert').as('indexOf'),
              field('awards').mapKeys().as('keys'),
              field('awards').mapRemove('hugo').as('removed'),
              field('awards')
                  .mapMerge(map(<String, Object?>{'extra': 1}))
                  .as('merged'),
              array(<Object?>[1, field('published')]).as('array'),
              field('missing').ifAbsent('default').as('ifAbsent'),
              field('missing').isAbsent().as('isAbsent'),
            ]),
            <String, Object?>{
              'get': 'desert',
              'reverse': <String>['ecology', 'desert', 'politics'],
              'concat': <String>['politics', 'desert', 'ecology', 'x'],
              'first': 'politics',
              'last': 'ecology',
              'indexOf': 1,
              'keys': unorderedEquals(<String>['hugo', 'nebula']),
              'removed': <String, Object?>{'nebula': true},
              'merged': <String, Object?>{
                'hugo': true,
                'nebula': true,
                'extra': 1
              },
              'array': <Object?>[1, 1965],
              'ifAbsent': 'default',
              'isAbsent': true,
            });
      });

      test('timestamps and vectors', () async {
        const Timestamp time = Timestamp(86400, 0);
        expect(
            await select(<Selectable>[
              constant(time).timestampAdd('day', 1).as('add'),
              constant(time).timestampSubtract('hour', 24).as('subtract'),
              constant(time).timestampToUnixSeconds().as('seconds'),
              constant(86400000).unixMillisToTimestamp().as('fromMillis'),
              constant(VectorValue(<double>[3, 4]))
                  .euclideanDistance(<double>[0, 0]).as('euclidean'),
              constant(VectorValue(<double>[1, 2]))
                  .dotProduct(<double>[3, 4]).as('dot'),
              constant(VectorValue(<double>[1, 2])).vectorLength().as('dims'),
              field('__name__').collectionId().as('collection'),
            ]),
            <String, Object?>{
              'add': const Timestamp(172800, 0),
              'subtract': const Timestamp(0, 0),
              'seconds': 86400,
              'fromMillis': time,
              'euclidean': 5.0,
              'dot': 11.0,
              'dims': 2,
              'collection': collection.id,
            });
      });

      test('aggregates', () async {
        final PipelineSnapshot snapshot = await source().sort(<Ordering>[
          field('published').ascending()
        ]).aggregate(<AliasedAggregate>[
          field('genre').arrayAggDistinct().as('genres'),
          field('published').arrayAgg().as('years'),
        ]).execute();
        final Map<String, Object?> row = rows(snapshot).single;
        expect(
            row['genres'],
            unorderedEquals(<String>[
              'Dystopian',
              'Fantasy',
              'Magical Realism',
              'Romance',
              'Science Fiction'
            ]));
        expect(row['years'],
            unorderedEquals(<int>[1979, 1813, 1967, 1954, 1985, 1965]));
      });
    });

    test('rawStage and raw functions', () async {
      final PipelineSnapshot snapshot =
          await source().rawStage('where', <Object?>[
        FunctionExpression('equal', <Object?>[field('title'), 'Dune'])
      ]).rawStage('select', <Object?>[
        <String, Object?>{
          'title': field('title'),
          'reversed':
              FunctionExpression('string_reverse', <Object?>[field('title')]),
        }
      ]).execute();
      expect(rows(snapshot).single,
          <String, Object?>{'title': 'Dune', 'reversed': 'enuD'});
    });

    test('fails with invalid-argument for an unknown function', () async {
      await expectLater(
          source()
              .where(FunctionExpression('no_such_fn', <Object?>[field('a')])
                  .asBoolean())
              .execute(),
          throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
              'code', FirestoreErrorCode.invalidArgument)));
    });

    test('fails with unavailable while the network is disabled', () async {
      await firestore.disableNetwork();
      await expectLater(
          source().execute(),
          throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
              'code', FirestoreErrorCode.unavailable)));
      await firestore.enableNetwork();
      expect((await source().execute()).results, hasLength(6));
    });

    test('does not see pending writes', () async {
      await firestore.disableNetwork();
      // Not awaited: the write stays pending while offline.
      final Future<void> write = collection
          .document('book7')
          .set(<String, Object?>{'title': 'Pending'});
      await firestore.enableNetwork();
      await write;
      expect((await source().execute()).results, hasLength(7));
    });

    group('createFrom(query) returns what the query returns', () {
      Future<void> check(Query<Map<String, Object?>> query) async {
        final List<String> expected = (await query.get(Source.server))
            .docs
            .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id)
            .toList();
        final PipelineSnapshot snapshot =
            await firestore.pipeline().createFrom(query).execute();
        expect(ids(snapshot), expected);
        expect(expected, isNotEmpty, reason: 'the case must match something');
      }

      test('whole collection', () => check(collection));

      test('filters', () async {
        await check(collection.whereEqualTo('genre', 'Science Fiction'));
        await check(collection.whereNotEqualTo('genre', 'Science Fiction'));
        await check(collection.whereGreaterThan('rating', 4.3));
        await check(collection.whereLessThanOrEqualTo('published', 1965));
        await check(collection.whereArrayContains('tags', 'adventure'));
        await check(
            collection.whereArrayContainsAny('tags', <String>['love', 'epic']));
        await check(
            collection.whereIn('genre', <String>['Romance', 'Fantasy']));
        await check(collection.whereIn('genre', <String>['Romance']));
        await check(
            collection.whereNotIn('genre', <String>['Romance', 'Fantasy']));
        await check(collection.whereEqualTo('awards.hugo', true));
      });

      test('composite filters', () async {
        await check(collection.where(Filter.or(<Filter>[
          Filter.equalTo('genre', 'Romance'),
          Filter.and(<Filter>[
            Filter.greaterThan('rating', 4.5),
            Filter.lessThan('published', 1960),
          ]),
        ])));
      });

      test('orderings', () async {
        await check(collection.orderBy('published'));
        await check(collection.orderBy('published', Direction.descending));
        await check(collection
            .orderBy('genre')
            .orderBy('rating', Direction.descending));
        // Only documents that have the field are returned.
        await check(collection.orderBy('awards.hugo'));
      });

      test('limits', () async {
        await check(collection.orderBy('published').limit(2));
        await check(
            collection.orderBy('published', Direction.descending).limit(2));
        await check(collection.orderBy('published').limitToLast(2));
        await check(collection
            .orderBy('published', Direction.descending)
            .limitToLast(2));
      });

      test('cursors', () async {
        final Query<Map<String, Object?>> ascending =
            collection.orderBy('published');
        await check(ascending.startAt(<Object?>[1965]));
        await check(ascending.startAfter(<Object?>[1965]));
        await check(ascending.endAt(<Object?>[1965]));
        await check(ascending.endBefore(<Object?>[1965]));
        await check(
            ascending.startAfter(<Object?>[1813]).endBefore(<Object?>[1985]));
      });

      test('cursors with a descending ordering', () async {
        final Query<Map<String, Object?>> descending =
            collection.orderBy('published', Direction.descending);
        await check(descending.startAt(<Object?>[1965]));
        await check(descending.startAfter(<Object?>[1965]));
        await check(descending.endAt(<Object?>[1965]));
        await check(descending.endBefore(<Object?>[1965]));
      });

      test('document cursors and several orderings', () async {
        final DocumentSnapshot<Map<String, Object?>> middle =
            await collection.document('book3').get();
        await check(collection.orderBy('genre').startAtDocument(middle));
        await check(collection.orderBy('genre').startAfterDocument(middle));
        await check(collection
            .orderBy('genre', Direction.descending)
            .startAtDocument(middle));
        await check(collection
            .orderBy('genre', Direction.descending)
            .endAtDocument(middle));
        await check(collection
            .orderBy('genre')
            .orderBy('rating', Direction.descending)
            .startAfter(<Object?>['Science Fiction', 4.6]));
      });

      test('cursors with limitToLast', () async {
        await check(collection
            .orderBy('published')
            .endBefore(<Object?>[1985]).limitToLast(2));
        await check(collection
            .orderBy('published', Direction.descending)
            .startAfter(<Object?>[1985]).limitToLast(2));
      });
    });
  }, skip: skip);
}
