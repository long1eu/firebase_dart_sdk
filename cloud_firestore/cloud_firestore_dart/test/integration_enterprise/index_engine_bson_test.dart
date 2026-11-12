// Persistent cache indexes end to end with BSON operands, on the Enterprise edition emulator (only that edition
// stores the BSON types): an index is configured and filled, and cache queries served by the index are compared with
// the server, with and without pending writes. See test/util/index_engine_harness.dart.
//
// Start the Enterprise edition emulator with `tool/start_enterprise_emulator.sh` and point
// FIRESTORE_ENTERPRISE_EMULATOR_HOST at it (`host:port`) to run these tests.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../util/index_engine_harness.dart';
import '../util/integration_test_util.dart';

Blob _binary(int subtype, List<int> bytes) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(bytes));

void main() {
  IntegrationTestUtil.currentDatabasePath =
      'integration_enterprise/index_engine_bson';

  final String? skip = IntegrationTestUtil.enterpriseEmulatorSkipReason;

  late Firestore firestore;
  int collectionIndex = 0;

  setUp(() async {
    if (skip != null) {
      return;
    }
    firestore = await IntegrationTestUtil.testEnterpriseFirestore();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  CollectionReference<Map<String, Object?>> testCollection() {
    return firestore.collection(
      'index-bson-${DateTime.now().microsecondsSinceEpoch}-${collectionIndex++}',
    );
  }

  // One field `v` with values of every BSON type and of the types that sort around them.
  final Docs docs = <String, Map<String, Object?>>{
    'null': <String, Object?>{'v': null},
    'minKey': <String, Object?>{'v': MinKey.instance},
    'true': <String, Object?>{'v': true},
    'int32-1': <String, Object?>{'v': Int32Value(1)},
    'int32-2': <String, Object?>{'v': Int32Value(2)},
    'long-2': <String, Object?>{'v': 2},
    'decimal-2.5': <String, Object?>{'v': Decimal128Value('2.5')},
    'double-3.5': <String, Object?>{'v': 3.5},
    'decimal-neg': <String, Object?>{'v': Decimal128Value('-1.2e3')},
    'timestamp': <String, Object?>{'v': Timestamp(100, 0)},
    'bsonTs-1-2': <String, Object?>{'v': BsonTimestamp(1, 2)},
    'bsonTs-1-3': <String, Object?>{'v': BsonTimestamp(1, 3)},
    // Seconds on both sides of 2^31, where the index encoding of the Android SDK wraps.
    'bsonTs-2^31-1': <String, Object?>{'v': BsonTimestamp(2147483647, 9)},
    'bsonTs-2^31': <String, Object?>{'v': BsonTimestamp(2147483648, 0)},
    'bsonTs-max': <String, Object?>{'v': BsonTimestamp(4294967295, 4294967295)},
    'string': <String, Object?>{'v': 'text'},
    'blob': <String, Object?>{
      'v': _binary(0, <int>[1, 2, 3]),
    },
    'binary-1': <String, Object?>{
      'v': _binary(1, <int>[1, 2, 3]),
    },
    'binary-128': <String, Object?>{
      'v': _binary(128, <int>[0]),
    },
    'oid-a': <String, Object?>{
      'v': const BsonObjectId('507f191e810c19729de860ea'),
    },
    'oid-b': <String, Object?>{
      'v': const BsonObjectId('507f191e810c19729de860eb'),
    },
    'regex-a': <String, Object?>{'v': const RegexValue('^foo', 'i')},
    'regex-b': <String, Object?>{'v': const RegexValue('^foo', 'm')},
    'array': <String, Object?>{
      'v': <Object?>[
        Int32Value(1),
        const BsonObjectId('507f191e810c19729de860ea'),
      ],
    },
    'maxKey': <String, Object?>{'v': MaxKey.instance},
    'missing': <String, Object?>{'other': 1},
  };

  test(
    'cache queries with BSON operands served by an index agree with the server',
    skip: skip,
    () async {
      await checkIndexedQueries(
        firestore: firestore,
        collection: testCollection(),
        docs: docs,
        indexes: <List<String>>[
          <String>['v'],
          <String>['v desc'],
          <String>['v contains'],
        ],
        queries: <IndexedQuery>[
          IndexedQuery('order by v', (c) => c.orderBy('v')),
          IndexedQuery(
            'order by v desc',
            (c) => c.orderBy('v', Direction.descending),
          ),
          IndexedQuery('order by v, limit 5', (c) => c.orderBy('v').limit(5)),
          IndexedQuery(
            'order by v, limitToLast 5',
            (c) => c.orderBy('v').limitToLast(5),
          ),
          // Numbers of every type compare by value.
          IndexedQuery(
            'v == Int32(2)',
            (c) => c.whereEqualTo('v', Int32Value(2)),
          ),
          IndexedQuery(
            'v > Int32(1)',
            (c) => c.whereGreaterThan('v', Int32Value(1)),
          ),
          IndexedQuery(
            'v <= Decimal128(2.5)',
            (c) => c.whereLessThanOrEqualTo('v', Decimal128Value('2.5')),
          ),
          IndexedQuery(
            'v < Decimal128(2.5)',
            (c) => c.whereLessThan('v', Decimal128Value('2.5')),
          ),
          IndexedQuery(
            'v >= 2, order by v desc',
            (c) => c
                .whereGreaterThanOrEqualTo('v', 2)
                .orderBy('v', Direction.descending),
          ),
          // BSON timestamps, on both sides of 2^31 seconds.
          IndexedQuery(
            'v == BsonTimestamp(1, 2)',
            (c) => c.whereEqualTo('v', BsonTimestamp(1, 2)),
          ),
          IndexedQuery(
            'v > BsonTimestamp(1, 2)',
            (c) => c.whereGreaterThan('v', BsonTimestamp(1, 2)),
          ),
          IndexedQuery(
            'v >= BsonTimestamp(2^31, 0)',
            (c) =>
                c.whereGreaterThanOrEqualTo('v', BsonTimestamp(2147483648, 0)),
          ),
          IndexedQuery(
            'v < BsonTimestamp(2^31, 0)',
            (c) => c.whereLessThan('v', BsonTimestamp(2147483648, 0)),
          ),
          IndexedQuery(
            'v <= BsonTimestamp(max)',
            (c) => c.whereLessThanOrEqualTo(
              'v',
              BsonTimestamp(4294967295, 4294967295),
            ),
          ),
          // Object ids.
          IndexedQuery(
            'v == ObjectId(a)',
            (c) => c.whereEqualTo(
              'v',
              const BsonObjectId('507f191e810c19729de860ea'),
            ),
          ),
          IndexedQuery(
            'v > ObjectId(a)',
            (c) => c.whereGreaterThan(
              'v',
              const BsonObjectId('507f191e810c19729de860ea'),
            ),
          ),
          IndexedQuery(
            'v <= ObjectId(b)',
            (c) => c.whereLessThanOrEqualTo(
              'v',
              const BsonObjectId('507f191e810c19729de860eb'),
            ),
          ),
          // Binary data: subtype 0 is a plain blob, the other subtypes sort after it.
          IndexedQuery(
            'v >= Blob',
            (c) => c.whereGreaterThanOrEqualTo('v', _binary(0, <int>[1, 2, 3])),
          ),
          IndexedQuery(
            'v > Binary(1)',
            (c) => c.whereGreaterThan('v', _binary(1, <int>[1, 2, 3])),
          ),
          IndexedQuery(
            'v < Binary(128)',
            (c) => c.whereLessThan('v', _binary(128, <int>[0])),
          ),
          // Regular expressions.
          IndexedQuery(
            'v == Regex(^foo, i)',
            (c) => c.whereEqualTo('v', const RegexValue('^foo', 'i')),
          ),
          IndexedQuery(
            'v > Regex(^foo, i)',
            (c) => c.whereGreaterThan('v', const RegexValue('^foo', 'i')),
          ),
          // Min and max key.
          IndexedQuery(
            'v == MinKey',
            (c) => c.whereEqualTo('v', MinKey.instance),
          ),
          IndexedQuery(
            'v == MaxKey',
            (c) => c.whereEqualTo('v', MaxKey.instance),
          ),
          IndexedQuery(
            'v >= MinKey',
            (c) => c.whereGreaterThanOrEqualTo('v', MinKey.instance),
          ),
          IndexedQuery(
            'v <= MaxKey',
            (c) => c.whereLessThanOrEqualTo('v', MaxKey.instance),
          ),
          // Membership.
          IndexedQuery(
            'v in [Int32(1), ObjectId(b), BsonTimestamp(2^31, 0), MaxKey]',
            (c) => c.whereIn('v', <Object?>[
              Int32Value(1),
              const BsonObjectId('507f191e810c19729de860eb'),
              BsonTimestamp(2147483648, 0),
              MaxKey.instance,
            ]),
          ),
          IndexedQuery(
            'v not-in [Int32(1), Regex(^foo, i), MinKey]',
            (c) => c.whereNotIn('v', <Object?>[
              Int32Value(1),
              const RegexValue('^foo', 'i'),
              MinKey.instance,
            ]),
          ),
          IndexedQuery(
            'v != Int32(2)',
            (c) => c.whereNotEqualTo('v', Int32Value(2)),
          ),
          IndexedQuery(
            'v array-contains ObjectId(a)',
            (c) => c.whereArrayContains(
              'v',
              const BsonObjectId('507f191e810c19729de860ea'),
            ),
          ),
          IndexedQuery(
            'v array-contains-any [Int32(1), Regex]',
            (c) => c.whereArrayContainsAny('v', <Object?>[
              Int32Value(1),
              const RegexValue('x', ''),
            ]),
          ),
          IndexedQuery(
            'v == Int32(1) or v >= BsonTimestamp(2^31, 0)',
            (c) => c.where(
              Filter.or(<Filter>[
                Filter.equalTo('v', Int32Value(1)),
                Filter.greaterThanOrEqualTo('v', BsonTimestamp(2147483648, 0)),
              ]),
            ),
          ),
          // Cursors.
          IndexedQuery(
            'order by v, startAt BsonTimestamp(1, 3)',
            (c) => c.orderBy('v').startAt(<Object?>[BsonTimestamp(1, 3)]),
          ),
          IndexedQuery(
            'order by v, startAfter BsonTimestamp(2^31 - 1), endAt ObjectId(a)',
            (c) => c
                .orderBy('v')
                .startAfter(<Object?>[BsonTimestamp(2147483647, 9)])
                .endAt(<Object?>[
                  const BsonObjectId('507f191e810c19729de860ea'),
                ]),
          ),
          IndexedQuery(
            'order by v desc, startAt MaxKey, endBefore Decimal128(2.5)',
            (c) => c
                .orderBy('v', Direction.descending)
                .startAt(<Object?>[MaxKey.instance])
                .endBefore(<Object?>[Decimal128Value('2.5')]),
          ),
        ],
        pendingWrites: (CollectionReference<Map<String, Object?>> c) async {
          c.doc('pending-int32').set(<String, Object?>{
            'v': Int32Value(2),
          }).ignore();
          c.doc('pending-bsonTs').set(<String, Object?>{
            'v': BsonTimestamp(3000000000, 1),
          }).ignore();
          c.doc('oid-a').update(<String, Object?>{
            'v': const BsonObjectId('ffffffffffffffffffffffff'),
          }).ignore();
          c.doc('regex-b').delete().ignore();
          c.doc('maxKey').set(<String, Object?>{'other': 2}).ignore();
        },
        affectedByPendingWrites: <String>[
          'order by v',
          'v == Int32(2)',
          'v >= BsonTimestamp(2^31, 0)',
          'v > ObjectId(a)',
          'v > Regex(^foo, i)',
          'v == MaxKey',
        ],
      );
    },
  );
}
