// Recipe: an OR query across different fields, with `Filter.or`, and OR mixed
// with AND.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/or_queries.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> tasks = firestore.collection(
    scratch('tasks'),
  );

  final WriteBatch batch = firestore.batch();
  <String, Map<String, Object?>>{
    'a': {'owner': 'ada', 'priority': 1, 'done': false},
    'b': {'owner': 'alan', 'priority': 3, 'done': false},
    'c': {'owner': 'grace', 'priority': 3, 'done': true},
    'd': {'owner': 'grace', 'priority': 1, 'done': false},
  }.forEach((String id, Map<String, Object?> data) {
    batch.set(tasks.doc(id), data);
  });
  await batch.commit();

  // Mine, or urgent: two different fields, so whereIn cannot express it.
  final QuerySnapshot<Map<String, Object?>> mineOrUrgent = await tasks
      .where(
        Filter.or(<Filter>[
          Filter.equalTo('owner', 'ada'),
          Filter.greaterThanOrEqualTo('priority', 3),
        ]),
      )
      .get();
  print('mine or urgent: ${<String>[for (final d in mineOrUrgent) d.id]}');

  // (mine or urgent) and not done. A where() after another where() is an
  // AND, the same as wrapping both in Filter.and.
  final QuerySnapshot<Map<String, Object?>> open = await tasks
      .where(
        Filter.and(<Filter>[
          Filter.or(<Filter>[
            Filter.equalTo('owner', 'ada'),
            Filter.greaterThanOrEqualTo('priority', 3),
          ]),
          Filter.equalTo('done', false),
        ]),
      )
      .get();
  print('open, mine or urgent: ${<String>[for (final d in open) d.id]}');

  await firestore.terminate();
}
