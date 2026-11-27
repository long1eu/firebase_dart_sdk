// Cookbook: a counter that many clients change at once, three ways.
//
// Shows: ServerValue.increment, runTransaction, and why read-then-set loses
// updates.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/cookbook/counter.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import '../common.dart';

Future<void> main() => runExample('counter', (db, root) async {
  const int clicks = 20;

  // Wrong: read, add, write. Concurrent calls read the same old value and
  // overwrite each other, so the result is usually below 20.
  final DatabaseReference naive = root.child('naive');
  await naive.set(0);
  await Future.wait(<Future<void>>[
    for (int i = 0; i < clicks; i++)
      () async {
        final int current = ((await naive.get()).value as num?)!.toInt();
        await naive.set(current + 1);
      }(),
  ]);
  print('read-then-set: ${(await naive.get()).value} (expected $clicks)');

  // Right, simplest: let the server add. One round trip, no retries. Use it
  // for likes, views and counts where a rare double count after a lost
  // acknowledgement is acceptable.
  final DatabaseReference inc = root.child('increment');
  await Future.wait(<Future<void>>[
    for (int i = 0; i < clicks; i++) inc.set(ServerValue.increment(1)),
  ]);
  print('increment: ${(await inc.get()).value}');

  // Right, exact: a transaction runs again when the value changed under it.
  // Use it when the new value depends on the old one (a limit, a balance).
  final DatabaseReference tx = root.child('transaction');
  await Future.wait(<Future<TransactionResult>>[
    for (int i = 0; i < clicks; i++)
      tx.runTransaction((Object? v) {
        final int n = (v as num?)?.toInt() ?? 0;
        return n >= 15 ? const Transaction.abort() : Transaction.success(n + 1);
      }),
  ]);
  print('transaction with a limit of 15: ${(await tx.get()).value}');
});
