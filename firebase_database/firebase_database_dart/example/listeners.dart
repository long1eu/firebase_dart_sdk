// Listeners: onValue and the child streams, and the order of their events.
//
// Shows: onValue, onChildAdded, onChildChanged, onChildMoved, onChildRemoved,
// onChildEvents, once, and cancelling a subscription.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/listeners.dart
// Backend: Realtime Database emulator, project demo-example.

import 'dart:async';

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('listeners', (db, root) async {
  final DatabaseReference items = root.child('items');
  await items.set(<String, Object?>{'a': 1, 'b': 2});

  // Child streams fire once for each child that already exists, then for
  // each new one. A newcomer would expect them to wait for changes.
  final List<String> log = <String>[];
  final List<StreamSubscription<DatabaseEvent>> subscriptions =
      <StreamSubscription<DatabaseEvent>>[
        items.onValue.listen(
          (e) => log.add('value ${e.snapshot.children.length} children'),
        ),
        items.onChildAdded.listen(
          (e) => log.add('added ${e.snapshot.key} after ${e.previousChildKey}'),
        ),
        items.onChildChanged.listen(
          (e) => log.add('changed ${e.snapshot.key}=${e.snapshot.value}'),
        ),
        items.onChildRemoved.listen(
          (e) => log.add('removed ${e.snapshot.key}'),
        ),
        items.orderByValue().onChildMoved.listen(
          (e) => log.add('moved ${e.snapshot.key} after ${e.previousChildKey}'),
        ),
      ];
  await settle();
  log.add('--- initial events done');

  await items.child('c').set(3);
  await items.child('a').set(10); // changed; also moves 'a' in the value order
  await items.child('b').remove();
  await settle();
  print(log.join('\n'));

  // Inside one change the order is: removed, added, moved, changed, then
  // value. Four separate streams do not keep that order across them under
  // pause or `await for`; onChildEvents is one stream in the true order.
  final List<String> ordered = <String>[];
  final StreamSubscription<DatabaseEvent> all = items.onChildEvents.listen(
    (e) => ordered.add('${e.type.name} ${e.snapshot.key}'),
  );
  await settle();
  await items.child('d').set(4);
  await settle();
  await all.cancel();
  print('onChildEvents: $ordered');

  // A snapshot of a child event is the child, with its own reference.
  final DatabaseEvent first = await items.onChildAdded.first;
  print('child ref: ${first.snapshot.ref.path}');

  // once() takes the first event of a type and removes its listener.
  final DatabaseEvent once = await items.once();
  print('once: ${describe(once.snapshot)}');

  // Cancelling a subscription takes effect at once. A stream ends only when
  // the database closes or the server cancels it; losing the connection is
  // never an error on a stream (see connection_state.dart).
  for (final StreamSubscription<DatabaseEvent> s in subscriptions) {
    await s.cancel();
  }
});
