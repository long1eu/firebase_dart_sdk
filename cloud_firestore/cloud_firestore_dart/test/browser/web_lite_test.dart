// Firestore Lite in a real browser: the REST transport over `fetch`, through
// the public API of `package:cloud_firestore_dart/lite.dart`, against a
// private Firestore emulator on 127.0.0.1:8090 (tool/start_private_emulator.sh):
//
//   tool/test_browser.sh both test/browser/web_lite_test.dart
//
// This file only imports the lite library, as an application would.

@TestOn('browser')
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/lite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

const String emulatorHost = String.fromEnvironment(
  'FIRESTORE_EMULATOR_HOST_NAME',
  defaultValue: '127.0.0.1',
);
const int emulatorPort = int.fromEnvironment(
  'FIRESTORE_EMULATOR_PORT',
  defaultValue: 8090,
);
const String projectId = String.fromEnvironment(
  'FIRESTORE_PROJECT_ID',
  defaultValue: 'demo-test',
);

final Random _random = Random();
int _apps = 0;

/// A new instance with an app of its own. It is terminated when the test
/// ends, and its app is deleted.
Firestore newFirestore({Object? mockUserToken}) {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:browser',
      projectId: projectId,
    ),
    name: 'browser-lite-${_apps++}-${_random.nextInt(0x7fffffff)}',
  );
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator(
      emulatorHost,
      emulatorPort,
      mockUserToken: mockUserToken,
    ),
  );
  addTearDown(() async {
    await firestore.terminate();
    app.delete();
  });
  return firestore;
}

CollectionReference<Map<String, Object?>> newCollection([
  Firestore? firestore,
]) => (firestore ?? newFirestore()).collection(
  'browser-lite-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}',
);

List<Object?> values(QuerySnapshot<Map<String, Object?>> snapshot) => <Object?>[
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot.docs)
    doc.data['n'],
];

