// Server-side read-only transactions: `TransactionOptions(readOnly: true)`.
// Every read of the transaction (documents, queries, aggregations) sees one
// snapshot of the backend.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

TypeMatcher<FirestoreError> firestoreError(FirestoreErrorCode code) =>
    isA<FirestoreError>().having((FirestoreError e) => e.code, 'code', code);

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/read_only_transaction';
  late Firestore firestore;
  late CollectionReference<Map<String, Object?>> collection;
  final TransactionOptions readOnly = TransactionOptions(readOnly: true);

  setUp(() async {
    firestore = await IntegrationTestUtil.testFirestore();
    collection = firestore
        .collection('rotx-${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test('later reads do not see a write made during the transaction',
      () async {
    final DocumentReference<Map<String, Object?>> a = collection.doc('a');
    final DocumentReference<Map<String, Object?>> b = collection.doc('b');
    await a.set(<String, Object?>{'n': 1});
    await b.set(<String, Object?>{'n': 10});

    await firestore.runTransaction<void>((Transaction transaction) async {
      expect((await transaction.get(a)).data, <String, Object?>{'n': 1});

      // Another writer changes, deletes and creates documents meanwhile.
      await a.set(<String, Object?>{'n': 2});
      await b.delete();
      await collection.doc('c').set(<String, Object?>{'n': 100});

      // Documents, also one that was not read before the writes.
      expect((await transaction.get(a)).data, <String, Object?>{'n': 1});
      final DocumentSnapshot<Map<String, Object?>> oldB =
          await transaction.get(b);
      expect(oldB.exists, isTrue);
      expect(oldB.data, <String, Object?>{'n': 10});
      expect((await transaction.get(collection.doc('c'))).exists, isFalse);

      // A query and an aggregation see the same snapshot.
      final QuerySnapshot<Map<String, Object?>> all =
          await transaction.getQuery(collection.orderBy('n'));
      expect(all.docs.map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id),
          <String>['a', 'b']);
      expect(all.docs.first.data, <String, Object?>{'n': 1});
      expect(all.metadata.isFromCache, isFalse);
      expect(all.metadata.hasPendingWrites, isFalse);

      final AggregateQuerySnapshot aggregate = await transaction.getAggregate(
          collection.aggregate(<AggregateField>[
        AggregateField.count(),
        AggregateField.sum('n'),
      ]));
      expect(aggregate.getCount(), 2);
      expect(aggregate.get(AggregateField.sum('n')), 11);
    }, options: readOnly);

    // Outside of the transaction the writes are there.
    final QuerySnapshot<Map<String, Object?>> now =
        await collection.orderBy('n').get(Source.server);
    expect(now.docs.map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.data['n']),
        <Object?>[2, 100]);
  });

  test('queries keep their filters, order and limits', () async {
    for (int i = 0; i < 5; i++) {
      await collection.doc('d$i').set(<String, Object?>{'n': i, 'even': i.isEven});
    }
    await firestore.runTransaction<void>((Transaction transaction) async {
      List<Object?> ns(QuerySnapshot<Map<String, Object?>> snapshot) => snapshot
          .docs
          .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.data['n'])
          .toList();

      expect(
          ns(await transaction.getQuery(
              collection.where('even', isEqualTo: true).orderBy('n'))),
          <Object?>[0, 2, 4]);
      expect(
          ns(await transaction.getQuery(
              collection.orderBy('n', Direction.descending).limit(2))),
          <Object?>[4, 3]);
      expect(ns(await transaction.getQuery(collection.orderBy('n').limitToLast(2))),
          <Object?>[3, 4]);
    }, options: readOnly);
  });

  test('a typed query returns converted documents', () async {
    await collection.doc('a').set(<String, Object?>{'n': 7});
    final Query<int> numbers = collection.withConverter<int>(
        FirestoreDataConverter<int>.from(
      fromFirestore: (DocumentSnapshot<Map<String, Object?>> s, _) =>
          s.data!['n']! as int,
      toFirestore: (int value, _) => <String, Object?>{'n': value},
    ));
    final QuerySnapshot<int> snapshot = await firestore.runTransaction(
        (Transaction transaction) => transaction.getQuery(numbers),
        options: readOnly);
    expect(snapshot.docs.single.data, 7);
  });

  test('readTime reads the database as it was', () async {
    final DocumentReference<Map<String, Object?>> doc = collection.doc('a');
    await doc.set(<String, Object?>{'n': 1});
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final Timestamp between = Timestamp.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await doc.set(<String, Object?>{'n': 2});
    await collection.doc('later').set(<String, Object?>{'n': 3});

    await firestore.runTransaction<void>((Transaction transaction) async {
      expect((await transaction.get(doc)).data, <String, Object?>{'n': 1});
      expect((await transaction.getQuery(collection)).docs, hasLength(1));
      expect((await transaction.getAggregate(collection.count())).getCount(), 1);
    }, options: TransactionOptions(readOnly: true, readTime: between));
  });

  test('writes are rejected, and queries need a read-only transaction',
      () async {
    final DocumentReference<Map<String, Object?>> doc = collection.doc('a');
    await expectLater(
        firestore.runTransaction<void>((Transaction transaction) async {
          transaction.set(doc, <String, Object?>{'n': 1});
        }, options: readOnly),
        throwsA(firestoreError(FirestoreErrorCode.invalidArgument)));

    await expectLater(
        firestore.runTransaction<void>(
            (Transaction transaction) => transaction.getQuery(collection)),
        throwsA(firestoreError(FirestoreErrorCode.invalidArgument)));
    await expectLater(
        firestore.runTransaction<void>((Transaction transaction) =>
            transaction.getAggregate(collection.count())),
        throwsA(firestoreError(FirestoreErrorCode.invalidArgument)));
  });

  test('a transaction without reads, and one whose callback fails', () async {
    expect(
        await firestore.runTransaction<int>((Transaction transaction) async => 7,
            options: readOnly),
        7);

    int attempts = 0;
    await expectLater(
        firestore.runTransaction<void>((Transaction transaction) async {
          attempts++;
          await transaction.get(collection.doc('a'));
          throw StateError('callback failed');
        }, options: readOnly),
        throwsStateError);
    expect(attempts, 1);
  });
}
