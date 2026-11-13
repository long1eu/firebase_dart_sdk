// GENERATED from the README files by
// test/unit/api/readme_snippets_test.dart. Do not edit: change the README
// and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'package:cloud_firestore_dart/lite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

late FirebaseApp app;
late Firestore firestore;

// ../../docs/guides/lite.md:23
Future<void> liteGuideLine23() async {
  // Synchronous, and nothing is sent until the first call.
  final Firestore firestore = Firestore.instanceFor(app: app);

  final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');
  await cities.doc('LA').set({'name': 'Los Angeles', 'state': 'CA', 'population': 3900000});

  final QuerySnapshot<Map<String, Object?>> californian =
      await cities.where('state', isEqualTo: 'CA').get();
  print(californian.docs.map((QueryDocumentSnapshot<Map<String, Object?>> doc) => doc.id).toList());

  final WriteBatch batch = firestore.batch()
    ..update(cities.doc('LA'), {'population': FieldValue.increment(1000)})
    ..delete(cities.doc('old'));
  await batch.commit();

  final AggregateQuerySnapshot count = await cities.count().get();
  print(count.getCount());

  await firestore.terminate();
}
