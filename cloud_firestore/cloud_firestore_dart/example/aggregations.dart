// Aggregations run on the server without downloading the documents: count,
// sum and average, optionally with aliases of your choice.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/aggregations.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  final Firestore firestore = await connect();
  final CollectionReference<Map<String, Object?>> orders = firestore.collection(
    scratch('orders'),
  );

  final WriteBatch batch = firestore.batch();
  for (final (String customer, int total) in <(String, int)>[
    ('ada', 30),
    ('ada', 12),
    ('alan', 100),
  ]) {
    batch.set(orders.doc(), <String, Object?>{
      'customer': customer,
      'total': total,
    });
  }
  await batch.commit();

  // Count.
  final AggregateQuerySnapshot count = await orders.count().get();
  print('orders: ${count.getCount()}');

  // Several aggregations in one request; read each one back with the same
  // AggregateField.
  final AggregateField sum = AggregateField.sum('total');
  final AggregateField average = AggregateField.average('total');
  final AggregateQuerySnapshot totals = await orders
      .where('customer', isEqualTo: 'ada')
      .aggregate(<AggregateField>[AggregateField.count(), sum, average])
      .get();
  print(
    'ada: ${totals.getCount()} orders, sum ${totals.getInt(sum)}, '
    'average ${totals.getDouble(average)}',
  );

  // With aliases the result is a map keyed by the names you chose.
  final AggregateQuerySnapshot named =
      await orders.aggregateWithAliases(<String, AggregateField>{
        'revenue': AggregateField.sum('total'),
        'orders': AggregateField.count(),
        'averageOrder': AggregateField.average('total'),
      }).get();
  print('all: ${named.data()}');

  await firestore.terminate();
}
