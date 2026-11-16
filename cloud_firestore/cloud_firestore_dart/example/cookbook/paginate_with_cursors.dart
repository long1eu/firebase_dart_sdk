// Recipe: page through a large result with a cursor. Each page starts after
// the last document of the page before (`startAfterDocument`), so the backend
// never reads the documents of the earlier pages again.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/paginate_with_cursors.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> posts = firestore.collection(
    scratch('posts'),
  );

  final WriteBatch batch = firestore.batch();
  for (int i = 1; i <= 12; i++) {
    // Two posts per day: the ordering field has ties.
    batch.set(posts.doc('post$i'), <String, Object?>{'day': (i + 1) ~/ 2});
  }
  await batch.commit();

  // The query needs an order. A document cursor also holds the document id,
  // so posts with the same day are neither skipped nor repeated.
  final Query<Map<String, Object?>> ordered = posts.orderBy('day');
  const int pageSize = 5;

  DocumentSnapshot<Map<String, Object?>>? last;
  int pageNumber = 0;
  while (true) {
    Query<Map<String, Object?>> page = ordered.limit(pageSize);
    if (last != null) {
      page = page.startAfterDocument(last);
    }
    final QuerySnapshot<Map<String, Object?>> snapshot = await page.get();
    if (snapshot.isEmpty) {
      break;
    }
    pageNumber++;
    print('page $pageNumber: ${<String>[for (final d in snapshot) d.id]}');
    if (snapshot.length < pageSize) {
      break; // A short page is the last one.
    }
    last = snapshot.docs.last;
  }

  await firestore.terminate();
}
