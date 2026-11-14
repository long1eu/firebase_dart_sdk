// Writes sample orders for the job to summarize. Emulator only: it refuses to
// run without FIRESTORE_EMULATOR_HOST, so that it never writes sample data
// into a real project.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_run_job/firestore_from_env.dart';

Future<void> main() async {
  if ((Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '').isEmpty) {
    stderr.writeln(
      'seed.dart writes sample data: set FIRESTORE_EMULATOR_HOST.',
    );
    exitCode = 78;
    return;
  }
  final String ordersPath =
      Platform.environment['ORDERS_COLLECTION'] ?? 'orders';
  final Firestore firestore = firestoreFromEnvironment();
  final WriteBatch batch = firestore.batch();
  for (int i = 0; i < 10; i++) {
    batch.set(
      firestore.collection(ordersPath).doc('order-$i'),
      <String, Object?>{
        // 7 paid orders of 10, 20, ..., 70; 3 cancelled ones.
        'status': i < 7 ? 'paid' : 'cancelled',
        'amount': (i + 1) * 10.0,
      },
    );
  }
  await batch.commit();
  print('wrote 10 orders to $ordersPath (7 paid, revenue 280.00)');
  await firestore.terminate();
}
