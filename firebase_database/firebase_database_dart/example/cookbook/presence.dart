// Cookbook: who is online. Each client writes "online" and asks the server to
// write "offline" when its connection ends.
//
// Shows: onConnected, OnDisconnect, ServerValue.timestamp, a second client
// watching the list.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/cookbook/presence.dart
// Backend: Realtime Database emulator, project demo-example.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';

import '../common.dart';

/// Keeps [status] marked online while [db] is connected. Returns the
/// subscription, which the caller cancels to stop.
StreamSubscription<bool> keepPresent(
  FirebaseDatabase db,
  DatabaseReference status,
) {
  // Register again at every connection: the server forgets onDisconnect
  // writes when the connection ends, and the client does not keep them across
  // a restart. Order matters: register the offline write first, then write
  // online, so a crash between the two cannot leave a user stuck online.
  return db.onConnected.listen((bool connected) async {
    if (!connected) {
      return;
    }
    await status.onDisconnect.set(<String, Object?>{
      'state': 'offline',
      'at': ServerValue.timestamp,
    });
    await status.set(<String, Object?>{
      'state': 'online',
      'at': ServerValue.timestamp,
    });
  });
}

Future<void> main() => runExample('presence', (db, root) async {
  final FirebaseDatabase phone = emulatorDatabase(appName: 'phone');
  final DatabaseReference status = phone.ref(root.path).child('status/ada');
  final StreamSubscription<bool> present = keepPresent(phone, status);
  try {
    // Another client watches the list.
    final List<String> seen = <String>[];
    final sub = db.ref(root.path).child('status').onValue.listen((e) {
      seen.add(describe(e.snapshot).replaceAll(RegExp(r'\{.*?at: \d+'), '{'));
    });
    await db
        .ref(root.path)
        .child('status/ada/state')
        .onValue
        .firstWhere((DatabaseEvent e) => e.snapshot.value == 'online');
    print('ada is online');

    phone.goOffline(); // stands for a closed lid or a lost network
    await db
        .ref(root.path)
        .child('status/ada/state')
        .onValue
        .firstWhere((DatabaseEvent e) => e.snapshot.value == 'offline')
        .timeout(const Duration(seconds: 15));
    print('ada is offline');
    await sub.cancel();
  } finally {
    await present.cancel();
    await phone.close();
  }
});
