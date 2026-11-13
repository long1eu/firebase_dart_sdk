// Transactions (read-write and read-only) and write batches.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/transactions_and_batches.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  final Firestore firestore = connect();
  final CollectionReference<Map<String, Object?>> accounts = firestore
      .collection(scratch('accounts'));
  final DocumentReference<Map<String, Object?>> ada = accounts.doc('ada');
  final DocumentReference<Map<String, Object?>> alan = accounts.doc('alan');

  // A batch applies all its writes atomically, without reading.
  final WriteBatch batch = firestore.batch()
    ..set(ada, <String, Object?>{'balance': 100})
    ..set(alan, <String, Object?>{'balance': 20});
  await batch.commit();

  // runBatch creates and commits the batch for you.
  await firestore.runBatch((WriteBatch batch) async {
    batch
      ..update(ada, <String, Object?>{'currency': 'EUR'})
      ..update(alan, <String, Object?>{'currency': 'EUR'});
  });

  // A read-write transaction: all reads come first, then the writes. The
  // function is run again if a document it read changed in the meantime, so
  // it must not have side effects of its own. Its result is returned.
  final int newBalance = await firestore.runTransaction<int>((
    Transaction transaction,
  ) async {
    final DocumentSnapshot<Map<String, Object?>> from = await transaction.get(
      ada,
    );
    final DocumentSnapshot<Map<String, Object?>> to = await transaction.get(
      alan,
    );
    final int fromBalance = from.data!['balance']! as int;
    final int toBalance = to.data!['balance']! as int;
    const int amount = 30;
    if (fromBalance < amount) {
      // Throwing aborts the transaction; nothing is written.
      throw StateError('Insufficient funds');
    }
    transaction
      ..update(ada, <String, Object?>{'balance': fromBalance - amount})
      ..update(alan, <String, Object?>{'balance': toBalance + amount});
    return fromBalance - amount;
  });
  print('ada after transfer: $newBalance');

  // The number of attempts can be limited.
  try {
    await firestore.runTransaction<void>((Transaction transaction) async {
      await transaction.get(ada);
      throw StateError('Changed my mind');
    }, options: TransactionOptions(maxAttempts: 1));
  } on StateError catch (e) {
    print('aborted: ${e.message}');
  }

  // A read-only transaction reads a consistent view of several documents and
  // cannot write.
  final int total = await firestore.runTransaction<int>((
    Transaction transaction,
  ) async {
    final int a = (await transaction.get(ada)).data!['balance']! as int;
    final int b = (await transaction.get(alan)).data!['balance']! as int;
    return a + b;
  }, options: TransactionOptions(readOnly: true));
  print('total: $total');

  await firestore.terminate();
}
