// Recipe: read several documents, a query and an aggregation as they all were
// at one moment, with a read-only transaction. It takes no locks and never
// conflicts with writers.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/read_only_transaction.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final Firestore firestore = connect();
  final CollectionReference<Map<String, Object?>> accounts = firestore
      .collection(scratch('accounts'));
  final CollectionReference<Map<String, Object?>> orders = firestore.collection(
    scratch('orders'),
  );
  await accounts.doc('ada').set(<String, Object?>{'credit': 100});
  await orders.add(<String, Object?>{'account': 'ada', 'total': 30});
  await orders.add(<String, Object?>{'account': 'ada', 'total': 25});

  final String report = await firestore.runTransaction<String>((
    Transaction transaction,
  ) async {
    final DocumentSnapshot<Object?> account = await transaction.get(
      accounts.doc('ada'),
    );
    // getQuery and getAggregate are only allowed in read-only transactions.
    final QuerySnapshot<Object?> list = await transaction.getQuery(
      orders.where('account', isEqualTo: 'ada'),
    );
    final AggregateField spent = AggregateField.sum('total');
    final AggregateQuerySnapshot sum = await transaction.getAggregate(
      orders.where('account', isEqualTo: 'ada').aggregate(<AggregateField>[
        spent,
      ]),
    );
    return 'credit ${account.getInt('credit')}, '
        '${list.length} orders, spent ${sum.getInt(spent)}';
  }, options: TransactionOptions(readOnly: true));
  print(report);

  // Writes in a read-only transaction throw.
  try {
    await firestore.runTransaction<void>((Transaction transaction) async {
      transaction.update(accounts.doc('ada'), <String, Object?>{'credit': 0});
    }, options: TransactionOptions(readOnly: true));
  } on FirestoreError catch (e) {
    print('write refused: ${e.code}');
  }

  await firestore.terminate();
}
