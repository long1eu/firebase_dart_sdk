// Quick start: add documents, read and query them, listen to changes, write
// with a batch and a transaction, count.
//
// The other files in this directory go through one topic each; see
// example/README.md. offline_persistence.dart keeps the cache in SQLite, and
// server.dart shows the setup for a backend process. They all target the
// local Firestore emulator:
//
//     firebase emulators:start --only firestore --project demo-example
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/main.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import 'common.dart';

Future<void> main() async {
  // No `openDatabase` is passed, so the cache lives in memory. See
  // offline_persistence.dart for a cache on disk.
  final Firestore firestore = connect();

  final CollectionReference<Map<String, Object?>> users = firestore.collection(
    scratch('users'),
  );

  // Write: `set` on a document you name, `add` for a generated id.
  await users.doc('ada').set(<String, Object?>{'name': 'Ada', 'age': 36});
  final DocumentReference<Map<String, Object?>> alan = await users.add(
    <String, Object?>{'name': 'Alan', 'age': 41},
  );
  print('added alan with a generated id of ${alan.id.length} characters');

  // Read one document and query the collection.
  final DocumentSnapshot<Map<String, Object?>> ada = await users
      .doc('ada')
      .get();
  print('ada: ${ada.data}');

  final QuerySnapshot<Map<String, Object?>> older = await users
      .where('age', isGreaterThan: 40)
      .get();
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in older.docs) {
    print('older than 40: ${doc.data['name']}');
  }

  // Listen: the first event is the current result, every later one a change.
  // Local writes are reported at once, before the backend confirms them.
  // An app would call `snapshots.listen(...)`; the iterator lets this program
  // wait for each event in turn. Cancelling it stops the listener.
  final StreamIterator<QuerySnapshot<Map<String, Object?>>> listener =
      StreamIterator<QuerySnapshot<Map<String, Object?>>>(
        users.orderBy('name').snapshots,
      );
  await listener.moveNext();
  print('listener: ${_names(listener.current)}');

  // A batch writes several documents atomically.
  final WriteBatch batch = firestore.batch()
    ..set(users.doc('grace'), <String, Object?>{'name': 'Grace', 'age': 45})
    ..update(users.doc('ada'), <String, Object?>{'age': 37});
  await batch.commit();
  await listener.moveNext();
  print('listener after the batch: ${_names(listener.current)}');

  // A transaction reads, then writes based on what it read. It is retried if
  // the documents it read change before it commits.
  final int newAge = await firestore.runTransaction<int>((
    Transaction transaction,
  ) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
        .get(alan);
    final int age = snapshot.data!['age']! as int;
    transaction.update(alan, <String, Object?>{'age': age + 1});
    return age + 1;
  });
  print('alan is now $newAge');

  await listener.cancel();

  final AggregateQuerySnapshot count = await users.count().get();
  print('count: ${count.getCount()}');

  // Release the gRPC channel and the timers so that the process can exit.
  await firestore.terminate();
}

List<Object?> _names(QuerySnapshot<Map<String, Object?>> snapshot) => <Object?>[
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot.docs)
    doc.data['name'],
];