void main() {
  test('writes a document and reads it back', () async {
    final DocumentReference<Map<String, Object?>> doc = newCollection().doc(
      'a',
    );
    expect((await doc.get()).exists, isFalse);

    final Map<String, Object?> data = <String, Object?>{
      'text': 'héllo \u{1F600} 日本',
      'int': 42,
      'double': 1.5,
      'bool': true,
      'null': null,
      'timestamp': const Timestamp(1700000000, 123456000),
      'geo': const GeoPoint(1.5, -2.5),
      'bytes': Blob(Uint8List.fromList(<int>[0, 1, 2, 255])),
      'vector': FieldValue.vector(<double>[1, 2.5]),
      'ref': doc,
      'list': <Object?>[1, 'two', null],
      'map': <String, Object?>{
        'nested': <String, Object?>{'deep': 'yes'},
      },
    };
    await doc.set(data);

    final DocumentSnapshot<Map<String, Object?>> snapshot = await doc.get();
    expect(snapshot.exists, isTrue);
    expect(snapshot.id, 'a');
    expect(snapshot.data, data);
    expect(snapshot.get('map.nested.deep'), 'yes');
    expect(snapshot.get('ref'), isA<DocumentReference<Map<String, Object?>>>());
  });

  test('updates with transforms, merges and deletes', () async {
    final DocumentReference<Map<String, Object?>> doc = newCollection().doc(
      'a',
    );
    await doc.set(<String, Object?>{
      'count': 1,
      'tags': <Object?>['a'],
      'gone': true,
    });
    await doc.update(<String, Object?>{
      'count': FieldValue.increment(2),
      'tags': FieldValue.arrayUnion(<Object>['b']),
      'gone': FieldValue.delete(),
      'when': FieldValue.serverTimestamp(),
    });
    await doc.set(<String, Object?>{'merged': true}, SetOptions.mergeAllFields);

    final Map<String, Object?> data = (await doc.get()).data!;
    expect(data['count'], 3);
    expect(data['tags'], <Object?>['a', 'b']);
    expect(data.containsKey('gone'), isFalse);
    expect(data['when'], isA<Timestamp>());
    expect(data['merged'], isTrue);

    await doc.delete();
    expect((await doc.get()).exists, isFalse);
  });

  test('a backend error has its code', () async {
    await expectLater(
      newCollection().doc('missing').update(<String, Object?>{'a': 1}),
      throwsA(
        isA<FirestoreError>().having(
          (FirestoreError e) => e.code,
          'code',
          FirestoreErrorCode.notFound,
        ),
      ),
    );
  });

  test('queries with filters, orders, limits and cursors', () async {
    final CollectionReference<Map<String, Object?>> collection =
        newCollection();
    final WriteBatch batch = collection.firestore.batch();
    for (int n = 1; n <= 5; n++) {
      batch.set(collection.doc('doc$n'), <String, Object?>{
        'n': n,
        'even': n.isEven,
      });
    }
    await batch.commit();

    expect(values(await collection.orderBy('n').get()), <int>[1, 2, 3, 4, 5]);
    expect(
      values(await collection.where('even', isEqualTo: true).get()),
      unorderedEquals(<int>[2, 4]),
    );
    expect(
      values(
        await collection
            .where(
              Filter.or(<Filter>[
                Filter.equalTo('n', 1),
                Filter.greaterThan('n', 4),
              ]),
            )
            .orderBy('n')
            .get(),
      ),
      <int>[1, 5],
    );
    expect(
      values(
        await collection
            .where('n', whereIn: <Object?>[1, 3, 9])
            .orderBy('n', Direction.descending)
            .get(),
      ),
      <int>[3, 1],
    );
    expect(values(await collection.orderBy('n').limit(2).get()), <int>[1, 2]);
    expect(values(await collection.orderBy('n').limitToLast(2).get()), <int>[
      4,
      5,
    ]);
    expect(
      values(
        await collection.orderBy('n').startAfter(<Object?>[1]).endAt(<Object?>[
          3,
        ]).get(),
      ),
      <int>[2, 3],
    );

    final QuerySnapshot<Map<String, Object?>> firstPage = await collection
        .orderBy('n')
        .limit(2)
        .get();
    expect(
      values(
        await collection
            .orderBy('n')
            .startAfterDocument(firstPage.docs.last)
            .limit(2)
            .get(),
      ),
      <int>[3, 4],
    );
  });

  test('collection group queries and aggregations', () async {
    final CollectionReference<Map<String, Object?>> collection =
        newCollection();
    final String group = '${collection.id}-group';
    await collection.doc('a').collection(group).doc('x').set(<String, Object?>{
      'n': 1,
    });
    await collection.doc('b').collection(group).doc('y').set(<String, Object?>{
      'n': 4,
    });

    final Query<Map<String, Object?>> query = collection.firestore
        .collectionGroup(group);
    expect(values(await query.orderBy('n').get()), <int>[1, 4]);
    expect((await query.count().get()).getCount(), 2);
    expect(
      (await query.aggregateWithAliases(<String, AggregateField>{
        'total': AggregateField.sum('n'),
        'mean': AggregateField.average('n'),
        'docs': AggregateField.count(),
      }).get()).data(),
      <String, Object?>{'total': 5, 'mean': 2.5, 'docs': 2},
    );
  });

  test('transactions read, write and retry', () async {
    final DocumentReference<Map<String, Object?>> doc = newCollection().doc(
      'counter',
    );
    await doc.set(<String, Object?>{'count': 1});

    int attempts = 0;
    final int result = await doc.firestore.runTransaction<int>((
      Transaction transaction,
    ) async {
      attempts++;
      final int count = (await transaction.get(doc)).get('count')! as int;
      if (attempts == 1) {
        // A write outside the transaction: the first attempt must fail.
        await doc.update(<String, Object?>{'count': 10});
      }
      transaction.update(doc, <String, Object?>{'count': count + 1});
      return count + 1;
    });
    expect(attempts, 2);
    expect(result, 11);
    expect((await doc.get()).get('count'), 11);
  });

  test('a read-only transaction reads at one point in time', () async {
    final CollectionReference<Map<String, Object?>> collection =
        newCollection();
    await collection.doc('a').set(<String, Object?>{'n': 1});
    await collection.firestore.runTransaction<void>((
      Transaction transaction,
    ) async {
      expect(values(await transaction.getQuery(collection)), <int>[1]);
      await collection.doc('b').set(<String, Object?>{'n': 2});
      expect(values(await transaction.getQuery(collection)), <int>[1]);
      expect(
        (await transaction.getAggregate(collection.count())).getCount(),
        1,
      );
      expect((await transaction.get(collection.doc('b'))).exists, isFalse);
    }, options: TransactionOptions(readOnly: true));
    expect((await collection.count().get()).getCount(), 2);
  });

  test('converters', () async {
    final CollectionReference<String> names = newCollection().withConverter(
      FirestoreDataConverter<String>.from(
        fromFirestore: (QueryDocumentSnapshot<Map<String, Object?>> snapshot) =>
            snapshot.data['name']! as String,
        toFirestore: (String name, SetOptions? options) => <String, Object?>{
          'name': name,
        },
      ),
    );
    final DocumentReference<String> ada = await names.add('Ada');
    expect((await ada.get()).data, 'Ada');
    expect((await names.get()).docs.single.data, 'Ada');
  });

  test('requests with a mock user token succeed', () async {
    final Firestore firestore = newFirestore(
      mockUserToken: <String, Object?>{'sub': 'alice'},
    );
    final DocumentReference<Map<String, Object?>> doc = newCollection(
      firestore,
    ).doc('a');
    await doc.set(<String, Object?>{'a': 1});
    expect((await doc.get()).data, <String, Object?>{'a': 1});
  });

  test('a terminated instance rejects calls; calls in flight finish', () async {
    final Firestore firestore = newFirestore();
    final CollectionReference<Map<String, Object?>> collection = newCollection(
      firestore,
    );
    await collection.doc('a').set(<String, Object?>{'n': 1});

    final Future<AggregateQuerySnapshot> inFlight = collection.count().get();
    await firestore.terminate();
    expect((await inFlight).getCount(), 1);
    await expectLater(
      collection.doc('a').get(),
      throwsA(
        isA<FirestoreError>().having(
          (FirestoreError e) => e.code,
          'code',
          FirestoreErrorCode.failedPrecondition,
        ),
      ),
    );
  });
}
