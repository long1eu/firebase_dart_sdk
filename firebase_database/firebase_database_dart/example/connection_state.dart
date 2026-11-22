// The connection: .info/connected, going offline and back, queued writes.
//
// Shows: onConnected, isConnected, goOffline, goOnline, serverTimeOffset, and
// what a write does while offline.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/connection_state.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('connection', (db, root) async {
  // onConnected is the stream of `.info/connected`: its first event is the
  // current state, which is false until the first connection is up. Wait for
  // true before you rely on the server.
  final List<bool> states = <bool>[];
  final subscription = db.onConnected.listen(states.add);
  await db.onConnected.firstWhere((bool connected) => connected);
  print('connected: ${db.isConnected}, offset: ${db.serverTimeOffset}');

  // goOffline() is synchronous. Listeners keep their data and writes wait.
  db.goOffline();
  await settle();
  print('connected after goOffline: ${db.isConnected}');

  // A write while offline raises its local events at once but its Future
  // stays pending: it is queued, not failed. The listener sees the value
  // before the server does.
  final Future<void> queued = root.child('queued').set('written offline');
  final DatabaseEvent local = await root.child('queued').onValue.first;
  print('local value while offline: ${local.snapshot.value}');

  // goOnline() sends the queue, in order, and the Future completes.
  db.goOnline();
  await queued;
  print('write completed after reconnect');

  // A lost connection is never an error on a stream: a listener simply gets
  // its data again after reconnecting. Watch onConnected to show it in a UI.
  await subscription.cancel();
  print('connection states seen: $states');
});
