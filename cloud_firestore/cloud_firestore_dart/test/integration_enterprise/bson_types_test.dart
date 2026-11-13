// Ported from the Android SDK's BsonTypesTest (androidTest) and from the BSON
// cases of its TypeTest.
//
// The BSON types are only stored by databases of the Enterprise edition. Start
// the Enterprise edition emulator with `tool/start_enterprise_emulator.sh` and
// point FIRESTORE_ENTERPRISE_EMULATOR_HOST at it (`host:port`) to run these
// tests.

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../util/integration_test_util.dart';

Blob _binary(int subtype, [List<int> bytes = const <int>[]]) =>
    Blob.bsonBinary(subtype, Uint8List.fromList(bytes));

typedef _Docs = Map<String, Map<String, Object?>>;

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration_enterprise/bson_types';

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

  CollectionReference testCollection() {
    return firestore.collection(
      'bson-${DateTime.now().microsecondsSinceEpoch}-${collectionIndex++}',
    );
  }

  Future<CollectionReference> testCollectionWithDocs(_Docs docs) async {
    final CollectionReference collection = testCollection();
    await IntegrationTestUtil.writeAllDocs(collection, docs);
    return collection;
  }

  Future<void> verifySuccessfulWriteReadCycle(Map<String, Object?> data) async {
    final DocumentReference document = testCollection().document();
    await document.set(data);
    final DocumentSnapshot snapshot = await document.get(Source.server);
    expect(snapshot.data, data);
  }

  Future<void> expectConsistent(
    CollectionReference collection,
    Query query,
    _Docs docs,
    List<String> expected,
  ) {
    return IntegrationTestUtil.assertSDKQueryResultsConsistentWithBackend(
      collection,
      query,
      docs,
      expected,
    );
  }

  Matcher throwsInvalidArgument(String message) {
    return throwsA(
      isA<FirestoreError>()
          .having(
            (FirestoreError e) => e.code,
            'code',
            FirestoreErrorCode.invalidArgument,
          )
          .having(
            (FirestoreError e) => e.message,
            'message',
            contains(message),
          ),
    );
  }

  Map<String, Object?> allTypes() {
    return <String, Object?>{
      'bsonObjectId': BsonObjectId('507f191e810c19729de860ea'),
      'regex': const RegexValue('^foo', 'i'),
      'bsonTimestamp': BsonTimestamp(1, 2),
      'bsonBinary': _binary(1, <int>[1, 2, 3]),
      'int32': Int32Value(1),
      'decimal128': Decimal128Value('1.2e3'),
      'minKey': MinKey.instance,
      'maxKey': MaxKey.instance,
    };
  }

  group('BsonTypesTest', () {
    test('writeAndReadBsonTypes', () async {
      final DocumentReference docRef = await testCollection().add(allTypes());
      await docRef.set(<String, Object?>{
        'bsonObjectId': BsonObjectId('507f191e810c19729de860eb'),
        'regex': const RegexValue('^foo', 'm'),
        'bsonTimestamp': BsonTimestamp(1, 3),
      }, SetOptions.mergeAllFields);
      await docRef.update(<String, Object?>{'int32': Int32Value(2)});

      final Map<String, Object?> expected = allTypes()
        ..['bsonObjectId'] = BsonObjectId('507f191e810c19729de860eb')
        ..['regex'] = const RegexValue('^foo', 'm')
        ..['bsonTimestamp'] = BsonTimestamp(1, 3)
        ..['int32'] = Int32Value(2);

      final DocumentSnapshot actual = await docRef.get(Source.server);
      expect(actual.get('bsonObjectId'), isA<BsonObjectId>());
      expect(actual.get('regex'), isA<RegexValue>());
      expect(actual.get('bsonTimestamp'), isA<BsonTimestamp>());
      expect(actual.get('bsonBinary'), isA<Blob>());
      expect(actual.get('int32'), isA<Int32Value>());
      expect(actual.get('decimal128'), isA<Decimal128Value>());
      expect(actual.get('minKey'), isA<MinKey>());
      expect(actual.get('maxKey'), isA<MaxKey>());
      expect(actual.data, expected);
    });

    test('writeAndReadBsonTypeOffline', () async {
      final DocumentReference docRef = testCollection().document();
      await firestore.disableNetwork();

      // Adding docs to cache, do not wait for the write to be acknowledged.
      unawaited(docRef.set(allTypes()));
      unawaited(
        docRef.update(<String, Object?>{
          'bsonObjectId': BsonObjectId('507f191e810c19729de860eb'),
          'regex': const RegexValue('^foo', 'm'),
          'bsonTimestamp': BsonTimestamp(1, 3),
        }),
      );

      final Map<String, Object?> expected = allTypes()
        ..['bsonObjectId'] = BsonObjectId('507f191e810c19729de860eb')
        ..['regex'] = const RegexValue('^foo', 'm')
        ..['bsonTimestamp'] = BsonTimestamp(1, 3);

      final DocumentSnapshot actual = await docRef.get(Source.cache);
      expect(actual.data, expected);
      await firestore.enableNetwork();
    });

    test('listenToDocumentsWithBsonTypes', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': MaxKey.instance},
        'b': <String, Object?>{'key': const RegexValue('^foo', 'i')},
        'c': <String, Object?>{'key': BsonObjectId('507f191e810c19729de860ea')},
        'd': <String, Object?>{
          'key': _binary(1, <int>[1, 2, 3]),
        },
        'e': <String, Object?>{'key': BsonTimestamp(1, 2)},
        'f': <String, Object?>{'key': Decimal128Value('1.2e3')},
        'g': <String, Object?>{'key': Int32Value(1)},
        'h': <String, Object?>{'key': MinKey.instance},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);
      final Query query = collection.orderBy('key', Direction.descending);

      final List<QuerySnapshot> snapshots = <QuerySnapshot>[];
      Completer<void> next = Completer<void>();
      final StreamSubscription<QuerySnapshot> subscription = query
          .getSnapshots(MetadataChanges.include)
          .listen((QuerySnapshot snapshot) {
            snapshots.add(snapshot);
            if (!snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites &&
                !next.isCompleted) {
              next.complete();
            }
          });
      try {
        await next.future.timeout(const Duration(seconds: 20));
        expect(IntegrationTestUtil.querySnapshotToIds(snapshots.last), <String>[
          'a',
          'b',
          'c',
          'd',
          'e',
          'f',
          'g',
          'h',
        ]);

        // A document that sorts in the middle moves to its place.
        next = Completer<void>();
        await collection.document('i').set(<String, Object?>{
          'key': BsonTimestamp(1, 3),
        });
        await collection.document('g').set(<String, Object?>{
          'key': Decimal128Value('1.3e3'),
        });
        if (IntegrationTestUtil.querySnapshotToIds(snapshots.last).length !=
                9 ||
            snapshots.last.metadata.hasPendingWrites) {
          await next.future.timeout(const Duration(seconds: 20));
        }
        expect(IntegrationTestUtil.querySnapshotToIds(snapshots.last), <String>[
          'a',
          'b',
          'c',
          'd',
          'i',
          'e',
          'g',
          'f',
          'h',
        ]);
      } finally {
        await subscription.cancel();
      }
    });

    test('filterAndOrderBsonObjectIds', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': BsonObjectId('507f191e810c19729de860ea')},
        'b': <String, Object?>{'key': BsonObjectId('507f191e810c19729de860eb')},
        'c': <String, Object?>{'key': BsonObjectId('507f191e810c19729de860ec')},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereGreaterThan('key', BsonObjectId('507f191e810c19729de860ea')),
        docs,
        <String>['c', 'b'],
      );
      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereNotEqualTo('key', BsonObjectId('507f191e810c19729de860eb')),
        docs,
        <String>['c', 'a'],
      );
    });

    test('filterAndOrderBsonTimestamps', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': BsonTimestamp(1, 1)},
        'b': <String, Object?>{'key': BsonTimestamp(1, 2)},
        'c': <String, Object?>{'key': BsonTimestamp(2, 1)},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereGreaterThan('key', BsonTimestamp(1, 1)),
        docs,
        <String>['c', 'b'],
      );
      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereNotEqualTo('key', BsonTimestamp(1, 2)),
        docs,
        <String>['c', 'a'],
      );
    });

    test('filterAndOrderBlob', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{
          'key': _binary(1, <int>[1, 2, 3]),
        },
        'b': <String, Object?>{
          'key': _binary(1, <int>[1, 2, 4]),
        },
        'c': <String, Object?>{
          'key': _binary(2, <int>[1, 2, 2]),
        },
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereGreaterThan('key', _binary(1, <int>[1, 2, 3])),
        docs,
        <String>['c', 'b'],
      );
      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereNotEqualTo('key', _binary(1, <int>[1, 2, 4])),
        docs,
        <String>['c', 'a'],
      );
    });

    test('filterAndOrderRegex', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': const RegexValue('^bar', 'i')},
        'b': <String, Object?>{'key': const RegexValue('^bar', 'm')},
        'c': <String, Object?>{'key': const RegexValue('^baz', 'i')},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereGreaterThan('key', const RegexValue('^bar', 'i')),
        docs,
        <String>['c', 'b'],
      );
      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereNotEqualTo('key', const RegexValue('^bar', 'm')),
        docs,
        <String>['c', 'a'],
      );
    });

    test('filterAndOrderInt32', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': Int32Value(-1)},
        'b': <String, Object?>{'key': Int32Value(1)},
        'c': <String, Object?>{'key': Int32Value(2)},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereGreaterThan('key', Int32Value(-1)),
        docs,
        <String>['c', 'b'],
      );
      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereNotEqualTo('key', Int32Value(1)),
        docs,
        <String>['c', 'a'],
      );
    });

    test('filterAndOrderDecimal128', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': Decimal128Value('-1.2e3')},
        'b': <String, Object?>{'key': Decimal128Value('0')},
        'c': <String, Object?>{'key': Decimal128Value('1.2e3')},
        'd': <String, Object?>{'key': Decimal128Value('NaN')},
        'e': <String, Object?>{'key': Decimal128Value('-Infinity')},
        'f': <String, Object?>{'key': Decimal128Value('Infinity')},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);
      final Query descending = collection.orderBy('key', Direction.descending);

      await expectConsistent(
        collection,
        descending.whereGreaterThan('key', Decimal128Value('-1.2e3')),
        docs,
        <String>['f', 'c', 'b'],
      );
      await expectConsistent(
        collection,
        descending.whereGreaterThan('key', Decimal128Value('-1.2e-3')),
        docs,
        <String>['f', 'c', 'b'],
      );
      await expectConsistent(
        collection,
        descending.whereNotEqualTo('key', Decimal128Value('0.0')),
        docs,
        <String>['f', 'c', 'a', 'e', 'd'],
      );
      await expectConsistent(
        collection,
        collection.whereNotEqualTo('key', Decimal128Value('NaN')),
        docs,
        <String>['e', 'a', 'b', 'c', 'f'],
      );
      await expectConsistent(
        collection,
        descending.whereEqualTo('key', Decimal128Value('1.2e3')),
        docs,
        <String>['c'],
      );
      await expectConsistent(
        collection,
        descending.whereNotEqualTo('key', Decimal128Value('1.2e3')),
        docs,
        <String>['f', 'b', 'a', 'e', 'd'],
      );
    });

    test('filterAndOrderMinKey', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': MinKey.instance},
        'b': <String, Object?>{'key': MinKey.instance},
        'c': <String, Object?>{'key': null},
        'd': <String, Object?>{'key': 1},
        'e': <String, Object?>{'key': MaxKey.instance},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      // MinKeys are equal, they sort by document id as the secondary order.
      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereEqualTo('key', MinKey.instance),
        docs,
        <String>['b', 'a'],
      );
      await expectConsistent(
        collection,
        collection.whereNotEqualTo('key', MinKey.instance),
        docs,
        <String>['d', 'e'],
      );
      await expectConsistent(
        collection,
        collection.whereGreaterThanOrEqualTo('key', MinKey.instance),
        docs,
        <String>['a', 'b'],
      );
      await expectConsistent(
        collection,
        collection.whereLessThanOrEqualTo('key', MinKey.instance),
        docs,
        <String>['a', 'b'],
      );
      for (final Query empty in <Query>[
        collection.whereGreaterThan('key', MinKey.instance),
        collection.whereLessThan('key', MinKey.instance),
      ]) {
        await expectConsistent(collection, empty, docs, <String>[]);
        expect((await empty.get(Source.server)).isEmpty, isTrue);
      }
    });

    test('filterAndOrderMaxKey', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': MinKey.instance},
        'b': <String, Object?>{'key': 1},
        'c': <String, Object?>{'key': MaxKey.instance},
        'd': <String, Object?>{'key': MaxKey.instance},
        'e': <String, Object?>{'key': null},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection
            .orderBy('key', Direction.descending)
            .whereEqualTo('key', MaxKey.instance),
        docs,
        <String>['d', 'c'],
      );
      await expectConsistent(
        collection,
        collection.whereNotEqualTo('key', MaxKey.instance),
        docs,
        <String>['a', 'b'],
      );
      await expectConsistent(
        collection,
        collection.whereGreaterThanOrEqualTo('key', MaxKey.instance),
        docs,
        <String>['c', 'd'],
      );
      await expectConsistent(
        collection,
        collection.whereLessThanOrEqualTo('key', MaxKey.instance),
        docs,
        <String>['c', 'd'],
      );
      for (final Query empty in <Query>[
        collection.whereLessThan('key', MaxKey.instance),
        collection.whereGreaterThan('key', MaxKey.instance),
      ]) {
        await expectConsistent(collection, empty, docs, <String>[]);
        expect((await empty.get(Source.server)).isEmpty, isTrue);
      }
    });

    test('filterNullValueWithBsonTypes', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': MinKey.instance},
        'b': <String, Object?>{'key': null},
        'c': <String, Object?>{'key': null},
        'd': <String, Object?>{'key': 1},
        'e': <String, Object?>{'key': MaxKey.instance},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection.whereEqualTo('key', null),
        docs,
        <String>['b', 'c'],
      );
      await expectConsistent(
        collection,
        collection.whereNotEqualTo('key', null),
        docs,
        <String>['a', 'd', 'e'],
      );
    });

    test('filterAndOrderNumericalValues', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': Decimal128Value('-1.2e3')},
        'b': <String, Object?>{'key': Int32Value(0)},
        'c': <String, Object?>{'key': Decimal128Value('1')},
        'd': <String, Object?>{'key': Int32Value(1)},
        'e': <String, Object?>{'key': 1},
        'f': <String, Object?>{'key': 1.0},
        'g': <String, Object?>{'key': Decimal128Value('1.2e-3')},
        'h': <String, Object?>{'key': Int32Value(2)},
        'i': <String, Object?>{'key': Decimal128Value('NaN')},
        'j': <String, Object?>{'key': Decimal128Value('-Infinity')},
        'k': <String, Object?>{'key': double.nan},
        'l': <String, Object?>{'key': double.infinity},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);
      final Query descending = collection.orderBy('key', Direction.descending);

      await expectConsistent(collection, descending, docs, <String>[
        'l', // Infinity
        'h', // 2
        'f', // 1.0
        'e', // 1
        'd', // 1
        'c', // 1
        'g', // 0.0012
        'b', // 0
        'a', // -1200
        'j', // -Infinity
        'k', // NaN
        'i', // NaN
      ]);
      await expectConsistent(
        collection,
        descending.whereNotEqualTo('key', Decimal128Value('1.0')),
        docs,
        <String>['l', 'h', 'g', 'b', 'a', 'j', 'k', 'i'],
      );
      await expectConsistent(
        collection,
        descending.whereEqualTo('key', 1),
        docs,
        <String>['f', 'e', 'd', 'c'],
      );
    });

    test('decimal128ValuesWithNo2sComplementRepresentation', () async {
      // A decimal128 without an exact binary representation is not equal to
      // the double with the same decimal digits, for example 1.1.
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': Decimal128Value('-1.1e-3')},
        'b': <String, Object?>{'key': Decimal128Value('1.1')},
        'c': <String, Object?>{'key': 1.1},
        'd': <String, Object?>{'key': 1.0},
        'e': <String, Object?>{'key': Decimal128Value('1.1e-3')},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection.whereEqualTo('key', Decimal128Value('1.1')),
        docs,
        <String>['b'],
      );
      await expectConsistent(
        collection,
        collection.whereNotEqualTo('key', Decimal128Value('1.1')),
        docs,
        <String>['a', 'e', 'd', 'c'],
      );
      await expectConsistent(
        collection,
        collection.whereEqualTo('key', 1.1),
        docs,
        <String>['c'],
      );
      await expectConsistent(
        collection,
        collection.whereNotEqualTo('key', 1.1),
        docs,
        <String>['a', 'e', 'd', 'b'],
      );
    });

    test('orderBsonTypesTogether', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'bsonObjectId1': <String, Object?>{
          'key': BsonObjectId('507f191e810c19729de860ea'),
        },
        'bsonObjectId2': <String, Object?>{
          'key': BsonObjectId('507f191e810c19729de860eb'),
        },
        'bsonObjectId3': <String, Object?>{
          'key': BsonObjectId('407f191e810c19729de860ea'),
        },
        'regex1': <String, Object?>{'key': const RegexValue('^bar', 'm')},
        'regex2': <String, Object?>{'key': const RegexValue('^bar', 'i')},
        'regex3': <String, Object?>{'key': const RegexValue('^baz', 'i')},
        'bsonTimestamp1': <String, Object?>{'key': BsonTimestamp(2, 0)},
        'bsonTimestamp2': <String, Object?>{'key': BsonTimestamp(1, 2)},
        'bsonTimestamp3': <String, Object?>{'key': BsonTimestamp(1, 1)},
        'bsonBinary1': <String, Object?>{
          'key': _binary(1, <int>[1, 2, 3]),
        },
        'bsonBinary2': <String, Object?>{
          'key': _binary(1, <int>[1, 2, 4]),
        },
        'bsonBinary3': <String, Object?>{
          'key': _binary(2, <int>[1, 2, 2]),
        },
        'int32Value1': <String, Object?>{'key': Int32Value(-1)},
        'int32Value2': <String, Object?>{'key': Int32Value(1)},
        'int32Value3': <String, Object?>{'key': Int32Value(0)},
        'decimal128Value1': <String, Object?>{'key': Decimal128Value('-1.2e3')},
        'decimal128Value2': <String, Object?>{'key': Decimal128Value('-0.0')},
        'decimal128Value3': <String, Object?>{'key': Decimal128Value('1.2e3')},
        'minKey1': <String, Object?>{'key': MinKey.instance},
        'minKey2': <String, Object?>{'key': MinKey.instance},
        'maxKey1': <String, Object?>{'key': MaxKey.instance},
        'maxKey2': <String, Object?>{'key': MaxKey.instance},
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await expectConsistent(
        collection,
        collection.orderBy('key', Direction.descending),
        docs,
        <String>[
          'maxKey2',
          'maxKey1',
          'regex3',
          'regex1',
          'regex2',
          'bsonObjectId2',
          'bsonObjectId1',
          'bsonObjectId3',
          'bsonBinary3',
          'bsonBinary2',
          'bsonBinary1',
          'bsonTimestamp1',
          'bsonTimestamp2',
          'bsonTimestamp3',
          // Int32Value and Decimal128Value are sorted together.
          'decimal128Value3',
          'int32Value2',
          // An Int32Value of 0 equals a Decimal128Value of 0, they sort by
          // document key as the secondary order.
          'int32Value3',
          'decimal128Value2',
          'int32Value1',
          'decimal128Value1',
          'minKey2',
          'minKey1',
        ],
      );
    });

    test('canRunTransactionsOnDocumentsWithBsonTypes', () async {
      final _Docs docs = <String, Map<String, Object?>>{
        'a': <String, Object?>{'key': BsonObjectId('507f191e810c19729de860ea')},
        'b': <String, Object?>{'key': const RegexValue('^foo', 'i')},
        'c': <String, Object?>{
          'key': _binary(1, <int>[1, 2, 3]),
        },
      };
      final CollectionReference collection = await testCollectionWithDocs(docs);

      await firestore.runTransaction((Transaction transaction) async {
        final DocumentSnapshot snapshot = await transaction.get(
          collection.document('a'),
        );
        expect(
          snapshot.getBsonObjectId('key'),
          BsonObjectId('507f191e810c19729de860ea'),
        );
        transaction
          ..update(collection.document('b'), <String, Object?>{
            'key': const RegexValue('^bar', 'i'),
          })
          ..delete(collection.document('c'));
      });

      final QuerySnapshot snapshot = await collection.get(Source.server);
      expect(IntegrationTestUtil.querySnapshotToIds(snapshot), <String>[
        'a',
        'b',
      ]);
      expect(
        snapshot.documents[0].getBsonObjectId('key'),
        BsonObjectId('507f191e810c19729de860ea'),
      );
      expect(
        snapshot.documents[1].getRegexValue('key'),
        const RegexValue('^bar', 'i'),
      );
    });

    test(
      'numericIncrementWithBsonTypes',
      () async {
        final DocumentReference docRef = testCollection().document();

        await docRef.set(<String, Object?>{'val': Decimal128Value('10.5')});
        await docRef.update(<String, Object?>{
          'val': FieldValue.increment(5.0),
        });
        DocumentSnapshot actual = await docRef.get(Source.server);
        expect(actual.get('val'), Decimal128Value('15.5'));

        await docRef.set(<String, Object?>{'val': Int32Value(10)});
        await docRef.update(<String, Object?>{'val': FieldValue.increment(5)});
        actual = await docRef.get(Source.server);
        expect(actual.get('val'), 15);
      },
      // Verified over REST: the emulator (v1.22.0) does not treat an
      // Int32Value or a Decimal128Value as a number in an increment, it
      // replaces the field with the operand. The backend adds them.
      skip:
          skip ??
          'The Firestore emulator ignores BSON numbers in increment '
              'transforms (v1.22.0), this needs a real Enterprise database',
    );

    test('numericMinimumAndMaximumWithBsonTypes', () async {
      final DocumentReference docRef = testCollection().document();

      // Minimum: the base wins.
      await docRef.set(<String, Object?>{'val': Decimal128Value('10.5')});
      await docRef.update(<String, Object?>{'val': FieldValue.minimum(20.0)});
      DocumentSnapshot actual = await docRef.get(Source.server);
      expect(actual.get('val'), Decimal128Value('10.5'));

      // Minimum: the operand wins.
      await docRef.set(<String, Object?>{'val': Decimal128Value('10.5')});
      await docRef.update(<String, Object?>{'val': FieldValue.minimum(5.0)});
      actual = await docRef.get(Source.server);
      expect(actual.get('val'), 5.0);

      // Maximum: the base wins.
      await docRef.set(<String, Object?>{'val': Int32Value(10)});
      await docRef.update(<String, Object?>{'val': FieldValue.maximum(5)});
      actual = await docRef.get(Source.server);
      expect(actual.get('val'), Int32Value(10));

      // Maximum: the operand wins.
      await docRef.set(<String, Object?>{'val': Int32Value(10)});
      await docRef.update(<String, Object?>{'val': FieldValue.maximum(20)});
      actual = await docRef.get(Source.server);
      expect(actual.get('val'), 20);
    });
  }, skip: skip);

  group('TypeTest', () {
    test('testCanReadAndWriteMinKey', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'minKey': MinKey.instance,
      });
    });

    test('testCanReadAndWriteMaxKey', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'maxKey': MaxKey.instance,
      });
    });

    test('testCanReadAndWriteRegexValue', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'regex': const RegexValue('^foo', 'i'),
      });
    });

    test('testCanReadAndWriteInt32Value', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'int32': Int32Value(1),
      });
    });

    test('testCanReadAndWriteDecimal128Value', () async {
      final Map<String, Object?> values = <String, Object?>{
        'decimalSciPositive': Decimal128Value('1.2e3'),
        'decimalSciNegative': Decimal128Value('-1.2e3'),
        'decimalSciNegativeExponent': Decimal128Value('1.2e-3'),
        'decimalSciNegativeValueAndExponent': Decimal128Value('-1.2e-3'),
        'decimalSciExplicitPositiveExponent': Decimal128Value('1.2e+3'),
        'decimalFloatPositive': Decimal128Value('1.1'),
        'decimalIntNegative': Decimal128Value('-1'),
        'decimalZeroNegative': Decimal128Value('-0'),
        'decimalZeroInt': Decimal128Value('0'),
        'decimalZeroFloat': Decimal128Value('0.0'),
        'decimalNaN': Decimal128Value('NaN'),
        'decimalInfinityPositive': Decimal128Value('Infinity'),
        'decimalInfinityNegative': Decimal128Value('-Infinity'),
      };
      await verifySuccessfulWriteReadCycle(values);
    });

    test('testCanReadAndWriteBsonTimestampValue', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'bsonTimestamp': BsonTimestamp(1, 2),
      });
    });

    test('testCanReadAndWriteBsonObjectIdValue', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'bsonObjectId': BsonObjectId('507f191e810c19729de860ea'),
      });
    });

    test('testCanReadAndWriteBsonBinaryValue', () async {
      await verifySuccessfulWriteReadCycle(<String, Object?>{
        'bsonBinary': _binary(1, <int>[1, 2, 3]),
      });
      await verifySuccessfulWriteReadCycle(<String, Object?>{
        'bsonBinary': _binary(128, <int>[1, 2, 3]),
      });
      await verifySuccessfulWriteReadCycle(<String, Object?>{
        'bsonBinary': _binary(255),
      });
    });

    test('testCanReadAndWriteBsonTypesInLists', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'BsonTypes': allTypes().values.toList(),
      });
    });

    test('testCanReadAndWriteBsonTypesInMaps', () {
      return verifySuccessfulWriteReadCycle(<String, Object?>{
        'BsonTypes': allTypes(),
      });
    });

    test('testNativeAndBsonBinaryOrderingAndEquality', () async {
      final CollectionReference collection = testCollection();
      final _Docs docs = <String, Map<String, Object?>>{
        // BSON binary with the subtype 0 is a regular blob.
        'doc1': <String, Object?>{
          'binary': _binary(0, <int>[2]),
        },
        'doc2': <String, Object?>{
          'binary': Blob(Uint8List.fromList(<int>[1])),
        },
      };
      await IntegrationTestUtil.writeAllDocs(collection, docs);
      await expectConsistent(
        collection,
        collection.orderBy('binary'),
        docs,
        <String>['doc2', 'doc1'],
      );

      docs['doc3'] = <String, Object?>{
        'binary': _binary(0, <int>[1]),
      };
      await collection.document('doc3').set(docs['doc3']!);
      await expectConsistent(
        collection,
        collection.whereEqualTo('binary', Blob(Uint8List.fromList(<int>[1]))),
        docs,
        <String>['doc2', 'doc3'],
      );
    });

    test('invalidRegexGetsRejected', () async {
      await expectLater(
        testCollection().document().set(<String, Object?>{
          'key': const RegexValue('foo', 'a'),
        }),
        throwsInvalidArgument("Invalid regex option 'a'"),
      );
    });

    test('invalidBsonObjectIdGetsRejected', () async {
      // An ObjectId whose length is not 24 gets rejected.
      await expectLater(
        testCollection().document().set(<String, Object?>{
          'key': BsonObjectId('foobar'),
        }),
        throwsInvalidArgument('Object ID hex string has incorrect length.'),
      );
    });

    test('invalidDecimal128ValueGetsRejected', () async {
      // More significant digits than a decimal128 can hold.
      await expectLater(
        testCollection().document().set(<String, Object?>{
          'key': Decimal128Value('1.0000000000000000000000000000000001'),
        }),
        throwsInvalidArgument('Invalid decimal128 string'),
      );
    });

    // The Dart port rejects these values when they are constructed, before
    // any write.
    test('invalidBlobGetsRejected', () {
      expect(
        () => Blob.bsonBinary(1234, Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'The subtype for Blob must be a value in the inclusive [0, 255] range.',
          ),
        ),
      );
      expect(
        () => Blob.bsonBinary(-1, Uint8List.fromList(<int>[1])),
        throwsArgumentError,
      );
    });

    test('invalidBsonTimestampDataGetsRejected', () {
      Matcher rejects(String field, int value) => throwsA(
        isA<ArgumentError>()
            .having((ArgumentError e) => e.invalidValue, 'invalidValue', value)
            .having(
              (ArgumentError e) => e.message,
              'message',
              "The field '$field' does not represent an unsigned 32-bit integer",
            ),
      );
      expect(() => BsonTimestamp(-1, 1), rejects('seconds', -1));
      expect(
        () => BsonTimestamp(4294967296, 1),
        rejects('seconds', 4294967296),
      );
      expect(() => BsonTimestamp(1, -1), rejects('increment', -1));
      expect(
        () => BsonTimestamp(1, 4294967296),
        rejects('increment', 4294967296),
      );
    });

    test('invalid 32-bit integer gets rejected', () {
      expect(() => Int32Value(2147483648), throwsArgumentError);
      expect(() => Int32Value(-2147483650), throwsArgumentError);
      expect(Int32Value(2147483647).value, 2147483647);
      expect(Int32Value(-2147483648).value, -2147483648);
    });

    test('testCanUseTypedAccessors', () async {
      final DocumentReference docRef = testCollection().document();
      await docRef.set(allTypes());
      final DocumentSnapshot snapshot = await docRef.get(Source.server);
      expect(
        snapshot.getBsonObjectId('bsonObjectId'),
        BsonObjectId('507f191e810c19729de860ea'),
      );
      expect(snapshot.getRegexValue('regex'), const RegexValue('^foo', 'i'));
      expect(snapshot.getBsonTimestamp('bsonTimestamp'), BsonTimestamp(1, 2));
      expect(snapshot.getBlob('bsonBinary'), _binary(1, <int>[1, 2, 3]));
      expect(snapshot.getInt32Value('int32'), Int32Value(1));
      expect(
        snapshot.getDecimal128Value('decimal128'),
        Decimal128Value('1.2e3'),
      );
      expect(snapshot.getMinKey('minKey'), MinKey.instance);
      expect(snapshot.getMaxKey('maxKey'), MaxKey.instance);
      expect(snapshot.getInt32Value('missing'), isNull);
    });

    test('snapshotListenerSortsDifferentTypesSameAsServer', () async {
      final CollectionReference collection = testCollection();
      final _Docs docs = <String, Map<String, Object?>>{
        'null': <String, Object?>{'value': null},
        'min': <String, Object?>{'value': MinKey.instance},
        'boolean': <String, Object?>{'value': true},
        'nan': <String, Object?>{'value': double.nan},
        'int32': <String, Object?>{'value': Int32Value(1)},
        'decimal128': <String, Object?>{'value': Decimal128Value('1.2e3')},
        'double': <String, Object?>{'value': 1.0},
        'int': <String, Object?>{'value': 1},
        'timestamp': <String, Object?>{'value': Timestamp(100, 123000000)},
        'bsonTimestamp': <String, Object?>{'value': BsonTimestamp(1, 2)},
        'string': <String, Object?>{'value': 'a'},
        'bytes': <String, Object?>{
          'value': Blob(Uint8List.fromList(<int>[1, 2, 3])),
        },
        'bsonBinary': <String, Object?>{
          'value': _binary(1, <int>[1, 2, 3]),
        },
        'reference': <String, Object?>{
          'value': collection.document('testDocRef'),
        },
        'bsonObjectId': <String, Object?>{
          'value': BsonObjectId('507f191e810c19729de860ea'),
        },
        'geoPoint': <String, Object?>{'value': GeoPoint(1.23, 4.56)},
        'regex': <String, Object?>{'value': const RegexValue('^foo', 'i')},
        'array': <String, Object?>{
          'value': <Object?>[
            1.0,
            'foo',
            <String, Object?>{'key': true},
            null,
          ],
        },
        'vector': <String, Object?>{
          'value': FieldValue.vector(<double>[1, 2, 3]),
        },
        'map': <String, Object?>{
          'value': <String, Object?>{'key': true},
        },
        'max': <String, Object?>{'value': MaxKey.instance},
      };
      await IntegrationTestUtil.writeAllDocs(collection, docs);

      // NaN is never equal to itself, compare everything else.
      final List<String> expected = <String>[
        'null',
        'min',
        'boolean',
        'nan',
        'double',
        'int',
        'int32',
        'decimal128',
        'timestamp',
        'bsonTimestamp',
        'string',
        'bytes',
        'bsonBinary',
        'reference',
        'bsonObjectId',
        'geoPoint',
        'regex',
        'array',
        'vector',
        'map',
        'max',
      ];
      final Query query = collection.orderBy('value');
      await IntegrationTestUtil.checkOnlineAndOfflineResultsMatch(
        collection,
        query,
        expected,
      );
      final QuerySnapshot snapshot = await query
          .getSnapshots(MetadataChanges.include)
          .firstWhere(
            (QuerySnapshot snapshot) => !snapshot.metadata.isFromCache,
          );
      expect(IntegrationTestUtil.querySnapshotToIds(snapshot), expected);
    });
  }, skip: skip);
}
