// Values the server fills in: the time and increments.
//
// Shows: ServerValue.timestamp, ServerValue.increment, the local estimate
// before the server answers, estimatedServerTime.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/server_values.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('server-values', (db, root) async {
  // The device clock can be wrong; ServerValue.timestamp is the time on the
  // server, in milliseconds since the epoch. It can sit anywhere in a value.
  final DatabaseReference post = root.child('post');
  final Future<void> write = post.set(<String, Object?>{
    'title': 'Hello',
    'createdAt': ServerValue.timestamp,
  });

  // Until the server answers, local events show an estimate from the device
  // clock corrected by serverTimeOffset. After the answer the real value
  // arrives as another event, which may differ by a few milliseconds.
  final List<Object?> seen = <Object?>[];
  final sub = post
      .child('createdAt')
      .onValue
      .listen((e) => seen.add(e.snapshot.value));
  await write;
  await settle();
  await sub.cancel();
  print('createdAt events: $seen');

  // Increment adds on the server, so concurrent clients never overwrite each
  // other, with no transaction round trip. A missing or non-number value
  // counts as 0.
  final DatabaseReference views = root.child('views');
  await views.set(ServerValue.increment(1));
  await Future.wait(<Future<void>>[
    for (int i = 0; i < 4; i++) views.set(ServerValue.increment(1)),
  ]);
  print('views: ${(await views.get()).value}');

  // Writes are at least once: if an acknowledgement is lost and the client
  // sends the write again after reconnecting, an increment is applied twice.
  // For exact counts, use a transaction (see transactions.dart).

  // The client's idea of the server's time, for the UI.
  print(
    'offset: ${db.serverTimeOffset}, now on the server: ${db.estimatedServerTime}',
  );
});
