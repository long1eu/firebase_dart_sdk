// A Flutter program that uses the official firebase_database API, with
// firebase_database_dart doing the work underneath.
//
// On Linux the FirebaseDatabaseDart.use() call is optional: Flutter registers
// the package before main() runs. On the other platforms it replaces the
// official implementation. Run it against an emulator started with
// `tool/start_database_emulator.sh 9000` from the repository root (open
// rules for this namespace).

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseDatabaseDart.use();
  await Firebase.initializeApp(
    // Use your own options (flutterfire configure) for a real project.
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:1:web:1',
      messagingSenderId: '1',
      projectId: 'demo-test',
      databaseURL: 'https://demo-test-default-rtdb.firebaseio.com',
    ),
  );
  final FirebaseDatabase database = FirebaseDatabase.instance;
  database.useDatabaseEmulator('127.0.0.1', 9000);

  final DatabaseReference notes = database.ref('notes');
  final StreamSubscription<DatabaseEvent> added = notes.onChildAdded.listen((
    DatabaseEvent event,
  ) {
    debugPrint('added ${event.snapshot.key}: ${event.snapshot.value}');
  });
  await notes.push().set(<String, Object?>{
    'text': 'Hello from Dart',
    'createdAt': ServerValue.timestamp,
  });

  final DatabaseReference likes = database.ref('counters/likes');
  final TransactionResult result = await likes.runTransaction(
    (Object? value) => Transaction.success(((value as int?) ?? 0) + 1),
  );
  debugPrint('likes: ${result.snapshot.value} (${result.committed})');

  final DatabaseReference status = database.ref('status/example');
  await status.onDisconnect().set('offline');
  await status.set('online');

  final DataSnapshot all = await notes.get();
  debugPrint('${all.children.length} notes');
  await added.cancel();
}
