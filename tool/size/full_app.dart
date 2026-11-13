// The sample application of the size check (tool/check_size.sh), with the
// main library and a memory cache. Keep it in step with lite_app.dart, which
// does the same with Firestore Lite.
//
// It is compiled, never run.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      applicationId: 'appId',
      projectId: 'demo-size',
    ),
    name: 'size',
  );
  final Firestore firestore = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings(
      cacheSettings: const MemoryCacheSettings(),
    ).withEmulator('127.0.0.1', 8080),
  );
  final CollectionReference<Map<String, Object?>> cities = firestore.collection(
    'cities',
  );
  await cities.doc('SF').set(<String, Object?>{
    'name': 'San Francisco',
    'population': 800000,
  });
  await cities.doc('SF').update(<String, Object?>{
    'visits': FieldValue.increment(1),
  });
  print((await cities.doc('SF').get()).data);
  final QuerySnapshot<Map<String, Object?>> big = await cities
      .where('population', isGreaterThan: 100000)
      .orderBy('population')
      .limitToLast(2)
      .get();
  print(big.docs.length);
  print((await cities.count().get()).getCount());
  await (firestore.batch()..delete(cities.doc('LA'))).commit();
  await firestore.runTransaction<void>((Transaction transaction) async {
    final DocumentSnapshot<Map<String, Object?>> snapshot = await transaction
        .get(cities.doc('SF'));
    transaction.update(cities.doc('SF'), <String, Object?>{
      'seen': snapshot.exists,
    });
  });
  await firestore.terminate();
}
