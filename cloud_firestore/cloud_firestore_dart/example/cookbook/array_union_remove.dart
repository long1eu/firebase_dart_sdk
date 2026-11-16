// Recipe: add to and remove from an array field without reading it first,
// with `FieldValue.arrayUnion` and `FieldValue.arrayRemove`.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/array_union_remove.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final DocumentReference<Map<String, Object?>> post = firestore
      .collection(scratch('posts'))
      .doc('hello');
  await post.set(<String, Object?>{
    'tags': <String>['dart', 'news'],
  });

  // arrayUnion appends the elements that are not in the array yet.
  await post.update(<String, Object?>{
    'tags': FieldValue.arrayUnion(<String>['news', 'firestore']),
  });
  print('after union: ${(await post.get())['tags']}');

  // arrayRemove removes every copy of each element.
  await post.update(<String, Object?>{
    'tags': FieldValue.arrayRemove(<String>['news']),
  });
  print('after remove: ${(await post.get())['tags']}');

  // Maps in an array only match when the whole map is equal.
  await post.update(<String, Object?>{
    'likes': FieldValue.arrayUnion(<Object?>[
      <String, Object?>{'user': 'ada', 'at': 1},
    ]),
  });
  await post.update(<String, Object?>{
    'likes': FieldValue.arrayRemove(<Object?>[
      <String, Object?>{'user': 'ada'},
    ]),
  });
  print('likes after removing a partial map: ${(await post.get())['likes']}');

  await firestore.terminate();
}
