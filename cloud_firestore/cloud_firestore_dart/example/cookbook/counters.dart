// Recipe: a counter. A simple counter is one field changed with
// `FieldValue.increment`. A distributed counter spreads the writes over a few
// shard documents and reads the total with a `sum` aggregation.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/counters.dart

import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> pages = firestore.collection(
    scratch('pages'),
  );

  // Simple counter: the backend adds to the stored value, so two clients
  // that increment at the same time do not overwrite each other. The field
  // is created (as 0 + 1) if it does not exist yet.
  final DocumentReference<Map<String, Object?>> home = pages.doc('home');
  await home.set(<String, Object?>{'title': 'Home'});
  await Future.wait(<Future<void>>[
    for (int i = 0; i < 5; i++)
      home.update(<String, Object?>{'views': FieldValue.increment(1)}),
  ]);
  print(
    'simple counter: ${((await home.get()).get('views') as num?)?.toInt()}',
  );

  // Distributed counter: each write goes to one of the shards at random.
  const int shardCount = 4;
  final CollectionReference<Map<String, Object?>> shards = pages
      .doc('pricing')
      .collection('shards');
  final WriteBatch create = firestore.batch();
  for (int i = 0; i < shardCount; i++) {
    create.set(shards.doc('$i'), <String, Object?>{'count': 0});
  }
  await create.commit();

  final Random random = Random();
  Future<void> incrementShard() => shards
      .doc('${random.nextInt(shardCount)}')
      .update(<String, Object?>{'count': FieldValue.increment(1)});
  await Future.wait(<Future<void>>[
    for (int i = 0; i < 10; i++) incrementShard(),
  ]);

  // The total, added up by the backend.
  final AggregateField total = AggregateField.sum('count');
  final AggregateQuerySnapshot sum = await shards.aggregate(<AggregateField>[
    total,
  ]).get();
  print('distributed counter: ${(sum.get(total) as num?)?.toInt()}');

  await firestore.terminate();
}
