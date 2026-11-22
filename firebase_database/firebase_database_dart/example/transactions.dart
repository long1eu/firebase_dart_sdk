// Transactions: change a value based on its current value, safely.
//
// Shows: runTransaction, Transaction.success, Transaction.abort, the retry
// behaviour, TransactionResult.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/transactions.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('transactions', (db, root) async {
  final DatabaseReference seats = root.child('seats');

  // The handler gets the current value. On the very first run it is often
  // null, because the client holds no data yet: handle null, do not assume it
  // is the real value. If the server's value differs, the handler runs again
  // with it, so it must be free of side effects and synchronous.
  int runs = 0;
  TransactionResult result = await seats.runTransaction((Object? current) {
    runs++;
    return Transaction.success(((current as num?) ?? 5) - 1);
  });
  print(
    'committed: ${result.committed}, value: ${result.snapshot.value}, runs: $runs',
  );

  // Abort to leave the value alone: the result says committed false and holds
  // the value the handler saw.
  await seats.set(0);
  result = await seats.runTransaction((Object? current) {
    return current == 0 ? const Transaction.abort() : Transaction.success(0);
  });
  print(
    'aborted: committed ${result.committed}, value ${result.snapshot.value}',
  );

  // Many concurrent updates never lose one; with set() they would.
  final DatabaseReference counter = root.child('counter');
  await Future.wait(<Future<TransactionResult>>[
    for (int i = 0; i < 10; i++)
      counter.runTransaction(
        (Object? v) => Transaction.success(((v as num?) ?? 0) + 1),
      ),
  ]);
  print('counter after 10 transactions: ${(await counter.get()).value}');

  // A transaction can write several fields: return the whole new value.
  final DatabaseReference account = root.child('account');
  await account.set(<String, Object?>{'balance': 100, 'log': 0});
  await account.runTransaction((Object? v) {
    // The first run sees what the client has cached, and with no listener
    // here that is null even though the value was just written. Return null
    // unchanged: the server sees that its value differs, sends it, and the
    // handler runs again with the real data. Never assume a non-null value.
    if (v == null) {
      return Transaction.success(null);
    }
    final Map<String, Object?> data = Map<String, Object?>.of(
      v as Map<String, Object?>,
    );
    data['balance'] = (data['balance']! as num) - 30;
    data['log'] = (data['log']! as num) + 1;
    return Transaction.success(data);
  });
  print('account: ${(await account.get()).value}');

  // An exception in the handler aborts the transaction and fails the Future
  // with that same object.
  try {
    await seats.runTransaction((Object? v) => throw StateError('refused'));
  } on StateError catch (error) {
    print('handler threw: ${error.message}');
  }

  // Transactions live in memory only. If the connection drops after the value
  // was sent, the Future fails with 'disconnected'; a later set() at the
  // location fails it with 'overridden-by-set'.
});
