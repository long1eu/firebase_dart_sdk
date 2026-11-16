// Recipe: match a field against a list of values with `whereIn`, and an array
// field against a list with `arrayContainsAny`, and what to do when the list is
// longer than the backend allows.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/in_and_array_contains_any.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> users = firestore.collection(
    scratch('users'),
  );

  final WriteBatch batch = firestore.batch();
  for (int i = 0; i < 40; i++) {
    batch.set(users.doc('u$i'), <String, Object?>{
      'team': 'team${i % 8}',
      'skills': <String>[if (i.isEven) 'dart', if (i % 3 == 0) 'go'],
    });
  }
  await batch.commit();

  // whereIn: the field equals one of the values.
  final QuerySnapshot<Map<String, Object?>> teams = await users
      .where('team', whereIn: <String>['team1', 'team2'])
      .get();
  print('team1 or team2: ${teams.length} users');

  // arrayContainsAny: the array field holds at least one of the values.
  final QuerySnapshot<Map<String, Object?>> coders = await users
      .where('skills', arrayContainsAny: <String>['dart', 'go'])
      .get();
  print('dart or go: ${coders.length} users');

  // The backend accepts at most 30 values in one filter (and 30 terms in the
  // whole query once OR filters are expanded). For a longer list, split it
  // and merge the results yourself. Documents are keyed by id, so a document
  // found by two chunks is counted once.
  final List<String> wanted = <String>[for (int i = 0; i < 35; i++) 'u$i'];
  final Map<String, QueryDocumentSnapshot<Map<String, Object?>>> found =
      <String, QueryDocumentSnapshot<Map<String, Object?>>>{};
  for (int start = 0; start < wanted.length; start += 30) {
    final List<String> chunk = wanted.sublist(
      start,
      start + 30 > wanted.length ? wanted.length : start + 30,
    );
    final QuerySnapshot<Map<String, Object?>> part = await users
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc in part) {
      found[doc.id] = doc;
    }
  }
  print('35 ids in two queries: ${found.length} users');

  // With 31 values the request fails on the backend, not in the client.
  try {
    await users
        .where(FieldPath.documentId, whereIn: wanted.sublist(0, 31))
        .get(Source.server);
    print('31 values: accepted');
  } on FirestoreException catch (e) {
    print('31 values: ${e.errorCode}');
  }

  await firestore.terminate();
}
