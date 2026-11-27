// Errors: FirebaseDatabaseException and programmer errors.
//
// Shows: code, message, serverStatus, ArgumentError, StateError, and the
// codes a program can meet.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/error_handling.dart
// Backend: Realtime Database emulator, project demo-example.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() async {
  final FirebaseDatabase db = emulatorDatabase();
  final DatabaseReference root = db.ref(freshKey('errors'));
  try {
    // 1. Programmer errors are not exceptions of this package: a bad path,
    // value or query throws an ArgumentError or StateError at the call, before
    // any request. Fix the code; do not catch them in production.
    for (final void Function() bad in <void Function()>[
      () => root.child('a.b'),
      () => root.child('x').set(double.nan),
      () => root.orderByKey().limitToFirst(0),
      () => db.ref('.info/connected').set(true),
    ]) {
      try {
        bad();
      } on ArgumentError catch (error) {
        print('ArgumentError: ${error.message}');
      }
    }

    // 2. Errors from the server or the connection are FirebaseDatabaseException.
    // Branch on code; message is for people; serverStatus is for logs. A
    // refused write needs rules, see auth_and_rules.dart:
    try {
      await db.ref('example-private/nobody').set('x');
    } on FirebaseDatabaseException catch (error) {
      print('code: ${error.code}, status: ${error.serverStatus}');
    }

    // It is also a FirebaseException, so a general handler catches it.
    try {
      await db.ref('example-private/nobody').get();
    } on FirebaseException catch (error) {
      print('plugin: ${error.plugin}');
    }

    // 3. Offline is not an error: a write stays pending and a listener keeps
    // its data. get() waits 3 seconds for a connection, then answers from the
    // cache or fails with 'unavailable'.
    db.goOffline();
    try {
      await root.child('never-cached').get();
    } on FirebaseDatabaseException catch (error) {
      print('offline get: ${error.code}');
    }
    db.goOnline();

    // 4. A write the server never saw cannot be told apart from a slow one:
    // put a timeout around it if the user must not wait.
    try {
      db.goOffline();
      await root.child('slow').set(1).timeout(const Duration(seconds: 1));
    } on TimeoutException {
      print('write still queued after 1s');
    } finally {
      db.goOnline();
    }
  } finally {
    await root.remove();
    await db.close();
  }
}
