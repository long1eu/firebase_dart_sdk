// Quick start: write a document, read it back, query and count.
//
// The other files in this directory go through one topic each; see
// example/README.md. They all target the local Firestore emulator:
//
//     firebase emulators:start --only firestore --project demo-example
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/main.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  // No `openDatabase` is passed, so the cache lives in memory. See
  // offline_persistence.dart for a cache on disk.
  final Firestore firestore = await connect();

  final CollectionReference<Map<String, Object?>> users =
      firestore.collection(scratch('users'));

  await users.doc('ada').set(<String, Object?>{'name': 'Ada', 'age': 36});
  await users.doc('alan').set(<String, Object?>{'name': 'Alan', 'age': 41});

  final DocumentSnapshot<Map<String, Object?>> ada =
      await users.doc('ada').get();
  print('ada: ${ada.data}');

  final QuerySnapshot<Map<String, Object?>> older =
      await users.where('age', isGreaterThan: 40).get();
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in older.docs) {
    print('older than 40: ${doc.id} ${doc.data}');
  }

  final AggregateQuerySnapshot count = await users.count().get();
  print('count: ${count.getCount()}');

  // Release the gRPC channel and the timers so that the process can exit.
  await firestore.terminate();
}
