// Recipe: find the documents whose embedding is nearest to a query vector,
// with `findNearest`. The search runs on the server only.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/nearest_neighbours.dart
//
// The emulator needs no index. A production database needs a vector index on
// the field, created with the Firebase CLI or the Google Cloud console.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> recipes = firestore
      .collection(scratch('recipes'));

  // Embeddings would come from a model; three dimensions keep this short.
  final WriteBatch batch = firestore.batch();
  <String, (String, List<double>)>{
    'pancakes': ('breakfast', <double>[0.9, 0.1, 0.0]),
    'omelette': ('breakfast', <double>[0.8, 0.3, 0.1]),
    'curry': ('dinner', <double>[0.1, 0.9, 0.4]),
    'salad': ('lunch', <double>[0.2, 0.2, 0.9]),
  }.forEach((String id, (String, List<double>) value) {
    batch.set(recipes.doc(id), <String, Object?>{
      'meal': value.$1,
      // Store the embedding as a vector, not as a plain array.
      'embedding': VectorValue(value.$2),
    });
  });
  await batch.commit();

  final List<double> query = <double>[1.0, 0.2, 0.0];

  // The two nearest documents, with their distance in a field of the result.
  final VectorQuerySnapshot nearest = await recipes
      .findNearest(
        vectorField: 'embedding',
        queryVector: query,
        limit: 2,
        distanceMeasure: DistanceMeasure.cosine,
        distanceResultField: 'distance',
      )
      .get();
  for (final QueryDocumentSnapshot<Object?> doc in nearest) {
    print(
      '${doc.id}: ${(doc.get('distance') as num?)?.toDouble().toStringAsFixed(3)}',
    );
  }

  // Filters of the base query apply before the search.
  final VectorQuerySnapshot dinner = await recipes
      .where('meal', isEqualTo: 'dinner')
      .findNearest(
        vectorField: 'embedding',
        queryVector: query,
        limit: 2,
        distanceMeasure: DistanceMeasure.euclidean,
      )
      .get();
  print('nearest dinner: ${<String>[for (final d in dinner) d.id]}');

  await firestore.terminate();
}
