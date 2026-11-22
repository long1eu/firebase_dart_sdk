// Writes the server makes when a client disconnects.
//
// Shows: OnDisconnect.set, update, remove, cancel, and a second client seeing
// the result.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/on_disconnect.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('on-disconnect', (db, root) async {
  // The program needs two connections: one that goes away, one that watches.
  // Each instance has its own connection, so a second one is a second client.
  final FirebaseDatabase client = emulatorDatabase(appName: 'client');
  final DatabaseReference mine = client.ref(root.path).child('presence');
  try {
    // The server remembers the write and applies it when it sees this
    // connection end, even if the app crashed. The Future completes when the
    // server has registered it, not when it ran.
    await mine.child('state').onDisconnect.set('offline');
    await mine.child('room').onDisconnect.remove();
    await mine.child('state').set('online');
    await mine.child('room').set('kitchen');

    // The write is gone after a restart: register it again each time the
    // connection comes back (see cookbook/presence.dart).

    // Watch from the other client.
    final DatabaseReference watched = db.ref(root.path).child('presence/state');
    print('before: ${(await watched.get()).value}');

    // goOffline() ends the connection, and the server applies the writes.
    client.goOffline();
    final DatabaseEvent event = await watched.onValue
        .firstWhere((DatabaseEvent e) => e.snapshot.value == 'offline')
        .timeout(const Duration(seconds: 15));
    print('after disconnect: ${event.snapshot.value}');

    // cancel() takes registered writes back; update() registers a merge.
    client.goOnline();
    await client.onConnected.firstWhere((bool c) => c);
    await mine.child('state').onDisconnect.cancel();
    await mine.onDisconnect.update(<String, Object?>{
      'lastSeen': ServerValue.timestamp,
    });
  } finally {
    await client.close();
  }
});
