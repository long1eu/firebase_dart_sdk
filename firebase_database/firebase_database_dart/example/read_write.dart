// Reading and writing: set, update, remove, get and the shape of the values.
//
// Shows: set replaces, update merges, null removes, plain Dart values come back.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/read_write.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('read-write', (db, root) async {
  final DatabaseReference ada = root.child('users/ada');

  // set() replaces everything at the location, children included.
  await ada.set(<String, Object?>{'name': 'Ada', 'age': 36, 'city': 'London'});

  // update() changes only the keys you name and leaves the others.
  await ada.update(<String, Object?>{'age': 37});
  print('after update: ${(await ada.get()).value}');

  // A null value removes that child: there is no stored null in this
  // database, a location either has data or it does not.
  await ada.update(<String, Object?>{'city': null});
  print('after removing city: ${(await ada.get()).value}');

  // set() replaces: 'name' is gone after this.
  await ada.set(<String, Object?>{'age': 38});
  print('after set: ${(await ada.get()).value}');

  // Values are plain Dart data. Read them with patterns.
  if ((await ada.get()).value case {'age': num age}) {
    print('age is $age');
  }

  // An integral number reads back as int, also when you wrote 5.0.
  await root.child('n').set(5.0);
  print('5.0 reads as ${(await root.child('n').get()).value.runtimeType}');

  // A list is stored as a map with the index as key. The same location can
  // read back as a List (all keys are small integers) or as a Map, so iterate
  // children when the shape can vary.
  await root.child('list').set(<Object?>['a', 'b', 'c']);
  final DataSnapshot list = await root.child('list').get();
  print('list: ${list.value}, keys: ${list.children.map((c) => c.key)}');

  // The snapshot is unmodifiable; copy it to change it.
  try {
    (list.value! as List<Object?>).add('d');
  } on UnsupportedError {
    print('the value of a snapshot cannot be changed');
  }

  // remove() is set(null); an empty location has no data.
  await ada.remove();
  final DataSnapshot gone = await ada.get();
  print('exists: ${gone.exists}, value: ${gone.value}');

  // Bad values fail at the call with an ArgumentError, before any request.
  try {
    await root.child('bad').set(<String, Object?>{'a.b': 1});
  } on ArgumentError catch (error) {
    print('invalid key: ${error.runtimeType}');
  }
});
