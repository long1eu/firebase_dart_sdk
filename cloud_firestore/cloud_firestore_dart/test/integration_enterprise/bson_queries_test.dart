// BSON values in pipeline results and expressions, and in the results of
// aggregations. Needs the Enterprise edition emulator
// (`tool/start_enterprise_emulator.sh`), see `enterprise_emulator_smoke_test.dart`.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/bson_queries';

  final String? skip = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  late Firestore firestore;

  setUp(() async {
    firestore = await IntegrationTestUtil.testEnterpriseFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  Future<CollectionReference> collectionWith(List<Object?> values) async {
    final CollectionReference collection =
        firestore.collection('bson_queries_${autoId()}');
    for (int i = 0; i < values.length; i++) {
      await collection.document('d$i').set(<String, Object?>{'v': values[i]});
    }
    return collection;
  }

  group('pipelines', () {
    final Map<String, Object?> allTypes = <String, Object?>{
      'minKey': MinKey.instance,
      'maxKey': MaxKey.instance,
      'int32': Int32Value(-7),
      'decimal128': Decimal128Value('1.2e3'),
      'oid': BsonObjectId('507f191e810c19729de860ea'),
      'timestamp': BsonTimestamp(1, 2),
      'regex': const RegexValue('^foo', 'i'),
      'binary': Blob.bsonBinary(128, Uint8List.fromList(<int>[1, 2, 3])),
      'nested': <String, Object?>{
        'array': <Object?>[Int32Value(1), MaxKey.instance],
      },
    };

    test('results return the BSON value classes', () async {
      final CollectionReference collection =
          firestore.collection('bson_queries_${autoId()}');
      await collection.document('doc').set(allTypes);

      final PipelineSnapshot snapshot =
          await firestore.pipeline().collection(collection.path).execute();
      final PipelineResult result = snapshot.results.single;
      expect(result.data(), allTypes);
      expect(result.get('int32'), isA<Int32Value>());
      expect(result.get('decimal128'), isA<Decimal128Value>());
      expect(result.get('minKey'), same(MinKey.instance));
      expect(result.get('maxKey'), same(MaxKey.instance));
      expect((result.get('binary')! as Blob).subtype, 128);
      expect(result.get('nested.array'),
          <Object?>[Int32Value(1), MaxKey.instance]);

      // The same document read with a get() has the same data.
      final DocumentSnapshot document =
          await collection.document('doc').get(Source.server);
      expect(result.data(), document.data);
    });

    test('selected and computed fields keep their BSON type', () async {
      final CollectionReference collection =
          firestore.collection('bson_queries_${autoId()}');
      await collection.document('doc').set(allTypes);

      final PipelineSnapshot snapshot = await firestore
          .pipeline()
          .collection(collection.path)
          .select(<Object>[
        'oid',
        field('regex').as('renamed'),
        constant(Int32Value(5)).as('int32Constant'),
        constant(Decimal128Value('0.1')).as('decimalConstant'),
        constant(BsonTimestamp(3, 4)).as('timestampConstant'),
        constant(MinKey.instance).as('minConstant'),
      ]).execute();
      expect(snapshot.results.single.data(), <String, Object?>{
        'oid': BsonObjectId('507f191e810c19729de860ea'),
        'renamed': const RegexValue('^foo', 'i'),
        'int32Constant': Int32Value(5),
        'decimalConstant': Decimal128Value('0.1'),
        'timestampConstant': BsonTimestamp(3, 4),
        'minConstant': MinKey.instance,
      });
    });

    test('filters and sorts by BSON values', () async {
      final CollectionReference collection = await collectionWith(<Object?>[
        Int32Value(1),
        2,
        Decimal128Value('2.5'),
        3.5,
        BsonObjectId('507f191e810c19729de860ea'),
        MinKey.instance,
        MaxKey.instance,
      ]);
      List<String?> ids(PipelineSnapshot snapshot) =>
          snapshot.results.map((PipelineResult r) => r.id).toList();

      expect(
          ids(await firestore
              .pipeline()
              .collection(collection.path)
              .where(field('v').greaterThan(Int32Value(1)))
              .sort(<Ordering>[field('v').descending()]).execute()),
          <String>['d3', 'd2', 'd1']);
      expect(
          ids(await firestore
              .pipeline()
              .collection(collection.path)
              .where(field('v').lessThanOrEqual(Decimal128Value('2.5')))
              .sort(<Ordering>[field('v').ascending()]).execute()),
          <String>['d0', 'd1', 'd2']);
      expect(
          ids(await firestore
              .pipeline()
              .collection(collection.path)
              .where(field('v').equal(BsonObjectId('507f191e810c19729de860ea')))
              .execute()),
          <String>['d4']);
      expect(
          ids(await firestore
              .pipeline()
              .collection(collection.path)
              .sort(<Ordering>[field('v').ascending()]).execute()),
          <String>['d5', 'd0', 'd1', 'd2', 'd3', 'd4', 'd6']);
    });

    test('aggregates over BSON numbers', () async {
      Future<Map<String, Object?>> aggregate(List<Object?> values) async {
        final CollectionReference collection = await collectionWith(values);
        final PipelineSnapshot snapshot = await firestore
            .pipeline()
            .collection(collection.path)
            .aggregate(<AliasedAggregate>[
          field('v').sum().as('sum'),
          field('v').average().as('avg'),
          field('v').minimum().as('min'),
          field('v').maximum().as('max'),
          field('v').count().as('count'),
        ]).execute();
        return snapshot.results.single.data();
      }

      // 32-bit integers add up to a 64-bit integer.
      expect(
          await aggregate(
              <Object?>[Int32Value(2147483647), Int32Value(2147483647)]),
          <String, Object?>{
            'sum': 4294967294,
            'avg': 2147483647.0,
            'min': Int32Value(2147483647),
            'max': Int32Value(2147483647),
            'count': 2,
          });
      expect(await aggregate(<Object?>[Int32Value(1), 2.5]), <String, Object?>{
        'sum': 3.5,
        'avg': 1.75,
        'min': Int32Value(1),
        'max': 2.5,
        'count': 2,
      });
      // A decimal makes the sum and the average a decimal.
      expect(
          await aggregate(
              <Object?>[Int32Value(1), 2, 2.5, Decimal128Value('0.5')]),
          <String, Object?>{
            'sum': Decimal128Value('6'),
            'avg': Decimal128Value('1.5'),
            'min': Decimal128Value('0.5'),
            'max': 2.5,
            'count': 4,
          });
      expect(
          await aggregate(
              <Object?>[Decimal128Value('1.1'), Decimal128Value('2.2')]),
          <String, Object?>{
            'sum': Decimal128Value('3.3'),
            'avg': Decimal128Value('1.65'),
            'min': Decimal128Value('1.1'),
            'max': Decimal128Value('2.2'),
            'count': 2,
          });
      // The minimum and the maximum follow the order of the types.
      expect(
          await aggregate(<Object?>[
            MinKey.instance,
            BsonObjectId('507f191e810c19729de860ea'),
            BsonTimestamp(1, 2),
            const RegexValue('a', 'i'),
            MaxKey.instance,
          ]),
          <String, Object?>{
            'sum': null,
            'avg': null,
            'min': MinKey.instance,
            'max': MaxKey.instance,
            'count': 5,
          });
    });
  }, skip: skip);

  group('plain maps shaped like a BSON value', () {
    test('are that BSON value in a query', () async {
      final CollectionReference collection = await collectionWith(<Object?>[
        Int32Value(5),
        5,
        Int32Value(6),
        BsonObjectId('507f191e810c19729de860ea'),
      ]);
      final Map<String, Map<String, Object?>> docs =
          <String, Map<String, Object?>>{
        'd0': <String, Object?>{'v': Int32Value(5)},
        'd1': <String, Object?>{'v': 5},
        'd2': <String, Object?>{'v': Int32Value(6)},
        'd3': <String, Object?>{'v': BsonObjectId('507f191e810c19729de860ea')},
      };

      // The backend and the local cache agree, from the cache and in a
      // listener.
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          collection,
          collection.whereEqualTo('v', <String, Object?>{'__int__': 5}),
          docs,
          <String>['d0', 'd1']);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          collection,
          collection.whereGreaterThan('v', <String, Object?>{'__int__': 5}),
          docs,
          <String>['d2']);
      await IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
          collection,
          collection.whereIn('v', <Object?>[
            <String, Object?>{'__oid__': '507f191e810c19729de860ea'},
            <String, Object?>{'__int__': 6},
          ]),
          docs,
          <String>['d2', 'd3']);
    });

    test('are rejected in document data', () async {
      final DocumentReference document =
          firestore.collection('bson_queries_${autoId()}').document('doc');
      expect(
          () => document.set(<String, Object?>{
                'v': <String, Object?>{'__int__': 5}
              }),
          throwsArgumentError);
      expect((await document.get(Source.server)).exists, isFalse);
    });

    test('are that BSON value in an array transform', () async {
      final DocumentReference document =
          firestore.collection('bson_queries_${autoId()}').document('doc');
      await document.set(<String, Object?>{
        'l': <Object?>[Int32Value(5)]
      });
      await document.update(<String, Object?>{
        'l': FieldValue.arrayUnion(<Object?>[
          <String, Object?>{'__int__': 5},
          <String, Object?>{'__int__': 6},
        ])
      });
      // The local view and the backend hold the same values.
      final List<Object?> expected = <Object?>[Int32Value(5), Int32Value(6)];
      expect((await document.get(Source.cache)).get('l'), expected);
      expect((await document.get(Source.server)).get('l'), expected);
    });
  }, skip: skip);

  group('aggregation queries', () {
    final AggregateField sum = AggregateField.sum('v');
    final AggregateField average = AggregateField.average('v');

    Future<AggregateQuerySnapshot> aggregate(List<Object?> values) async {
      final CollectionReference collection = await collectionWith(values);
      return collection.aggregate(<AggregateField>[
        sum,
        average,
        AggregateField.count()
      ]).get(AggregateSource.server);
    }

    test('sum and average of 32-bit integers are an int and a double',
        () async {
      AggregateQuerySnapshot snapshot = await aggregate(
          <Object?>[Int32Value(1), Int32Value(2), Int32Value(4)]);
      expect(snapshot.get(sum), 7);
      expect(snapshot.get(average), closeTo(7 / 3, 1e-12));
      expect(snapshot.getInt(sum), 7);
      expect(snapshot.getCount(), 3);

      // The sum does not overflow at 32 bits.
      snapshot = await aggregate(
          <Object?>[Int32Value(2147483647), Int32Value(2147483647)]);
      expect(snapshot.get(sum), 4294967294);
      expect(snapshot.get(average), 2147483647.0);

      snapshot = await aggregate(<Object?>[Int32Value(1), 2]);
      expect(snapshot.get(sum), 3);
      expect(snapshot.get(average), 1.5);

      snapshot = await aggregate(<Object?>[Int32Value(1), 2.5]);
      expect(snapshot.get(sum), 3.5);
      expect(snapshot.get(average), 1.75);
    });

    test('sum and average with a decimal are a Decimal128Value', () async {
      AggregateQuerySnapshot snapshot = await aggregate(
          <Object?>[Decimal128Value('1.1'), Decimal128Value('2.2')]);
      expect(snapshot.get(sum), Decimal128Value('3.3'));
      expect(snapshot.get(average), Decimal128Value('1.65'));
      // The typed getters convert to the closest number.
      expect(snapshot.getDouble(sum), 3.3);
      expect(snapshot.getDouble(average), 1.65);
      expect(snapshot.getInt(sum), 3);
      expect(snapshot.data(), <String, Object?>{
        'sum_v': Decimal128Value('3.3'),
        'average_v': Decimal128Value('1.65'),
        'count': 2,
      });

      snapshot = await aggregate(
          <Object?>[Int32Value(1), 2, 2.5, Decimal128Value('0.5')]);
      expect(snapshot.get(sum), Decimal128Value('6'));
      expect(snapshot.get(average), Decimal128Value('1.5'));
      expect(snapshot.getInt(sum), 6);
      expect(snapshot.getDouble(average), 1.5);

      snapshot = await aggregate(<Object?>[Decimal128Value('NaN'), 1]);
      expect(snapshot.get(sum), Decimal128Value('NaN'));
      expect(snapshot.getDouble(sum), isNaN);
      expect(snapshot.getInt(sum), 0);
    });

    test('the other BSON types are not numbers', () async {
      final AggregateQuerySnapshot snapshot = await aggregate(<Object?>[
        MinKey.instance,
        BsonObjectId('507f191e810c19729de860ea'),
        BsonTimestamp(1, 2),
        const RegexValue('a', 'i'),
        Blob.bsonBinary(3, Uint8List.fromList(<int>[1])),
        MaxKey.instance,
      ]);
      expect(snapshot.getCount(), 6);
      expect(snapshot.get(average), isNull);
      // PORTING NOTE: the emulator (v1.22.0) answers null here, the sum over
      // no numbers of a Standard edition database is 0.
      expect(snapshot.get(sum), anyOf(isNull, 0));
    });
  }, skip: skip);
}
