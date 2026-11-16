// Recipe: delete every document of a collection, a page at a time, so that a
// large collection never has to fit in memory or in one request.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/delete_collection.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

/// Deletes the documents of [collection] in pages of [pageSize]. Returns the
/// number of documents deleted. Subcollections of the documents are not
/// deleted.
Future<int> deleteCollection(
  CollectionReference<Map<String, Object?>> collection, {
  int pageSize = 200,
}) async {
  int deleted = 0;
  while (true) {
    // Ask the server, not the cache: the cache may not hold every document.
    final QuerySnapshot<Map<String, Object?>> page = await collection
        .limit(pageSize)
        .get(GetOptions(source: Source.server));
    if (page.isEmpty) {
      return deleted;
    }
    final WriteBatch batch = collection.firestore.batch();
    for (final QueryDocumentSnapshot<Map<String, Object?>> doc in page) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    deleted += page.length;
  }
}

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> logs = firestore.collection(
    scratch('logs'),
  );

  final WriteBatch batch = firestore.batch();
  for (int i = 0; i < 450; i++) {
    batch.set(logs.doc(), <String, Object?>{'line': i});
  }
  await batch.commit();

  print('deleted: ${await deleteCollection(logs)}');
  print('left: ${(await logs.count().get()).count}');

  await firestore.terminate();
}
