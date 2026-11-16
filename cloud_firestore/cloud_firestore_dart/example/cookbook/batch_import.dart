// Recipe: import many documents. The writes go in batches of a few hundred, so
// that each commit stays far below the 10 MiB request limit and a failure only
// costs one chunk. Fixed document ids make a second run after a failure safe.
//
// Run from cloud_firestore/cloud_firestore_dart against the emulator:
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/cookbook/batch_import.dart

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';

Future<void> main() async {
  final FirebaseFirestore firestore = connect();
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    scratch('cities'),
  );

  // Rows from a file, an API, another database...
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    for (int i = 0; i < 1234; i++)
      <String, Object?>{
        'id': 'city$i',
        'name': 'City $i',
        'population': i * 100,
      },
  ];

  const int chunkSize = 400;
  int written = 0;
  for (int start = 0; start < rows.length; start += chunkSize) {
    final int end = start + chunkSize > rows.length
        ? rows.length
        : start + chunkSize;
    final WriteBatch batch = firestore.batch();
    for (final Map<String, Object?> row in rows.sublist(start, end)) {
      // The id comes from the data, so importing the same row twice
      // overwrites the document instead of creating a copy.
      batch.set(cities.doc(row['id']! as String), <String, Object?>{
        'name': row['name'],
        'population': row['population'],
      });
    }
    await batch.commit();
    written = end;
    print('written $written of ${rows.length}');
  }

  print('count on the server: ${(await cities.count().get()).count}');
  await firestore.terminate();
}
