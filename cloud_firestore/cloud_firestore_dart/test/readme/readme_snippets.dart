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
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';

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

// README.md:146
Future<void> firestoreReadmeLine146() async {
  // `app` is a FirebaseApp created with firebase_app_dart.
  final firestore = await Firestore.instanceFor(app: app);
  final users = firestore.collection('users');
  await users.doc('ada').set({'name': 'Ada', 'age': 36});
  final adults = await users.whereGreaterThanOrEqualTo('age', 18).get();
}

// README.md:164
Future<void> firestoreReadmeLine164() async {
  final firestore = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// README.md:181
Future<void> firestoreReadmeLine181() async {
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

// README.md:203
Future<void> firestoreReadmeLine203() async {
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

// README.md:234
Future<void> firestoreReadmeLine234() async {
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

// README.md:267
Future<void> firestoreReadmeLine267() async {
  // A signed-in Firebase Auth user: the security rules see request.auth.
  final auth = await FirebaseUserAuth.forApp(app);
  final firestore = await Firestore.instanceFor(app: app);
  await auth.signInWithEmailAndPassword('ada@example.com', 'the password'); // or signInAnonymously(), ...

  // A server (bypasses security rules; access is decided by IAM):
  //   app.authProvider = OAuthTokenProvider.serviceAccount(serviceAccountJson);
  //   app.authProvider = applicationDefaultCredentials();   // package:.../adc.dart
}

// README.md:293
Future<void> firestoreReadmeLine293() async {
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

// README.md:319
Future<void> firestoreReadmeLine319() async {
  // An existing query as a pipeline: the same documents in the same order.
  final Query<Map<String, Object?>> italian = users
      .where('country', isEqualTo: 'IT')
      .orderBy('age', Direction.descending)
      .limit(20);
  final PipelineSnapshot same =
      await firestore.pipeline().createFrom(italian).execute();

  // A subquery: every author with the number of their books.
  await firestore
      .pipeline()
      .collection('authors')
      .define([field('name').as('author')])
      .select([
        'name',
        firestore
            .pipeline()
            .collection('books')
            .where(field('author').equal(variable('author')))
            .aggregate([countAll().as('count')])
            .toScalarExpression()
            .as('books'),
      ])
      .execute();

  // A lambda over an array.
  await firestore
      .pipeline()
      .collection('books')
      .select([field('tags').arrayFilter((tag) => tag.startsWith('sci')).as('tags')])
      .execute();

  // A write stage, applied in one transaction.
  final PipelineSnapshot written = await firestore
      .pipeline()
      .collection('books')
      .where(field('published').lessThan(1900))
      .update(transformedFields: [constant(true).as('classic')])
      .execute(atomic: true);
  print(written.results.single.get('documents_modified'));
}

// README.md:553
Future<void> firestoreReadmeLine553() async {
  final total = await firestore.runTransaction((transaction) async {
    final account = await transaction.get(firestore.doc('accounts/a'));
    final orders = await transaction.getQuery(
        firestore.collection('orders').where('account', isEqualTo: 'a'));
    final count = await transaction.getAggregate(firestore.collection('orders').count());
    return (account.data, orders.docs.length, count.getCount());
  }, options: TransactionOptions(readOnly: true));
}

// README.md:654
Future<void> firestoreReadmeLine654() async {
  final indexes = firestore.persistentCacheIndexManager; // null with a memory cache
  await indexes?.enableIndexAutoCreation();
}

// ../../firebase_core/firebase_app_dart/README.md:41
Future<void> appReadmeLine41() async {
}

// ../../firebase_core/firebase_app_dart/README.md:49
Future<void> appReadmeLine49() async {
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

// ../../docs/migrating_from_vm_packages.md:57
Future<void> migrationGuideLine57() async {
}

// ../../docs/migrating_from_vm_packages.md:86
Future<void> migrationGuideLine86() async {
  final DocumentSnapshot<Map<String, Object?>> snapshot =
      await users.doc('ada').get();
  final Map<String, Object?>? data = snapshot.data; // null if it does not exist
  final int? age = data?['age'] as int?;
}

// ../../docs/migrating_from_vm_packages.md:110
Future<void> migrationGuideLine110() async {
  app.setDataCollectionDefaultEnabled(enabled: false);
}

// ../../docs/migrating_from_vm_packages.md:131
Future<void> migrationGuideLine131() async {
  final Firestore firestore = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
    // openDatabase: yourOpener, see section 5
  );
}

// ../../docs/migrating_from_vm_packages.md:146
Future<void> migrationGuideLine146() async {
  final Firestore emulated = await Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// ../../docs/migrating_from_vm_packages.md:175
Future<void> migrationGuideLine175() async {
}

// ../../docs/migrating_from_vm_packages.md:257
Future<void> migrationGuideLine257() async {
  final QuerySnapshot<Map<String, Object?>> result = await firestore
      .collection('users')
      .where(FieldPath.documentIdField, isEqualTo: 'ada')
      .get(Source.serverAndCache);
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in result.docs) {
    print(doc.ref.path);
  }
  await firestore.terminate();
}

// ../../docs/migrating_from_vm_packages.md:288
Future<void> migrationGuideLine288() async {
  final DocumentReference<Map<String, Object?>> ref =
      firestore.collection('users').doc('ada');
  final DocumentSnapshot<Map<String, Object?>> snapshot = await ref.get();
}

// ../../docs/migrating_from_vm_packages.md:323
Future<void> migrationGuideLine323() async {
  print('${firestore.projectId} / ${firestore.databaseName}');
}

// ../../docs/migrating_from_vm_packages.md:346
Future<void> migrationGuideLine346() async {
    final configRef = firestore.doc('config/plans');
    final userRef = users.doc('ada');
    await firestore.runTransaction<void>((Transaction tx) async {
      final config = await tx.get(configRef);
      tx.update(userRef, <String, Object?>{'plan': config.data!['plan']});
    });
}

// ../../docs/migrating_from_vm_packages.md:358
Future<void> migrationGuideLine358() async {
    await firestore.runTransaction<void>(
      (Transaction tx) async {},
      options: TransactionOptions(maxAttempts: 6),
    );
}

// ../../docs/migrating_from_vm_packages.md:381
Future<void> migrationGuideLine381() async {
    await firestore.terminate();
    try {
      await users.doc('ada').get();
    } on FirestoreError catch (e) {
      print(e.code == FirestoreErrorCode.failedPrecondition); // true
    }
}
