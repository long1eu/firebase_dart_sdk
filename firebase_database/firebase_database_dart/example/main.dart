// Quick start: connect, write, read, listen and clean up.
//
// Shows: a FirebaseDatabase on the local emulator, set, push, get, onValue.
// Platform: Dart VM (the package itself also runs on the web).
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/main.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() async {
  // One FirebaseDatabase is one connection. There is no global instance:
  // create it once and pass it around.
  final FirebaseDatabase db = emulatorDatabase();
  final DatabaseReference root = db.ref(freshKey('main'));
  try {
    // A reference is only a path; ref() and child() make no request.
    await root.child('greeting').set('hello');

    // push() makes a new child with a unique key, ordered by time. Nothing is
    // written until you set a value on it.
    final DatabaseReference message = root.child('messages').push();
    await message.set(<String, Object?>{
      'text': 'first message',
      'at': ServerValue.timestamp,
    });

    // get() reads once. A location with no data is not an error: exists is
    // false and value is null.
    final DataSnapshot greeting = await root.child('greeting').get();
    print('greeting: ${greeting.value}');
    print('nothing here: ${(await root.child('nope').get()).exists}');

    // onValue first gives the current data, then fires again after every change.
    final Stream<DatabaseEvent> events = root.child('greeting').onValue;
    final List<Object?> seen = <Object?>[];
    final subscription = events.listen((e) => seen.add(e.snapshot.value));
    await settle();
    await root.child('greeting').set('hello again');
    await settle();
    await subscription.cancel();
    print('onValue saw: $seen');
  } finally {
    // The data of this example is removed, and close() ends the connection.
    // An open FirebaseDatabase keeps a command-line program alive.
    await root.remove();
    await db.close();
  }
}
