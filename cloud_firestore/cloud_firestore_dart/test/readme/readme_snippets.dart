// GENERATED from the README files by
// test/unit/api/readme_snippets_test.dart. Do not edit: change the README
// and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'dart:io';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

late FirebaseApp app;
late Firestore firestore;
late CollectionReference<Map<String, Object?>> users;
late Query<Map<String, Object?>> query;
late List<int> bundleBytes;

class City {
  const City(this.name, this.population);
  factory City.fromMap(Map<String, Object?> m) =>
      City(m['name']! as String, m['population']! as int);
  final String name;
  final int population;
  Map<String, Object?> toMap() => {'name': name, 'population': population};
}

class MyDatabase implements Database {
  MyDatabase(this.path);

  @override
  final String path; // the file Firestore.clearPersistence() deletes

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, dynamic>>> query(String statement,
          [List<Object?>? arguments]) async =>
      <Map<String, dynamic>>[];

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) async => 0;

  @override
  void close() {}
}

// ../../README.md:11
Future<void> rootReadmeLine11() async {
  final firestore = await Firestore.instanceFor(app: app);
  await firestore.collection('users').doc('ada').set({'name': 'Ada', 'age': 36});

  firestore
      .collection('users')
      .where(Filter.or([
        Filter.equalTo('role', 'admin'),
        Filter.greaterThan('age', 40),
      ]))
      .limit(10)
      .snapshots
      .listen((snapshot) => print(snapshot.docs.length));
}

// README.md:84
Future<void> firestoreReadmeLine84() async {
  // `app` is a FirebaseApp created with firebase_app_dart.
  final firestore = await Firestore.instanceFor(app: app);
  final users = firestore.collection('users');
  await users.doc('ada').set({'name': 'Ada', 'age': 36});
  final adults = await users.whereGreaterThanOrEqualTo('age', 18).get();
}

// README.md:100
Future<void> firestoreReadmeLine100() async {
  final firestore = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// README.md:117
Future<void> firestoreReadmeLine117() async {
  final count = await users.count().get();                 // AggregateQuerySnapshot
  final agg = await users.aggregate([
    AggregateField.sum('age'),
    AggregateField.average('age'),
  ]).get();
  final either = await users
      .where(Filter.or([
        Filter.equalTo('city', 'Paris'),
        Filter.equalTo('city', 'Rome'),
      ]))
      .get();
  final last3 = await users.orderBy('age').limitToLast(3).get();
  final near = await users
      .findNearest('embedding', FieldValue.vector([0.1, 0.2, 0.3]), 5,
          DistanceMeasure.cosine)
      .get();
}

// README.md:139
Future<void> firestoreReadmeLine139() async {
  final converter = FirestoreDataConverter<City>.from(
    fromFirestore: (snapshot, options) => City.fromMap(snapshot.data!),
    toFirestore: (city, options) => city.toMap(),
  );

  final cities = firestore.collection('cities').withConverter<City>(converter);
  await cities.doc('sf').set(const City('San Francisco', 870000));   // CollectionReference<City>
  final City sf = (await cities.doc('sf').get()).data!;               // DocumentSnapshot<City>
  final big = await cities.whereGreaterThan('population', 500000).get();
  final names = [for (final c in big.docs) c.data.name];              // QueryDocumentSnapshot<City>
  final raw = cities.withoutConverter();                              // back to Map<String, Object?>
}

// README.md:170
Future<void> firestoreReadmeLine170() async {
  final settings = FirestoreSettings(
      cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024));
  final task = firestore.loadBundle(bundleBytes);          // LoadBundleTask
  final json = (await query.get()).toJson();               // e.g. sent from a server to a client
  final snapshot = QuerySnapshot.fromJson(firestore, json);
  firestore.querySnapshotsFromJson(json).listen((_) {});   // resumes listening from that snapshot
  await firestore.waitForPendingWrites();
  firestore.snapshotsInSync.listen((_) {});
  await firestore.terminate();
}

