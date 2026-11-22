// Queries: ordering, ranges and limits.
//
// Shows: orderByChild, orderByKey, orderByValue, startAt, endAt, startAfter,
// endBefore, equalTo, limitToFirst, limitToLast.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/queries.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('queries', (db, root) async {
  final DatabaseReference players = root.child('players');
  await players.set(<String, Object?>{
    'ann': <String, Object?>{'score': 30, 'team': 'red'},
    'bob': <String, Object?>{'score': 10, 'team': 'blue'},
    'cy': <String, Object?>{'score': 20, 'team': 'red'},
    'dee': <String, Object?>{'score': 40, 'team': 'blue'},
  });

  // A query is immutable: every modifier returns a new one. Results always
  // come in ascending order. For a top-3 board take the LAST three: there is
  // no descending order and no limit-and-reverse; reverse the list yourself.
  final top = await once(players.orderByChild('score').limitToLast(3));
  print('top 3 (ascending): ${describe(top)}');
  print(
    'top 3 (best first): ${top.children.toList().reversed.map((c) => c.key)}',
  );

  // Ranges: startAt and endAt are both included.
  final mid = await once(players.orderByChild('score').startAt(20).endAt(30));
  print('score 20..30: ${describe(mid)}');

  // startAfter and endBefore leave the bound out.
  final after = await once(players.orderByChild('score').startAfter(20));
  print('score > 20: ${describe(after)}');

  // equalTo matches one value; it already is a start and an end bound, so it
  // cannot be combined with startAt or endAt.
  final red = await once(players.orderByChild('team').equalTo('red'));
  print('team red: ${describe(red)}');

  // Order by key and by value.
  final byKey = await once(players.orderByKey().startAt('b').endAt('c'));
  print('keys b..c: ${describe(byKey)}');
  await root.child('flat').set(<String, Object?>{'x': 3, 'y': 1, 'z': 2});
  final byValue = await once(root.child('flat').orderByValue().limitToFirst(2));
  print('two smallest values: ${describe(byValue)}');

  // Children without the ordered child come first, with a null value.
  await players.child('eve').set(<String, Object?>{'team': 'red'});
  final all = await once(players.orderByChild('score').limitToFirst(1));
  print('no score first: ${describe(all)}');

  // The query decides the order of snapshot.children, but a value read as
  // a Map is not ordered by the query: iterate children, not value.

  // Rules are checked when you build a query: one orderBy, one start, one
  // end, one limit. A violation throws at the call.
  try {
    players.orderByKey().orderByValue();
  } on StateError catch (error) {
    print('second orderBy: StateError (${error.message})');
  }
  try {
    players.limitToFirst(0);
  } on ArgumentError {
    print('limit 0: ArgumentError');
  }

  // A query can be listened to like a reference; it is equal to another
  // query on the same path with the same parameters, and equal queries share
  // one listen on the server.
  print(players.orderByKey() == players.orderByKey());

  // Ordering by a child needs ".indexOn" in the rules of a real project, else
  // the read fails with 'index-not-defined' there. The emulator without rules
  // filters on the client and only warns.
});
