// Recipe: move a value from one document to another in a transaction, so that
// the total never changes even when other clients write at the same time.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/move_between_documents.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

/// Moves [amount] units of stock from [from] to [to]. Returns the stock that
/// is left in [from].
Future<int> moveStock(
  FirebaseFirestore firestore,
  DocumentReference<Map<String, Object?>> from,
  DocumentReference<Map<String, Object?>> to,
  int amount,
) {
  return firestore.runTransaction<int>((Transaction transaction) async {
    // All reads first, then the writes.
    final DocumentSnapshot<Object?> source = await transaction.get(from);
    final DocumentSnapshot<Object?> target = await transaction.get(to);
    final int available = (source.get('stock') as num?)?.toInt() ?? 0;
    if (available < amount) {
      // Throwing ends the transaction without writing anything.
      throw StateError('only $available left in ${from.id}');
    }
    transaction
      ..update(from, <String, Object?>{'stock': available - amount})
      ..set(to, <String, Object?>{
        'stock': ((target.get('stock') as num?)?.toInt() ?? 0) + amount,
      }, const SetOptions(merge: true));
    return available - amount;
  });
}

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> warehouses = firestore
      .collection(scratch('warehouses'));
  final DocumentReference<Map<String, Object?>> north = warehouses.doc('north');
  final DocumentReference<Map<String, Object?>> south = warehouses.doc('south');
  await north.set(<String, Object?>{'stock': 10});
  await south.set(<String, Object?>{'stock': 0});

  // Two moves at once: the transaction that loses the race runs again with
  // the new values.
  await Future.wait(<Future<int>>[
    moveStock(firestore, north, south, 3),
    moveStock(firestore, north, south, 4),
  ]);
  try {
    await moveStock(firestore, north, south, 5);
  } on StateError catch (e) {
    print('refused: ${e.message}');
  }

  final int n = ((await north.get()).get('stock') as num).toInt();
  final int s = ((await south.get()).get('stock') as num).toInt();
  print('north $n, south $s, total ${n + s}');

  await firestore.terminate();
}
