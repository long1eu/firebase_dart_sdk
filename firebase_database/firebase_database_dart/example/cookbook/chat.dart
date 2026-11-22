// Cookbook: a chat room. Push keys for messages, a limited live window of the
// latest ones, and a typing flag cleared on disconnect.
//
// Shows: push, onChildAdded, limitToLast, ServerValue.timestamp, OnDisconnect,
// two clients.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/cookbook/chat.dart
// Backend: Realtime Database emulator, project demo-example.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';

import '../common.dart';

Future<void> main() => runExample('chat', (db, root) async {
  final FirebaseDatabase bobDb = emulatorDatabase(appName: 'bob');
  final DatabaseReference room = db.ref(root.path).child('rooms/1');
  final DatabaseReference bobRoom = bobDb.ref(root.path).child('rooms/1');
  try {
    // Bob listens to the last 3 messages and everything after them. A
    // limited query with onChildAdded gives the window first (oldest to
    // newest), then each new message; without the limit a long room would
    // download completely.
    final List<String> received = <String>[];
    final StreamSubscription<DatabaseEvent> listening = bobRoom
        .child('messages')
        .limitToLast(3)
        .onChildAdded
        .listen((e) {
          final Map<Object?, Object?> m =
              e.snapshot.value! as Map<Object?, Object?>;
          received.add('${m['from']}: ${m['text']}');
        });

    // Ada writes. push() keys keep the messages in the order they were sent;
    // the timestamp is the server's, not the sender's clock.
    for (final String text in <String>[
      'hi',
      'anyone here?',
      'bob?',
      'hello!',
    ]) {
      await room.child('messages').push().set(<String, Object?>{
        'from': 'ada',
        'text': text,
        'at': ServerValue.timestamp,
      });
    }

    // A typing flag that the server clears if the app disappears.
    final DatabaseReference typing = room.child('typing/ada');
    await typing.onDisconnect.remove();
    await typing.set(true);
    await typing.remove();

    await settle();
    await listening.cancel();
    print(received.join('\n'));
  } finally {
    await bobDb.close();
  }
});
