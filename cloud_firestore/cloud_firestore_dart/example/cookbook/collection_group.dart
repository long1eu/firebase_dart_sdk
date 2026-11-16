// Recipe: query every subcollection with the same name at once, such as the
// `reviews` under every product, with `collectionGroup`.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/collection_group.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  // A collection group spans the whole database. This example makes the
  // collection id unique per run so that earlier runs do not show up; in an
  // app it is a fixed name such as 'reviews'.
  final String reviews = 'reviews${DateTime.now().microsecondsSinceEpoch}';
  final CollectionReference<Map<String, Object?>> products = firestore
      .collection(scratch('products'));

  final WriteBatch batch = firestore.batch();
  for (final (String product, String author, int stars)
      in <(String, String, int)>[
        ('pen', 'ada', 5),
        ('pen', 'alan', 2),
        ('desk', 'ada', 4),
        ('lamp', 'grace', 5),
      ]) {
    batch.set(
      products.doc(product).collection(reviews).doc(),
      <String, Object?>{'author': author, 'stars': stars},
    );
  }
  await batch.commit();

  // Every review by ada, whatever product it belongs to.
  final QuerySnapshot<Map<String, Object?>> byAda = await firestore
      .collectionGroup(reviews)
      .where('author', isEqualTo: 'ada')
      .get();
  for (final QueryDocumentSnapshot<Map<String, Object?>> review in byAda) {
    // The parent of the review's collection is the product.
    print(
      'ada on ${review.reference.parent.parent!.id}: ${review['stars']} stars',
    );
  }

  // Aggregations work on collection groups too.
  print(
    'five-star reviews: '
    '${(await firestore.collectionGroup(reviews).where('stars', isEqualTo: 5).count().get()).getCount()}',
  );

  await firestore.terminate();
}
