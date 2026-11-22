// The life of a FirebaseDatabase: instances, goOffline, close.
//
// Shows: independent instances, close() and what fails afterwards, the app
// being deleted.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/lifecycle.dart
// Backend: Realtime Database emulator, project demo-example.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() async {
  // Each constructor call is its own connection: there is no cache of
  // instances. Two instances on one URL are two clients that see each other
  // through the server only.
  final FirebaseDatabase first = emulatorDatabase(appName: 'first');
  final FirebaseDatabase second = emulatorDatabase(appName: 'second');
  final String key = freshKey('lifecycle');
  try {
    await first.ref(key).set('from first');
    print('second reads: ${(await second.ref(key).get()).value}');

    // Settings (persistence, logging, the emulator) are constructor
    // arguments; there are no setters, so nothing can change after the
    // first use.
    print('url: ${first.databaseUrl}');

    // Listeners are open streams; close() ends them with an error
    // 'database-closed' and then done, and fails pending writes the same way.
    final Completer<Object> ended = Completer<Object>();
    first
        .ref(key)
        .onValue
        .listen((_) {}, onError: (Object error) => ended.complete(error));
    await settle();
    await first.close();
    final Object error = await ended.future;
    print('stream ended with: ${(error as FirebaseDatabaseException).code}');

    // After close() every async call fails with 'database-closed'. ref() still
    // works because it makes no request. close() is idempotent.
    try {
      await first.ref(key).get();
    } on FirebaseDatabaseException catch (error) {
      print('get after close: ${error.code}');
    }
    await first.close();
  } finally {
    await second.ref(key).remove();
    await second.close();
  }
}
