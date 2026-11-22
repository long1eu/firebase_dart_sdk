// One atomic write to several places.
//
// Shows: update with multi-segment keys, null to delete, why it beats several
// set calls, and the rule on overlapping paths.
// Platform: Dart VM.
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 dart run example/multi_path_update.dart
// Backend: Realtime Database emulator, project demo-example.

import 'package:firebase_database_dart/firebase_database_dart.dart';

import 'common.dart';

Future<void> main() => runExample('multi-path', (db, root) async {
  // A post is kept in two places: the post and a list by author. Writing
  // them with two set() calls can leave one behind when the app stops
  // between the calls; one update() with path keys changes both or neither.
  final String postId = root.child('posts').push().key!;
  await root.update(<String, Object?>{
    'posts/$postId': <String, Object?>{'title': 'Hello', 'author': 'ada'},
    'by-author/ada/$postId': true,
    'counts/ada': ServerValue.increment(1),
  });
  print('posts: ${(await root.child('posts').get()).value}');
  print('by-author: ${(await root.child('by-author').get()).value}');

  // Deleting from both places in the same atomic write: null removes.
  await root.update(<String, Object?>{
    'posts/$postId': null,
    'by-author/ada/$postId': null,
    'counts/ada': ServerValue.increment(-1),
  });
  print(
    'after delete, posts exist: ${(await root.child('posts').get()).exists}',
  );

  // Keys are paths relative to the reference you call update on, and they
  // replace what is at that path. Here 'a/b' is replaced as a whole, 'a/c'
  // is left alone.
  await root.child('t').set(<String, Object?>{
    'a': <String, Object?>{
      'b': <String, Object?>{'x': 1},
      'c': 2,
    },
  });
  await root.child('t').update(<String, Object?>{
    'a/b': <String, Object?>{'y': 2},
  });
  print('t: ${(await root.child('t').get()).value}');

  // Two keys where one is the prefix of the other are refused at the call.
  try {
    await root.child('t').update(<String, Object?>{'a': 1, 'a/b': 2});
  } on ArgumentError {
    print('overlapping paths: ArgumentError');
  }

  // If the rules refuse any one path, the whole update fails and nothing is
  // written (see error_handling.dart).
});
