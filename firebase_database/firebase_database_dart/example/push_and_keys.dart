// Push ids and keys: lists in a database that has no lists.
//
// Shows: push, key, child, parent, root, path, url, the order of push keys.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/push_and_keys.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('push-and-keys', (db, root) async {
  final DatabaseReference log = root.child('log');

  // push() makes a key on this device, with no round trip. The keys sort by
  // creation time, also across devices, so a push list reads in the order it
  // was written. The key is known before the write completes.
  final DatabaseReference first = log.push();
  print('key before writing: ${first.key}');
  await first.set('one');
  await log.push().set('two');
  await log.push().set('three');

  // Reading the parent gives the values in key order = time order. A plain
  // List would reuse indexes and lose writes made at the same time.
  final DataSnapshot all = await log.get();
  print('in push order: ${all.children.map((c) => c.value).join(', ')}');

  // Keys can be compared as strings.
  final List<String?> keys = all.children.map((c) => c.key).toList();
  print('sorted: ${keys.toList()..sort()} == $keys');

  // Walk with child, parent and root. Empty segments are dropped.
  final DatabaseReference deep = root.child('a//b/c');
  print('path: ${deep.path}, key: ${deep.key}');
  print('parent: ${deep.parent!.path}');
  print(
    'root is a reference at path ${deep.root.path}, its key is ${deep.root.key}',
  );
  print('url: ${deep.url}');

  // Keys cannot contain . # \$ [ ] / or control characters; an invalid key
  // throws an ArgumentError at the call.
  try {
    root.child('bad.key');
  } on ArgumentError {
    print('"bad.key" is not a valid key');
  }

  // Keys that look like small integers are ordered as numbers, all other keys
  // as text. A parent whose keys are 0, 1, 2... reads back as a List, so use
  // push keys for data that is added concurrently.
  await root.child('mixed').set(<String, Object?>{
    '10': 'a',
    '9': 'b',
    'a': 'c',
    '01': 'd',
  });
  final DataSnapshot mixed = await root.child('mixed').orderByKey().get();
  print('orderByKey: ${mixed.children.map((c) => c.key).join(', ')}');
});
