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
// `firestore.pipeline().createFrom(query)` for every query shape of the SDK,
// compared with `query.get(Source.server)` on the Enterprise edition emulator
// (tool/start_enterprise_emulator.sh):
//
//     FIRESTORE_ENTERPRISE_EMULATOR_HOST=127.0.0.1:8181 \
//         dart test test/integration_enterprise/pipeline_create_from_test.dart
//
// Also covers createFromAggregateQuery and createFromVectorQuery.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

const Map<String, Map<String, Object?>> cities = <String, Map<String, Object?>>{
  'lisbon': <String, Object?>{
    'country': 'PT',
    'population': 545000,
    'tags': <String>['capital', 'coast'],
    'geo': <String, Object?>{'continent': 'EU', 'elevation': 2},
    'founded': null,
  },
  'milan': <String, Object?>{
    'country': 'IT',
    'population': 1370000,
    'tags': <String>['fashion'],
    'geo': <String, Object?>{'continent': 'EU', 'elevation': 120},
  },
  'paris': <String, Object?>{
    'country': 'FR',
    'population': 2100000,
    'tags': <String>['capital'],
    'geo': <String, Object?>{'continent': 'EU', 'elevation': 35},
    'ratio': double.nan,
  },
  'porto': <String, Object?>{
    'country': 'PT',
    'population': 232000,
    'tags': <String>['port', 'coast'],
    'geo': <String, Object?>{'continent': 'EU', 'elevation': 104},
  },
  'rome': <String, Object?>{
    'country': 'IT',
    'population': 2800000,
    'tags': <String>['capital'],
    'geo': <String, Object?>{'continent': 'EU', 'elevation': 21},
    'founded': -753,
  },
  'tokyo': <String, Object?>{
    'country': 'JP',
    'population': 14000000,
    'tags': <String>['capital', 'coast'],
    'geo': <String, Object?>{'continent': 'AS', 'elevation': 40},
  },
};

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/pipeline_create_from';

  final String? skip = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  late Firestore firestore;
  late CollectionReference<Map<String, Object?>> collection;

  /// Runs [query] on the server and as a pipeline and expects the same
  /// documents in the same order. A case has to match something, unless
  /// [allowEmpty] is set, so that a pair of empty results proves nothing by
  /// accident.
  Future<List<String>> check(Query<Map<String, Object?>> query,
      {bool allowEmpty = false, String? reason}) async {
    final List<String> expected = <String>[
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc
          in (await query.get(Source.server)).docs)
        doc.id
    ];
    final PipelineSnapshot snapshot =
        await firestore.pipeline().createFrom(query).execute();
    expect(<String?>[
      for (final PipelineResult r in snapshot.results) r.id
    ], expected, reason: reason);
    if (!allowEmpty) {
      expect(expected, isNotEmpty,
          reason: 'the case must match something (${reason ?? ''})');
    }
    return expected;
  }

  group('createFrom(query)', () {
    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      collection = firestore.collection('cities_${autoId()}');
      final WriteBatch batch = firestore.batch();
      cities.forEach((String id, Map<String, Object?> data) {
        batch.set(collection.doc(id), data);
      });
      await batch.commit();
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await IntegrationTestUtil.tearDown();
    });

    test('the whole collection', () async {
      expect(await check(collection), cities.keys);
    });

    test('where with every named argument', () async {
      await check(collection.where('country', isEqualTo: 'IT'));
      await check(collection.where('country', isNotEqualTo: 'IT'));
      await check(collection.where('population', isLessThan: 1370000));
      await check(collection.where('population', isLessThanOrEqualTo: 1370000));
      await check(collection.where('population', isGreaterThan: 1370000));
      await check(
          collection.where('population', isGreaterThanOrEqualTo: 1370000));
      await check(collection.where('tags', arrayContains: 'coast'));
      await check(collection
          .where('tags', arrayContainsAny: <String>['port', 'fashion']));
      await check(collection.where('country', whereIn: <String>['PT', 'JP']));
      await check(collection.where('country', whereIn: <String>['PT']));
      await check(
          collection.where('country', whereNotIn: <String>['PT', 'JP']));
      await check(collection.where('country', whereNotIn: <String>['PT']));
    });

    test('several arguments on one field and several where calls', () async {
      await check(collection.where('population',
          isGreaterThan: 500000, isLessThan: 2500000));
      await check(collection
          .where('country', isEqualTo: 'IT')
          .where('population', isGreaterThan: 2000000));
      await check(collection
          .where('tags', arrayContains: 'capital')
          .where('country', whereIn: <String>['IT', 'FR']).where('population',
              isLessThan: 2500000));
    });

    test('nested fields', () async {
      await check(collection.where('geo.continent', isEqualTo: 'AS'));
      await check(collection.where(FieldPath.of(<String>['geo', 'elevation']),
          isGreaterThan: 50));
      await check(collection.orderBy('geo.elevation', Direction.descending));
    });

    test('null and NaN', () async {
      expect(await check(collection.where('founded', isNull: true)),
          <String>['lisbon']);
      expect(await check(collection.where('founded', isNull: false)),
          <String>['rome']);
      expect(await check(collection.where('ratio', isEqualTo: double.nan)),
          <String>['paris']);
      // != matches neither null nor a missing field.
      expect(
          await check(collection.where('founded', isNotEqualTo: -753),
              allowEmpty: true),
          isEmpty);
      expect(await check(collection.where('founded', isNotEqualTo: 0)),
          <String>['rome']);
    });

    test('the method style filters', () async {
      await check(collection.whereEqualTo('country', 'PT'));
      await check(collection.whereNotEqualTo('country', 'PT'));
      await check(collection.whereGreaterThan('population', 2000000));
      await check(collection.whereArrayContains('tags', 'port'));
      await check(collection.whereIn('country', <String>['FR', 'JP']));
    });

    test('OR and AND filters', () async {
      await check(collection.where(Filter.or(<Filter>[
        Filter.equalTo('country', 'PT'),
        Filter.greaterThan('population', 5000000),
      ])));
      await check(collection.where(Filter.or(<Filter>[
        Filter.equalTo('country', 'PT'),
        Filter.and(<Filter>[
          Filter.equalTo('country', 'IT'),
          Filter.greaterThan('population', 2000000),
        ]),
      ])));
      await check(collection.where(Filter.and(<Filter>[
        Filter.or(<Filter>[
          Filter.equalTo('country', 'IT'),
          Filter.equalTo('country', 'FR'),
        ]),
        Filter.arrayContains('tags', 'capital'),
      ])));
      await check(collection
          .where(Filter.or(<Filter>[
            Filter.equalTo('country', 'JP'),
            Filter.lessThan('population', 600000),
          ]))
          .orderBy('population', Direction.descending)
          .limit(2));
    });

    test('filters on the document id', () async {
      await check(collection.where(FieldPath.documentIdField,
          isEqualTo: collection.doc('paris')));
      await check(collection.where(FieldPath.documentIdField,
          isGreaterThan: collection.doc('m')));
      await check(collection.where(FieldPath.documentIdField,
          whereIn: <Object>[collection.doc('rome'), collection.doc('porto')]));
      await check(collection.orderByField(FieldPath.documentIdField));
      // Not compared with a descending order by document id: the Enterprise
      // edition emulator rejects that classic query ("does not support
      // descending key scans"), while the pipeline runs.
    });

    test('orderings', () async {
      await check(collection.orderBy('population'));
      await check(collection.orderBy('population', Direction.descending));
      await check(collection
          .orderBy('country')
          .orderBy('population', Direction.descending));
      await check(collection
          .orderBy('country', Direction.descending)
          .orderBy('population'));
      // Only documents that have the field, nulls first.
      expect(await check(collection.orderBy('founded')),
          <String>['lisbon', 'rome']);
      // An inequality adds an implicit ordering.
      await check(collection.where('population', isGreaterThan: 500000));
      await check(collection
          .where('population', isGreaterThan: 500000)
          .orderBy('country', Direction.descending));
    });

    test('limit and limitToLast', () async {
      await check(collection.orderBy('population').limit(2));
      await check(collection.limit(3));
      await check(
          collection.orderBy('population', Direction.descending).limit(2));
      expect(await check(collection.orderBy('population').limitToLast(2)),
          <String>['rome', 'tokyo']);
      expect(
          await check(collection
              .orderBy('population', Direction.descending)
              .limitToLast(2)),
          <String>['lisbon', 'porto']);
      await check(collection
          .where('country', whereIn: <String>['IT', 'PT'])
          .orderBy('population')
          .limitToLast(3));
    });

    test('cursors by value, inclusive and exclusive', () async {
      final Query<Map<String, Object?>> ascending =
          collection.orderBy('population');
      expect(await check(ascending.startAt(<Object?>[1370000])),
          <String>['milan', 'paris', 'rome', 'tokyo']);
      expect(await check(ascending.startAfter(<Object?>[1370000])),
          <String>['paris', 'rome', 'tokyo']);
      expect(await check(ascending.endAt(<Object?>[1370000])),
          <String>['porto', 'lisbon', 'milan']);
      expect(await check(ascending.endBefore(<Object?>[1370000])),
          <String>['porto', 'lisbon']);
      await check(ascending
          .startAfter(<Object?>[232000]).endBefore(<Object?>[2800000]));
      await check(
          ascending.startAt(<Object?>[232000]).endAt(<Object?>[2800000]));
      // A cursor value that no document has.
      await check(ascending.startAt(<Object?>[1000000]));
    });

    test('cursors with a descending ordering', () async {
      final Query<Map<String, Object?>> descending =
          collection.orderBy('population', Direction.descending);
      expect(await check(descending.startAt(<Object?>[1370000])),
          <String>['milan', 'lisbon', 'porto']);
      expect(await check(descending.startAfter(<Object?>[1370000])),
          <String>['lisbon', 'porto']);
      expect(await check(descending.endAt(<Object?>[1370000])),
          <String>['tokyo', 'rome', 'paris', 'milan']);
      expect(await check(descending.endBefore(<Object?>[1370000])),
          <String>['tokyo', 'rome', 'paris']);
    });

    test('cursors over several orderings', () async {
      final Query<Map<String, Object?>> query = collection
          .orderBy('country')
          .orderBy('population', Direction.descending);
      await check(query.startAt(<Object?>['IT', 2800000]));
      await check(query.startAfter(<Object?>['IT', 2800000]));
      await check(query.endAt(<Object?>['IT', 1370000]));
      await check(query.endBefore(<Object?>['IT', 1370000]));
      // A prefix of the orderings.
      await check(query.startAt(<Object?>['IT']));
      await check(query.startAfter(<Object?>['IT']));
      await check(query.endAt(<Object?>['IT']));
      await check(query.endBefore(<Object?>['IT']));
    });

    test('cursors by document', () async {
      final DocumentSnapshot<Map<String, Object?>> milan =
          await collection.doc('milan').get();
      final DocumentSnapshot<Map<String, Object?>> porto =
          await collection.doc('porto').get();
      for (final Query<Map<String, Object?>> query
          in <Query<Map<String, Object?>>>[
        collection,
        collection.orderBy('population'),
        collection.orderBy('population', Direction.descending),
        collection.orderBy('country').orderBy('population'),
        collection.orderBy('country', Direction.descending),
      ]) {
        await check(query.startAtDocument(milan));
        await check(query.startAfterDocument(milan));
        await check(query.endAtDocument(milan));
        await check(query.endBeforeDocument(milan));
      }
      // Two documents with the same country: the document id breaks the tie.
      expect(
          await check(collection.orderBy('country').startAfterDocument(porto),
              allowEmpty: true),
          isEmpty,
          reason: 'porto is the last PT city');
      expect(await check(collection.orderBy('country').startAtDocument(porto)),
          <String>['porto']);
    });

    test('cursors with limits', () async {
      final Query<Map<String, Object?>> ascending =
          collection.orderBy('population');
      await check(ascending.startAfter(<Object?>[232000]).limit(2));
      expect(
          await check(ascending.endBefore(<Object?>[2800000]).limitToLast(2)),
          <String>['milan', 'paris']);
      expect(
          await check(ascending.startAt(<Object?>[545000]).endAt(
              <Object?>[2800000]).limitToLast(2)),
          <String>['paris', 'rome']);
      await check(collection
          .orderBy('population', Direction.descending)
          .startAfter(<Object?>[14000000]).limitToLast(2));
    });

    test('collection groups', () async {
      final String groupId = 'districts_${autoId()}';
      Future<void> add(String city, String id, int size) => collection
          .doc(city)
          .collection(groupId)
          .doc(id)
          .set(<String, Object?>{'size': size, 'city': city});
      await add('lisbon', 'alfama', 3);
      await add('lisbon', 'belem', 9);
      await add('rome', 'trastevere', 5);
      await add('tokyo', 'shibuya', 7);

      final Query<Map<String, Object?>> group =
          firestore.collectionGroup(groupId);
      expect(await check(group), hasLength(4));
      await check(group.where('size', isGreaterThan: 4));
      await check(group.orderBy('size', Direction.descending).limit(2));
      await check(
          group.orderBy('size').startAfter(<Object?>[3]).limitToLast(2));
      await check(group
          .where('city', whereIn: <String>['lisbon', 'rome']).orderBy('size'));
    });

    test('a query with a converter', () async {
      final Query<String> names = collection
          .where('country', isEqualTo: 'PT')
          .withConverter<String>(FirestoreDataConverter<String>.from(
            fromFirestore: (DocumentSnapshot<Map<String, Object?>> snapshot,
                    SnapshotOptions? options) =>
                snapshot.id,
            toFirestore: (String value, SetOptions? options) =>
                <String, Object?>{},
          ));
      final PipelineSnapshot snapshot =
          await firestore.pipeline().createFrom(names).execute();
      expect(<String?>[for (final PipelineResult r in snapshot.results) r.id],
          <String>['lisbon', 'porto']);
      // The converter of the query does not apply to pipeline results.
      expect(snapshot.results.first.data()['country'], 'PT');
    });

    test('BSON operands', () async {
      final CollectionReference<Map<String, Object?>> bson =
          firestore.collection('bson_${autoId()}');
      final Map<String, Object?> values = <String, Object?>{
        'min': MinKey.instance,
        'int32a': Int32Value(1),
        'int32b': Int32Value(7),
        'decimal': Decimal128Value('2.5'),
        'int': 4,
        'oid1': BsonObjectId('507f191e810c19729de860ea'),
        'oid2': BsonObjectId('507f191e810c19729de860eb'),
        'ts1': BsonTimestamp(1, 1),
        'ts2': BsonTimestamp(1, 2),
        'regex': const RegexValue('^foo', 'i'),
        'max': MaxKey.instance,
      };
      for (final MapEntry<String, Object?> entry in values.entries) {
        await bson.doc(entry.key).set(<String, Object?>{'v': entry.value});
      }
      Future<List<String>> checkBson(Query<Map<String, Object?>> query,
              {bool allowEmpty = false}) =>
          check(query, allowEmpty: allowEmpty);

      expect(await checkBson(bson.orderBy('v')), hasLength(values.length));
      await checkBson(bson.orderBy('v', Direction.descending));
      await checkBson(bson.where('v', isEqualTo: Int32Value(7)));
      await checkBson(bson.where('v', isGreaterThan: Int32Value(1)));
      await checkBson(
          bson.where('v', isLessThanOrEqualTo: Decimal128Value('2.5')));
      await checkBson(bson.where('v', isEqualTo: Decimal128Value('2.5')));
      await checkBson(bson.where('v',
          isGreaterThan: BsonObjectId('507f191e810c19729de860ea')));
      await checkBson(bson.where('v', isLessThan: BsonTimestamp(1, 2)));
      await checkBson(
          bson.where('v', isEqualTo: const RegexValue('^foo', 'i')));
      await checkBson(bson.where('v', isEqualTo: MinKey.instance));
      await checkBson(bson.where('v', isEqualTo: MaxKey.instance));
      await checkBson(bson.where('v', isNotEqualTo: MaxKey.instance));
      await checkBson(bson.where('v',
          whereIn: <Object?>[Int32Value(1), BsonTimestamp(1, 1), 4]));
      await checkBson(bson
          .where('v', whereNotIn: <Object?>[Int32Value(1), MinKey.instance]));
      // Cursors inside one type.
      await checkBson(bson
          .where('v', isGreaterThanOrEqualTo: Int32Value(1))
          .orderBy('v')
          .startAfter(<Object?>[Int32Value(1)]));
      await checkBson(bson
          .where('v', isGreaterThanOrEqualTo: BsonTimestamp(0, 0))
          .orderBy('v', Direction.descending)
          .startAfter(<Object?>[BsonTimestamp(1, 2)]));
    });

    test('filters on a field with values of several types', () async {
      final CollectionReference<Map<String, Object?>> mixed =
          firestore.collection('mixed_${autoId()}');
      final Map<String, Object?> values = <String, Object?>{
        'null': null,
        'nan': double.nan,
        'one': 1,
        'two': 2,
        'string': 'x',
        'array': <Object?>[null, 1],
      };
      for (final MapEntry<String, Object?> entry in values.entries) {
        await mixed.doc(entry.key).set(<String, Object?>{'v': entry.value});
      }
      await mixed.doc('missing').set(<String, Object?>{'w': 1});

      expect(await check(mixed.orderBy('v')), values.keys);
      expect(await check(mixed.where('v', isNull: true)), <String>['null']);
      expect(await check(mixed.where('v', isNull: false)),
          <String>['nan', 'one', 'two', 'string', 'array']);
      expect(await check(mixed.where('v', isEqualTo: double.nan)),
          <String>['nan']);
      // != and not-in match neither null nor a missing field.
      expect(await check(mixed.where('v', isNotEqualTo: 1)),
          <String>['nan', 'two', 'string', 'array']);
      expect(await check(mixed.where('v', isNotEqualTo: double.nan)),
          <String>['one', 'two', 'string', 'array']);
      expect(await check(mixed.where('v', whereNotIn: <Object?>[1, 2])),
          <String>['nan', 'string', 'array']);
      expect(await check(mixed.where('v', whereNotIn: <Object?>[1])),
          <String>['nan', 'two', 'string', 'array']);
      expect(await check(mixed.where('v', whereIn: <Object?>[null, 1])),
          <String>['null', 'one']);
      expect(await check(mixed.where('v', isGreaterThan: 0)),
          <String>['one', 'two']);
      // Array filters skip values that are not arrays.
      expect(
          await check(mixed.where('v', arrayContains: 1)), <String>['array']);
      expect(
          await check(mixed.where('v', arrayContainsAny: <Object?>[null, 7])),
          <String>['array']);
      expect(
          await check(mixed.where(Filter.or(<Filter>[
            Filter.arrayContains('v', 1),
            Filter.equalTo('v', 'x'),
          ]))),
          <String>['array', 'string']);
    });

    // A classic cursor is a position in the order of all types; the pipeline
    // comparison only matches values of the cursor's type. See the note on
    // createFrom in the README.
    test('known difference: cursors on a field with values of several types',
        () async {
      final CollectionReference<Map<String, Object?>> mixed =
          firestore.collection('mixed_${autoId()}');
      final Map<String, Object?> values = <String, Object?>{
        'null': null,
        'one': 1,
        'two': 2,
        'string': 'x',
      };
      for (final MapEntry<String, Object?> entry in values.entries) {
        await mixed.doc(entry.key).set(<String, Object?>{'v': entry.value});
      }
      Future<List<String?>> pipelineIds(
              Query<Map<String, Object?>> query) async =>
          <String?>[
            for (final PipelineResult r
                in (await firestore.pipeline().createFrom(query).execute())
                    .results)
              r.id
          ];
      Future<List<String>> classicIds(
              Query<Map<String, Object?>> query) async =>
          <String>[
            for (final QueryDocumentSnapshot<Map<String, Object?>> d
                in (await query.get(Source.server)).docs)
              d.id
          ];

      final Query<Map<String, Object?>> startAt =
          mixed.orderBy('v').startAt(<Object?>[2]);
      expect(await classicIds(startAt), <String>['two', 'string']);
      expect(await pipelineIds(startAt), <String>['two']);

      final Query<Map<String, Object?>> endAt =
          mixed.orderBy('v').endAt(<Object?>[1]);
      expect(await classicIds(endAt), <String>['null', 'one']);
      expect(await pipelineIds(endAt), <String>['one']);
    });
  }, skip: skip);

  group('createFromAggregateQuery', () {
    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      collection = firestore.collection('cities_${autoId()}');
      final WriteBatch batch = firestore.batch();
      cities.forEach((String id, Map<String, Object?> data) {
        batch.set(collection.doc(id), data);
      });
      await batch.commit();
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await IntegrationTestUtil.tearDown();
    });

    Future<Map<String, Object?>> run(AggregateQuery query) async {
      return (await firestore
              .pipeline()
              .createFromAggregateQuery(query)
              .execute())
          .results
          .single
          .data();
    }

    test('count', () async {
      final AggregateQuery query =
          collection.where('country', isEqualTo: 'IT').count();
      expect(await run(query), <String, Object?>{'count': 2});
      expect((await query.get()).getCount(), 2);
    });

    test('count, sum and average', () async {
      final AggregateField sum = AggregateField.sum('population');
      final AggregateField average = AggregateField.average('geo.elevation');
      final AggregateQuery query = collection
          .where('tags', arrayContains: 'capital')
          .aggregate(<AggregateField>[AggregateField.count(), sum, average]);
      final AggregateQuerySnapshot classic = await query.get();

      final Map<String, Object?> row = await run(query);
      expect(
          row.keys,
          unorderedEquals(
              <String>['count', 'sum_population', 'average_geo.elevation']));
      expect(row['count'], classic.getCount());
      expect(row['sum_population'], classic.getInt(sum));
      expect(row['average_geo.elevation'], classic.getDouble(average));
    });

    test('aliases', () async {
      final AggregateQuery query =
          collection.aggregateWithAliases(<String, AggregateField>{
        'cities': AggregateField.count(),
        'people': AggregateField.sum('population'),
      });
      expect(await run(query), (await query.get()).data());
    });

    test('an aggregate over a limited query', () async {
      final AggregateQuery query =
          collection.orderBy('population').limit(2).aggregate(<AggregateField>[
        AggregateField.sum('population'),
      ]);
      expect(await run(query),
          <String, Object?>{'sum_population': 232000 + 545000});
    });

    test('aggregates over nothing', () async {
      final AggregateField sum = AggregateField.sum('population');
      final AggregateField average = AggregateField.average('population');
      final AggregateQuery query = collection
          .where('country', isEqualTo: 'nowhere')
          .aggregate(<AggregateField>[sum, average, AggregateField.count()]);
      final AggregateQuerySnapshot classic = await query.get();
      expect(await run(query), <String, Object?>{
        'sum_population': classic.get(sum),
        'average_population': classic.get(average),
        'count': 0,
      });
    });
  }, skip: skip);

  group('createFromVectorQuery', () {
    late CollectionReference<Map<String, Object?>> vectors;

    setUp(() async {
      firestore = await IntegrationTestUtil.testEnterpriseFirestore();
      vectors = firestore.collection('vectors_${autoId()}');
      final Map<String, Map<String, Object?>> docs =
          <String, Map<String, Object?>>{
        'a': <String, Object?>{
          'kind': 'x',
          'embedding': VectorValue(<double>[1, 0])
        },
        'b': <String, Object?>{
          'kind': 'x',
          'embedding': VectorValue(<double>[0.8, 0.6])
        },
        'c': <String, Object?>{
          'kind': 'y',
          'embedding': VectorValue(<double>[0, 1])
        },
        'd': <String, Object?>{
          'kind': 'y',
          'embedding': VectorValue(<double>[3, 4])
        },
        'none': <String, Object?>{'kind': 'x'},
      };
      for (final MapEntry<String, Map<String, Object?>> doc in docs.entries) {
        await vectors.doc(doc.key).set(doc.value);
      }
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await IntegrationTestUtil.tearDown();
    });

    Future<List<String>> checkVector(VectorQuery query,
        {String? distanceField}) async {
      final VectorQuerySnapshot classic = await query.get();
      final PipelineSnapshot snapshot =
          await firestore.pipeline().createFromVectorQuery(query).execute();
      final List<String> expected = <String>[
        for (final QueryDocumentSnapshot<Object?> doc in classic.docs) doc.id
      ];
      expect(<String?>[for (final PipelineResult r in snapshot.results) r.id],
          expected);
      expect(expected, isNotEmpty);
      for (int i = 0; i < expected.length; i++) {
        final Map<String, Object?> classicData =
            classic.docs[i].data! as Map<String, Object?>;
        expect(
            snapshot.results[i].data().keys, unorderedEquals(classicData.keys));
        if (distanceField != null) {
          expect(snapshot.results[i].get(distanceField),
              closeTo(classicData[distanceField]! as double, 1e-9));
        }
      }
      return expected;
    }

    test('every distance measure', () async {
      for (final DistanceMeasure measure in DistanceMeasure.values) {
        await checkVector(
            vectors.findNearest('embedding', <double>[1, 0], 3, measure));
      }
    });

    test('over a filtered query', () async {
      expect(
          await checkVector(vectors.where('kind', isEqualTo: 'y').findNearest(
              'embedding', <double>[1, 0], 5, DistanceMeasure.euclidean)),
          <String>['c', 'd']);
    });

    test('distanceResultField', () async {
      await checkVector(
          vectors.findNearest(
              'embedding', <double>[1, 0], 4, DistanceMeasure.euclidean,
              distanceResultField: 'distance'),
          distanceField: 'distance');
    });

    test('distanceThreshold', () async {
      expect(
          await checkVector(vectors.findNearest(
              'embedding', <double>[1, 0], 4, DistanceMeasure.euclidean,
              distanceThreshold: 1)),
          <String>['a', 'b']);
      expect(
          await checkVector(
              vectors.findNearest(
                  'embedding', <double>[1, 0], 4, DistanceMeasure.dotProduct,
                  distanceResultField: 'similarity', distanceThreshold: 0.9),
              distanceField: 'similarity'),
          <String>['d', 'a']);
    });
  }, skip: skip);
}