// README.md:202
Future<void> firestoreReadmeLine202() async {
  final PipelineSnapshot snapshot = await firestore
      .pipeline()
      .collection('books')
      .where(field('rating').greaterThan(4).and(field('genre').equal('Fantasy')))
      .addFields([field('title').toUpper().as('upperTitle')])
      .sort([field('rating').descending()])
      .limit(10)
      .execute();

  for (final PipelineResult result in snapshot.results) {
    print('${result.id}: ${result.data()}');
  }

  // One row per genre.
  await firestore
      .pipeline()
      .collection('books')
      .aggregate([countAll().as('count'), field('rating').average().as('avg')],
          groups: ['genre'])
      .execute();
}

// ../../firebase_core/firebase_app_dart/README.md:38
Future<void> appReadmeLine38() async {
}

// ../../firebase_core/firebase_app_dart/README.md:46
Future<void> appReadmeLine46() async {
  FirebaseOptions options;
  if (Platform.isLinux) {
    options = const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId:
          '<YOUR_APP_ID>',
    );
  } else if (Platform.isMacOS) {
    options = const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId:
          '<YOUR_APP_ID>',
    );
  } else if (Platform.isWindows) {
    options = const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId:
          '<YOUR_APP_ID>',
    );
  } else if (Platform.isAndroid) {
    options = const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '<YOUR_APP_ID>',
    );
  } else if (Platform.isIOS) {
    options = const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '<YOUR_APP_ID>',
    );
  } else if (Platform.isFuchsia) {
    options = const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId:
          '<YOUR_APP_ID>',
    );
  } else {
    throw UnsupportedError('No Firebase options for this platform.');
  }

  FirebaseApp.withOptions(options);
}

// ../../docs/migrating_from_vm_packages.md:54
Future<void> migrationGuideLine54() async {
}

// ../../docs/migrating_from_vm_packages.md:83
Future<void> migrationGuideLine83() async {
  final DocumentSnapshot<Map<String, Object?>> snapshot =
      await users.doc('ada').get();
  final Map<String, Object?>? data = snapshot.data; // null if it does not exist
  final int? age = data?['age'] as int?;
}

// ../../docs/migrating_from_vm_packages.md:107
Future<void> migrationGuideLine107() async {
  app.setDataCollectionDefaultEnabled(enabled: false);
}

// ../../docs/migrating_from_vm_packages.md:128
Future<void> migrationGuideLine128() async {
  final Firestore firestore = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
    // openDatabase: yourOpener, see section 5
  );
}

// ../../docs/migrating_from_vm_packages.md:143
Future<void> migrationGuideLine143() async {
  final Firestore emulated = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// ../../docs/migrating_from_vm_packages.md:172
Future<void> migrationGuideLine172() async {
}

// ../../docs/migrating_from_vm_packages.md:233
Future<void> migrationGuideLine233() async {
  final QuerySnapshot<Map<String, Object?>> result = await firestore
      .collection('users')
      .where(FieldPath.documentIdField, isEqualTo: 'ada')
      .get(Source.serverAndCache);
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in result.docs) {
    print(doc.ref.path);
  }
  await firestore.terminate();
}

// ../../docs/migrating_from_vm_packages.md:264
Future<void> migrationGuideLine264() async {
  final DocumentReference<Map<String, Object?>> ref =
      firestore.collection('users').doc('ada');
  final DocumentSnapshot<Map<String, Object?>> snapshot = await ref.get();
}

// ../../docs/migrating_from_vm_packages.md:298
Future<void> migrationGuideLine298() async {
  print('${firestore.projectId} / ${firestore.databaseName}');
}

// ../../docs/migrating_from_vm_packages.md:321
Future<void> migrationGuideLine321() async {
    final configRef = firestore.doc('config/plans');
    final userRef = users.doc('ada');
    await firestore.runTransaction<void>((Transaction tx) async {
      final config = await tx.get(configRef);
      tx.update(userRef, <String, Object?>{'plan': config.data!['plan']});
    });
}

// ../../docs/migrating_from_vm_packages.md:333
Future<void> migrationGuideLine333() async {
    await firestore.runTransaction<void>(
      (Transaction tx) async {},
      options: TransactionOptions(maxAttempts: 6),
    );
}
