// A minimal command-line example: write a document, query it back and listen
// to a collection.
//
// It targets the local Firestore emulator, which is how this package is
// verified. Start one with
//
//     firebase emulators:start --only firestore --project demo-example
//
// and run
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/main.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final String emulator =
      Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final int colon = emulator.lastIndexOf(':');
  final String host = emulator.substring(0, colon);
  final int port = int.parse(emulator.substring(colon + 1));

  // The emulator accepts any API key and app id; a `demo-` project id keeps
  // the emulator from talking to a real project.
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:example',
      projectId: 'demo-example',
    ),
  );

  // No `openDatabase` is passed, so the cache lives in memory. Pass an
  // `OpenDatabase` function (for example backed by package:sqlite3) to keep an
  // offline cache on disk.
  final Firestore firestore = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings(cacheSettings: const MemoryCacheSettings())
        .withEmulator(host, port),
  );

  final CollectionReference<Map<String, Object?>> users =
      firestore.collection('users');

  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      users.snapshots.listen((QuerySnapshot<Map<String, Object?>> snapshot) {
    print('listener: ${snapshot.docs.length} user(s), '
        'pending writes: ${snapshot.metadata.hasPendingWrites}');
  });

  await users.doc('ada').set(<String, Object?>{'name': 'Ada', 'age': 36});
  await users.doc('alan').set(<String, Object?>{'name': 'Alan', 'age': 41});

  final QuerySnapshot<Map<String, Object?>> older =
      await users.whereGreaterThan('age', 40).get();
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in older.docs) {
    print('older than 40: ${doc.id} ${doc.data}');
  }

  await firestore.runTransaction<void>((Transaction transaction) async {
    final DocumentSnapshot<Map<String, Object?>> ada =
        await transaction.get(users.doc('ada'));
    final int age = ada.data!['age']! as int;
    transaction.update(users.doc('ada'), <String, Object?>{'age': age + 1});
  });

  final AggregateQuerySnapshot count = await users.count().get();
  print('count: ${count.getCount()}');

  await subscription.cancel();
  await firestore.terminate();
}
