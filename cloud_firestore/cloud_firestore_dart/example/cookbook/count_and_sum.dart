// Recipe: count documents and add up a field without downloading them. The
// backend computes the result and sends back only the numbers.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/count_and_sum.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> orders = firestore.collection(
    scratch('orders'),
  );

  final WriteBatch batch = firestore.batch();
  for (final (String status, int total) in <(String, int)>[
    ('paid', 30),
    ('paid', 45),
    ('open', 12),
    ('paid', 25),
  ]) {
    batch.set(orders.doc(), <String, Object?>{
      'status': status,
      'total': total,
    });
  }
  await batch.commit();

  // Only a count.
  final AggregateQuerySnapshot all = await orders.count().get();
  print('orders: ${all.getCount()}');

  // A count, a sum and an average of the same query in one request.
  final AggregateField revenue = AggregateField.sum('total');
  final AggregateField average = AggregateField.average('total');
  final AggregateQuerySnapshot paid = await orders
      .where('status', isEqualTo: 'paid')
      .aggregate(<AggregateField>[AggregateField.count(), revenue, average])
      .get();
  print(
    'paid: ${paid.getCount()} orders, revenue ${paid.getInt(revenue)}, '
    'average ${paid.getDouble(average)}',
  );

  await firestore.terminate();
}
