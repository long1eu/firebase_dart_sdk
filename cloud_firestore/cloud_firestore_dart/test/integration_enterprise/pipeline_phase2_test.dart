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
// Phase 2 of the Pipelines preview against the Enterprise edition emulator
// (tool/start_enterprise_emulator.sh):
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//         dart test test/integration_enterprise/pipeline_phase2_test.dart
//
// Covers the write stages and atomic execution, variables and subqueries,
// lambda functions, and the functions that the first pipeline tests only
// checked for their encoding. Everything is skipped, with a reason, when the
// variable is not set.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/pipeline_phase2';

  final String? skip = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  late Firestore firestore;
  late CollectionReference<Map<String, Object?>> collection;

  List<Map<String, Object?>> rows(PipelineSnapshot snapshot) =>
      snapshot.results.map((PipelineResult r) => r.data()).toList();

  Pipeline source() => firestore.pipeline().collection(collection);

  /// The documents of [collection], as a map from id to data, read with a
  /// pipeline (from the server).
  Future<Map<String, Map<String, Object?>>> contents(
      [CollectionReference<Map<String, Object?>>? of]) async {
    final PipelineSnapshot snapshot =
        await firestore.pipeline().collection(of ?? collection).execute();
    return <String, Map<String, Object?>>{
      for (final PipelineResult result in snapshot.results)
        result.id!: result.data(),
    };
  }

  group('pipelines, phase 2', () {
    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      collection = firestore.collection('phase2_${autoId()}');
      await collection.document('a').set(<String, Object?>{
        'name': 'a',
        'n': 1,
        'scores': <int>[1, 5, 9],
      });
      await collection.document('b').set(<String, Object?>{
        'name': 'b',
        'n': 2,
        'scores': <int>[2, 6],
      });
      await collection.document('c').set(<String, Object?>{
        'name': 'c',
        'n': 3,
        'scores': <int>[],
      });
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await IntegrationTestUtil.tearDown();
    });

    group('write stages', () {
      test('update writes the transformed fields', () async {
        final PipelineSnapshot snapshot = await source()
            .where(field('n').greaterThan(1))
            .update(transformedFields: <Selectable>[
          field('n').multiply(10).as('n'),
          constant(true).as('touched'),
        ]).execute();

        expect(rows(snapshot), <Map<String, Object?>>[
          <String, Object?>{'documents_modified': 2}
        ]);
        expect(snapshot.executionTime, isNull);

        final Map<String, Map<String, Object?>> docs = await contents();
        expect(docs['a'], <String, Object?>{
          'name': 'a',
          'n': 1,
          'scores': <int>[1, 5, 9]
        });
        expect(docs['b'], <String, Object?>{
          'name': 'b',
          'n': 20,
          'scores': <int>[2, 6],
          'touched': true
        });
        expect(docs['c']!['n'], 30);
      });

      test('update without fields writes the documents as the stages left them',
          () async {
        final PipelineSnapshot snapshot = await source()
            .where(field('name').equal('a'))
            .addFields(<Selectable>[field('scores').arrayLength().as('count')])
            .update()
            .execute(atomic: true);

        expect(
            rows(snapshot).single, <String, Object?>{'documents_modified': 1});
        expect((await contents())['a'], <String, Object?>{
          'name': 'a',
          'n': 1,
          'scores': <int>[1, 5, 9],
          'count': 3
        });
      });

      test('delete removes the matching documents', () async {
        final PipelineSnapshot snapshot = await source()
            .where(field('n').lessThan(3))
            .delete()
            .execute(atomic: true);

        expect(
            rows(snapshot).single, <String, Object?>{'documents_modified': 2});
        expect((await contents()).keys, <String>['c']);
      });

      test('delete of nothing modifies nothing', () async {
        final PipelineSnapshot snapshot = await source()
            .where(field('n').greaterThan(100))
            .delete()
            .execute();
        expect(
            rows(snapshot).single, <String, Object?>{'documents_modified': 0});
        expect(await contents(), hasLength(3));
      });

      test('insert copies documents into another collection', () async {
        final CollectionReference<Map<String, Object?>> archive =
            firestore.collection('archive_${autoId()}');
        final PipelineSnapshot snapshot = await source()
            .where(field('n').greaterThan(1))
            .select(<Object>['name', 'n'])
            .insert(
                collection: archive,
                documentId:
                    constant('copy-').stringConcat(<Object?>[field('name')]))
            .execute(atomic: true);

        expect(
            rows(snapshot).single, <String, Object?>{'documents_modified': 2});
        expect(await contents(archive), <String, Map<String, Object?>>{
          'copy-b': <String, Object?>{'name': 'b', 'n': 2},
          'copy-c': <String, Object?>{'name': 'c', 'n': 3},
        });
        // The source is untouched.
        expect(await contents(), hasLength(3));
      });

      test('insert lets the server assign ids', () async {
        final CollectionReference<Map<String, Object?>> archive =
            firestore.collection('archive_${autoId()}');
        await source()
            .select(<Object>['name'])
            .insert(collection: archive.path)
            .execute(atomic: true);

        final Map<String, Map<String, Object?>> docs = await contents(archive);
        expect(docs, hasLength(3));
        expect(docs.values.map((Map<String, Object?> d) => d['name']),
            unorderedEquals(<String>['a', 'b', 'c']));
        expect(docs.keys, everyElement(hasLength(20)));
      });

      test(
          'insert fails with already-exists for an existing document, and '
          'an atomic pipeline then writes nothing', () async {
        final CollectionReference<Map<String, Object?>> archive =
            firestore.collection('archive_${autoId()}');
        await archive.document('b').set(<String, Object?>{'old': true});

        await expectLater(
            source()
                .sort(<Ordering>[field('name').ascending()])
                .select(<Object>['name'])
                .insert(collection: archive, documentId: 'name')
                .execute(atomic: true),
            throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
                'code', FirestoreErrorCode.alreadyExists)));

        expect(await contents(archive), <String, Map<String, Object?>>{
          'b': <String, Object?>{'old': true},
        });
      });

      test('upsert creates and replaces documents', () async {
        final CollectionReference<Map<String, Object?>> archive =
            firestore.collection('archive_${autoId()}');
        await archive.document('b').set(<String, Object?>{'old': true});

        final PipelineSnapshot snapshot = await source()
            .where(field('n').lessThan(3))
            .select(<Object>['name', 'n']).upsert(
          additionalFields: <Selectable>[constant(true).as('archived')],
          collection: archive,
          documentId: 'name',
        ).execute(atomic: true);

        expect(
            rows(snapshot).single, <String, Object?>{'documents_modified': 2});
        final Map<String, Map<String, Object?>> docs = await contents(archive);
        expect(docs.keys, unorderedEquals(<String>['a', 'b']));
        expect(docs['a'],
            <String, Object?>{'name': 'a', 'n': 1, 'archived': true});
        expect(docs['b']!['archived'], isTrue);
        expect(docs['b']!['n'], 2);
      });

      test('upsert without a target writes back to the source documents',
          () async {
        await source().where(field('name').equal('c')).upsert(
            additionalFields: <Selectable>[
              constant(1).as('extra')
            ]).execute(atomic: true);
        expect((await contents())['c']!['extra'], 1);
      });

      test('insert from literals works without a transaction', () async {
        final CollectionReference<Map<String, Object?>> archive =
            firestore.collection('archive_${autoId()}');
        final PipelineSnapshot snapshot = await firestore
            .pipeline()
            .literals(<Map<String, Object?>>[
              <String, Object?>{'id': 'x', 'n': 1},
              <String, Object?>{'id': 'y', 'n': constant(1).add(1)},
            ])
            .insert(collection: archive, documentId: 'id')
            .execute();

        expect(
            rows(snapshot).single, <String, Object?>{'documents_modified': 2});
        expect(await contents(archive), <String, Map<String, Object?>>{
          'x': <String, Object?>{'id': 'x', 'n': 1},
          'y': <String, Object?>{'id': 'y', 'n': 2},
        });
      },
          // Verified with an admin (`Bearer owner`) REST call; see the same
          // skip in the first pipeline tests.
          skip: 'The emulator rejects the literals source for clients that '
              'are subject to security rules (permission-denied).');

      test('insert and upsert of stored documents need atomic execution',
          () async {
        final CollectionReference<Map<String, Object?>> archive =
            firestore.collection('archive_${autoId()}');
        final Matcher invalidArgument = throwsA(isA<FirestoreError>().having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.invalidArgument));

        await expectLater(
            source().insert(collection: archive).execute(), invalidArgument);
        await expectLater(
            source().upsert(
                additionalFields: <Selectable>[constant(1).as('x')]).execute(),
            invalidArgument);
        expect(await contents(archive), isEmpty);
        expect((await contents())['a']!.containsKey('x'), isFalse);
      });

      test('a listener sees the writes of a pipeline', () async {
        final DocumentReference<Map<String, Object?>> doc =
            collection.document('a');
        final Future<DocumentSnapshot<Map<String, Object?>>> changed = doc
            .snapshots
            .firstWhere((DocumentSnapshot<Map<String, Object?>> s) =>
                s.exists && s.data!['seen'] == true);
        await source().where(field('name').equal('a')).update(
            transformedFields: <Selectable>[
              constant(true).as('seen')
            ]).execute();
        expect((await changed).data!['n'], 1);
      },
          skip: 'The emulator (v1.22.0) does not report the writes of a '
              'pipeline to Listen streams: listeners and get(Source.server) '
              'return the old version until a regular write touches the '
              'document.');
    });

    group('variables and subqueries', () {
      test('define and variable', () async {
        final PipelineSnapshot snapshot =
            await source().define(<AliasedExpression>[
          field('n').multiply(100).as('big'),
          currentDocument().as('doc'),
        ]).sort(<Ordering>[field('name').ascending()]).select(<Object>[
          variable('big').as('big'),
          variable('doc').getField('name').as('name'),
        ]).execute();

        expect(rows(snapshot), <Map<String, Object?>>[
          <String, Object?>{'big': 100, 'name': 'a'},
          <String, Object?>{'big': 200, 'name': 'b'},
          <String, Object?>{'big': 300, 'name': 'c'},
        ]);
      });

      test('a scalar subquery over another collection', () async {
        final PipelineSnapshot snapshot = await source()
            .where(field('name').equal('b'))
            .define(
                <AliasedExpression>[field('n').as('limit')]).select(<Object>[
          'name',
          source()
              .where(field('n').lessThanOrEqual(variable('limit')))
              .aggregate(<AliasedAggregate>[countAll().as('count')])
              .toScalarExpression()
              .as('notLarger'),
        ]).execute();

        expect(rows(snapshot).single,
            <String, Object?>{'name': 'b', 'notLarger': 2});
      });

      test('an array subquery over a subcollection', () async {
        await collection
            .document('a')
            .collection('reviews')
            .document('r1')
            .set(<String, Object?>{'stars': 4});
        await collection
            .document('a')
            .collection('reviews')
            .document('r2')
            .set(<String, Object?>{'stars': 5});

        final PipelineSnapshot snapshot = await source()
            .sort(<Ordering>[field('name').ascending()])
            .limit(2)
            .select(<Object>[
              'name',
              firestore
                  .pipeline()
                  .subcollection('reviews')
                  .sort(<Ordering>[field('stars').ascending()])
                  .select(<Object>['stars'])
                  .toArrayExpression()
                  .as('stars'),
            ])
            .execute();

        expect(rows(snapshot), <Map<String, Object?>>[
          <String, Object?>{
            'name': 'a',
            'stars': <int>[4, 5]
          },
          <String, Object?>{'name': 'b', 'stars': <Object?>[]},
        ]);
      });
    });

    group('lambda and conditional functions', () {
      Future<Map<String, Object?>> selectFromA(
          List<Selectable> selections) async {
        return rows(await source()
                .where(field('name').equal('a'))
                .select(selections)
                .execute())
            .single;
      }

      test('arrayFilter, arrayTransform, arrayTransformWithIndex', () async {
        expect(
            await selectFromA(<Selectable>[
              field('scores')
                  .arrayFilter((Expression score) => score.greaterThan(4))
                  .as('filtered'),
              field('scores')
                  .arrayTransform((Expression score) => score.multiply(2))
                  .as('doubled'),
              field('scores')
                  .arrayTransformWithIndex(
                      (Expression score, Expression index) => score.add(index))
                  .as('plusIndex'),
              field('scores')
                  .arrayTransform((Expression score) => score.add(field('n')),
                      alias: 's')
                  .as('plusField'),
            ]),
            <String, Object?>{
              'filtered': <int>[5, 9],
              'doubled': <int>[2, 10, 18],
              'plusIndex': <int>[1, 6, 11],
              'plusField': <int>[2, 6, 10],
            });
      });

      test('array extremes', () async {
        expect(
            await selectFromA(<Selectable>[
              field('scores').arrayMaximum().as('max'),
              field('scores').arrayMinimum().as('min'),
              field('scores').arrayMaximumN(2).as('max2'),
              field('scores').arrayMinimumN(2).as('min2'),
            ]),
            <String, Object?>{
              'max': 9,
              'min': 1,
              'max2': <int>[9, 5],
              'min2': <int>[1, 5],
            });
      });

      test('switchOn and nor', () async {
        final PipelineSnapshot snapshot = await source()
            .sort(<Ordering>[field('name').ascending()]).select(<Object>[
          switchOn(field('n').equal(1), 'one',
              <Object?>[field('n').equal(2), 'two', 'many']).as('word'),
          nor(field('n').equal(1), field('n').equal(2)).as('nor'),
        ]).execute();

        expect(rows(snapshot), <Map<String, Object?>>[
          <String, Object?>{'word': 'one', 'nor': false},
          <String, Object?>{'word': 'two', 'nor': false},
          <String, Object?>{'word': 'many', 'nor': true},
        ]);
      });
    });

    // Functions and options that the first pipeline tests only checked for
    // their encoding.
    group('server-side check of', () {
      late DocumentReference<Map<String, Object?>> doc;
      // 1970-01-04T01:01:01Z, a Sunday.
      const Timestamp when = Timestamp(86400 * 3 + 3661, 0);

      setUp(() async {
        doc = collection.document('functions');
        await doc.set(<String, Object?>{
          'title': 'Dune',
          'tags': <String>['a', 'b', 'a', 'c'],
          'map': <String, Object?>{'x': 1, 'y': 2},
          'when': when,
          'start': const Timestamp(86400, 0),
          'location': const GeoPoint(0, 0),
          'nothing': null,
          'vector': VectorValue(<double>[1, 0]),
        });
      });

      Future<Map<String, Object?>> select(List<Selectable> selections) async {
        return rows(await firestore
                .pipeline()
                .documents(<Object>[doc])
                .select(selections)
                .execute())
            .single;
      }

      test('timestamp functions', () async {
        expect(
            await select(<Selectable>[
              field('when').timestampDiff('start', 'day').as('diffDays'),
              field('when')
                  .timestampDiff(constant(const Timestamp(86400, 0)), 'hour')
                  .as('diffHours'),
              field('when').timestampTruncate('day').as('truncated'),
              field('when')
                  .timestampTruncate('day', 'America/New_York')
                  .as('truncatedNewYork'),
              field('when').timestampExtract('hour').as('hour'),
              field('when')
                  .timestampExtract('hour', 'America/New_York')
                  .as('hourNewYork'),
              field('when').timestampExtract('dayofweek').as('dayOfWeek'),
              constant(86400).unixSecondsToTimestamp().as('fromSeconds'),
              constant(1000000).unixMicrosToTimestamp().as('fromMicros'),
              field('when').timestampToUnixMillis().as('millis'),
              field('when').timestampToUnixMicros().as('micros'),
            ]),
            <String, Object?>{
              'diffDays': 2,
              'diffHours': 49,
              'truncated': const Timestamp(86400 * 3, 0),
              // Midnight in New York (UTC-5) on January 3rd.
              'truncatedNewYork': const Timestamp(86400 * 2 + 5 * 3600, 0),
              'hour': 1,
              'hourNewYork': 20,
              'dayOfWeek': 1,
              'fromSeconds': const Timestamp(86400, 0),
              'fromMicros': const Timestamp(1, 0),
              'millis': 262861000,
              'micros': 262861000000,
            });
      });

      test('currentTimestamp and rand', () async {
        final DateTime before =
            DateTime.now().subtract(const Duration(minutes: 1));
        final Map<String, Object?> row = await select(<Selectable>[
          currentTimestamp().as('now'),
          rand().as('rand'),
        ]);
        expect((row['now']! as Timestamp).toDate().isAfter(before), isTrue);
        expect(row['rand'], allOf(greaterThanOrEqualTo(0), lessThan(1)));
      });

      test('array functions', () async {
        expect(
            await select(<Selectable>[
              field('tags').arraySlice(1).as('slice'),
              field('tags').arraySlice(1, 2).as('sliceLength'),
              field('tags').arrayFirstN(2).as('firstN'),
              field('tags').arrayLastN(2).as('lastN'),
              field('tags').arrayLastIndexOf('a').as('lastIndexOf'),
              field('tags').arrayIndexOfAll('a').as('indexOfAll'),
              field('tags').arrayGet(-1).as('getFromEnd'),
              field('tags').concat(<Object?>[
                <String>['z']
              ]).as('concat'),
              field('tags').length().as('length'),
              field('tags').reverse().as('reverse'),
            ]),
            <String, Object?>{
              'slice': <String>['b', 'a', 'c'],
              'sliceLength': <String>['b', 'a'],
              'firstN': <String>['a', 'b'],
              'lastN': <String>['a', 'c'],
              'lastIndexOf': 2,
              'indexOfAll': <int>[0, 2],
              'getFromEnd': 'c',
              'concat': <String>['a', 'b', 'a', 'c', 'z'],
              'length': 4,
              'reverse': <String>['c', 'a', 'b', 'a'],
            });
      });

      test('map functions', () async {
        expect(
            await select(<Selectable>[
              field('map').mapSet('z', 3).as('set'),
              field('map').mapValues().as('values'),
              field('map').mapEntries().as('entries'),
              field('map').length().as('length'),
            ]),
            <String, Object?>{
              'set': <String, Object?>{'x': 1, 'y': 2, 'z': 3},
              'values': unorderedEquals(<int>[1, 2]),
              'entries': unorderedEquals(<Map<String, Object?>>[
                <String, Object?>{'k': 'x', 'v': 1},
                <String, Object?>{'k': 'y', 'v': 2},
              ]),
              'length': 2,
            });
      });

      test('string functions', () async {
        expect(
            await select(<Selectable>[
              field('title').regexFind('u.').as('regexFind'),
              constant('banana').regexFindAll('an').as('regexFindAll'),
              constant('aXbXc').stringReplaceOne('X', '-').as('replaceOne'),
              field('title').concat(<Object?>['!', '?']).as('concat'),
              field('title').length().as('length'),
              field('title').reverse().as('reverse'),
              field('title').substring(2).as('substring'),
              constant('xxaxx').trim('x').as('trim'),
            ]),
            <String, Object?>{
              'regexFind': 'un',
              'regexFindAll': <String>['an', 'an'],
              'replaceOne': 'a-bXc',
              'concat': 'Dune!?',
              'length': 4,
              'reverse': 'enuD',
              'substring': 'ne',
              'trim': 'a',
            });
      });

      test('types, missing values and errors', () async {
        expect(
            await select(<Selectable>[
              field('nothing').coalesce(
                  field('missing'), <Object?>['fallback']).as('coalesce'),
              field('title').add(1).ifError('error').as('ifError'),
              field('nothing').ifNull('was null').as('ifNull'),
              field('title').isType('string').as('isString'),
              field('map').isType('string').as('mapIsString'),
              field('title').add(1).isError().as('isError'),
              field('map').type().as('type'),
              xor(field('title').equal('Dune'), field('nothing').exists())
                  .as('xorBothTrue'),
              xor(field('title').equal('Dune'), field('missing').exists())
                  .as('xorOneTrue'),
            ]),
            <String, Object?>{
              'coalesce': 'fallback',
              'ifError': 'error',
              'ifNull': 'was null',
              'isString': true,
              'mapIsString': false,
              'isError': true,
              'type': 'map',
              'xorBothTrue': false,
              'xorOneTrue': true,
            });
      });

      test('math, vectors and references', () async {
        final Map<String, Object?> row = await select(<Selectable>[
          constant(1.98).trunc().as('trunc'),
          constant(1.98).trunc(1).as('truncPlaces'),
          constant(2.5).round().as('round'),
          field('vector').cosineDistance(<double>[0, 1]).as('cosine'),
          field('vector').vectorLength().as('dimensions'),
          field('__name__').parent().as('parent'),
        ]);
        expect(row['trunc'], 1.0);
        expect(row['truncPlaces'], 1.9);
        expect(row['round'], 3.0);
        expect(row['cosine'], closeTo(1, 1e-9));
        expect(row['dimensions'], 2);
        expect(row['parent'], isA<DocumentReference<Object?>>());
      });

      test('geoDistance', () async {
        expect(
            (await select(<Selectable>[
              field('location').geoDistance(const GeoPoint(0, 1)).as('meters'),
            ]))['meters'],
            closeTo(111195, 500));
      },
          skip: 'The emulator (v1.22.0) rejects it: invalid-argument "The '
              "function 'geo_distance' does not exist.\"");

      test('first and last', () async {
        final PipelineSnapshot snapshot = await source()
            .where(field('n').exists())
            .sort(<Ordering>[
          field('n').ascending()
        ]).aggregate(<AliasedAggregate>[
          field('name').first().as('first'),
          field('name').last().as('last'),
        ]).execute();
        expect(rows(snapshot).single,
            <String, Object?>{'first': 'a', 'last': 'c'});
      });

      test('sample with a percentage', () async {
        expect((await source().sample(percentage: 1).execute()).results,
            hasLength(4));
        expect(
            (await source().sample(percentage: 0).execute()).results, isEmpty);
      });

      test('the database source', () async {
        final PipelineSnapshot snapshot = await firestore
            .pipeline()
            .database()
            .where(field('__name__').equal(doc))
            .select(<Object>['title']).execute();
        expect(rows(snapshot).single, <String, Object?>{'title': 'Dune'});
      });

      // The emulator accepts and ignores these options (it also accepts
      // options that do not exist), so this only shows that sending them
      // does not break a request.
      test('execute options are accepted', () async {
        PipelineSnapshot snapshot = await source()
            .where(field('n').exists())
            .execute(indexMode: PipelineIndexMode.recommended);
        expect(snapshot.results, hasLength(3));

        snapshot = await firestore
            .pipeline()
            .collection(collection, forceIndex: 'no_such_index')
            .where(field('n').exists())
            .execute();
        expect(snapshot.results, hasLength(3));

        snapshot = await source()
            .where(field('n').exists())
            .execute(rawOptions: <String, Object?>{
          'explain_options': <String, Object?>{'mode': 'analyze'}
        });
        expect(snapshot.results, hasLength(3));
        expect(snapshot.explainStats, isNull);
      });
    });
  }, skip: skip);
}
