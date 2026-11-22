// Priority and the order of mixed values.
//
// Shows: set with priority, setPriority, DataSnapshot.priority,
// orderByPriority, and how orderByValue sorts values of different types.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/priority_and_ordering.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('priority', (db, root) async {
  final DatabaseReference queue = root.child('queue');

  // A priority is a number or a string kept next to the value. It is the old
  // way to sort; orderByChild covers most needs today, but you meet
  // priorities in existing data.
  await queue.child('low').set('write docs', priority: 30);
  await queue.child('high').set('fix bug', priority: 10);
  await queue.child('mid').set('review', priority: 20);
  await queue.child('none').set('someday'); // no priority

  // Without priority orderByPriority is the default order of children() too.
  // Children without a priority come first, then numbers, then strings.
  final ordered = await queue.orderByPriority().get();
  for (final DataSnapshot child in ordered.children) {
    print('${child.key}: ${child.value} (priority ${child.priority})');
  }

  // setPriority changes only the priority.
  await queue.child('low').setPriority(5);
  print('after setPriority: ${describe(await queue.orderByPriority().get())}');

  // A set() with no priority removes the priority: it is part of the data
  // the call replaces.
  await queue.child('low').set('write docs');
  print('priority after set: ${(await queue.child('low').get()).priority}');

  // The order of values of different types in orderByValue: null (no data
  // is never listed), false, true, numbers, strings, then objects by key.
  await root.child('mixed').set(<String, Object?>{
    'a': 'text',
    'b': 2,
    'c': true,
    'd': false,
    'e': 1,
    'f': <String, Object?>{'k': 1},
  });
  final mixed = await root.child('mixed').orderByValue().get();
  print(
    'by value: ${mixed.children.map((c) => '${c.key}:${c.value}').join(' ')}',
  );
});
