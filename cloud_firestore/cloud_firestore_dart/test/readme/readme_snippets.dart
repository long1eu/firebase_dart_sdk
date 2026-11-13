// GENERATED from the README files by
// test/unit/api/readme_snippets_test.dart. Do not edit: change the README
// and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import '../../example/sqlite_database.dart';
import '../../example/sqlite_database_web.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:firebase_auth_providers_dart/adc.dart'; // needs dart:io
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

late FirebaseApp app;
late Firestore firestore;
late CollectionReference<Map<String, Object?>> users;
late Query<Map<String, Object?>> query;
late List<int> bundleBytes;
late String password;
late String keyFilePath;

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

class FileAuthStorage implements AuthStorage {
  @override
  Future<String?> read(String key) async { /* ... */ return null; } // null: no value

  @override
  Future<void> write(String key, String? value) async { /* null removes the key */ }
}

class AppDependencies extends PlatformDependencies {
  final BehaviorSubject<bool> connectivity = BehaviorSubject<bool>.seeded(true);

  @override
  BehaviorSubject<bool> get onNetworkConnected => connectivity;
}

class City {
  const City(this.name, this.population);
  factory City.fromMap(Map<String, Object?> m) =>
      City(m['name']! as String, m['population']! as int);
  final String name;
  final int population;
  Map<String, Object?> toMap() => {'name': name, 'population': population};
}

// ../../README.md:11
Future<void> rootReadmeLine11() async {
  final firestore = Firestore.instanceFor(app: app);
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

// README.md:50
Future<void> firestoreReadmeLine50() async {
  Future<void> main() async {
    final app = FirebaseApp.withOptions(const FirebaseOptions(
        apiKey: '<API key>', applicationId: '1:1234567890:web:abc', projectId: 'my-project'));
    final firestore = Firestore.instanceFor(app: app);
    await firestore.doc('cities/SF').set({'name': 'San Francisco', 'state': 'CA'});
    final cities = await firestore.collection('cities').where('state', isEqualTo: 'CA').get();
    print(cities.docs.map((city) => city.data));
    await firestore.terminate(); // a VM program exits once its instances are terminated
  }
}

// ../../firebase_core/firebase_app_dart/README.md:34
Future<void> appReadmeLine34() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  print(identical(FirebaseApp.instance, app)); // the default app
}

// ../../firebase_auth/firebase_auth_providers_dart/README.md:80
Future<void> authProvidersReadmeLine80() async {
  // Before the Firestore instance is created: it becomes the token provider of the app.
  final auth = await FirebaseUserAuth.forApp(app);
  final firestore = Firestore.instanceFor(app: app);

  await auth.signInWithEmailAndPassword('ada@example.com', password);
  await firestore.doc('users/${auth.uid}/notes/first').set({'text': 'hello'});
  await auth.signOut();
}

// ../../docs/migrating_from_vm_packages.md:60
Future<void> migrationGuideLine60() async {
}

// ../../docs/migrating_from_vm_packages.md:89
Future<void> migrationGuideLine89() async {
  final DocumentSnapshot<Map<String, Object?>> snapshot =
      await users.doc('ada').get();
  final Map<String, Object?>? data = snapshot.data; // null if it does not exist
  final int? age = data?['age'] as int?;
}

// ../../docs/migrating_from_vm_packages.md:113
Future<void> migrationGuideLine113() async {
  app.setDataCollectionDefaultEnabled(enabled: false);
}

// ../../docs/migrating_from_vm_packages.md:138
Future<void> migrationGuideLine138() async {
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
    // openDatabase: yourOpener, see section 5
  );
}

// ../../docs/migrating_from_vm_packages.md:153
Future<void> migrationGuideLine153() async {
  final Firestore emulated = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// ../../docs/migrating_from_vm_packages.md:182
Future<void> migrationGuideLine182() async {
}

// ../../docs/migrating_from_vm_packages.md:270
Future<void> migrationGuideLine270() async {
  final QuerySnapshot<Map<String, Object?>> result = await firestore
      .collection('users')
      .where(FieldPath.documentIdField, isEqualTo: 'ada')
      .get(Source.serverAndCache);
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in result.docs) {
    print(doc.ref.path);
  }
  await firestore.terminate();
}

// ../../docs/migrating_from_vm_packages.md:301
Future<void> migrationGuideLine301() async {
  final DocumentReference<Map<String, Object?>> ref =
      firestore.collection('users').doc('ada');
  final DocumentSnapshot<Map<String, Object?>> snapshot = await ref.get();
}

// ../../docs/migrating_from_vm_packages.md:336
Future<void> migrationGuideLine336() async {
  print('${firestore.projectId} / ${firestore.databaseId}');
}

// ../../docs/migrating_from_vm_packages.md:359
Future<void> migrationGuideLine359() async {
    final configRef = firestore.doc('config/plans');
    final userRef = users.doc('ada');
    await firestore.runTransaction<void>((Transaction tx) async {
      final config = await tx.get(configRef);
      tx.update(userRef, <String, Object?>{'plan': config.data!['plan']});
    });
}

// ../../docs/migrating_from_vm_packages.md:375
Future<void> migrationGuideLine375() async {
    await firestore.runTransaction<void>(
      (Transaction tx) async {},
      options: TransactionOptions(maxAttempts: 6),
    );
}

// ../../docs/migrating_from_vm_packages.md:398
Future<void> migrationGuideLine398() async {
    await firestore.terminate();
    try {
      await users.doc('ada').get();
    } on FirestoreError catch (e) {
      print(e.code == FirestoreErrorCode.failedPrecondition); // true
    }
}

// ../../docs/guides/authentication.md:26
Future<void> authenticationGuideLine26() async {
  // A signed-in Firebase Auth user: the security rules see request.auth.
  final auth = await FirebaseUserAuth.forApp(app);
  final firestore = Firestore.instanceFor(app: app);
  await auth.signInWithEmailAndPassword('ada@example.com', 'the password'); // or signInAnonymously(), ...

  // A server (bypasses security rules; access is decided by IAM):
  //   app.authProvider = OAuthTokenProvider.serviceAccount(serviceAccountJson);
  //   app.authProvider = applicationDefaultCredentials();   // package:.../adc.dart
}

// ../../docs/guides/authentication.md:48
Future<void> authenticationGuideLine48() async {
  final app = FirebaseApp.withOptions(const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    applicationId: '1:1234567890:dart:example',
    projectId: 'my-project',
  ));

  // Before the Firestore instance is created: it becomes the token provider of the app.
  final auth = await FirebaseUserAuth.forApp(app);
  final firestore = Firestore.instanceFor(app: app);

  await auth.signInWithEmailAndPassword('ada@example.com', password);
  // or: auth.signInAnonymously(), auth.createUserWithEmailAndPassword(...),
  //     auth.signInWithCustomToken(tokenFromYourServer)

  await firestore.doc('users/${auth.uid}/notes/first').set({'text': 'hello'});

  await auth.signOut();
}

// ../../docs/guides/authentication.md:102
Future<void> authenticationGuideLine102() async {
  final auth = await FirebaseUserAuth.forApp(app, storage: FileAuthStorage());
  // auth.currentUser is the user of the last run, if there was one.
}

// ../../docs/guides/authentication.md:132
Future<void> authenticationGuideLine132() async {
  final auth = await FirebaseUserAuth.forApp(app,
      emulatorHost: FirebaseUserAuth.emulatorHostFromEnvironment); // FIREBASE_AUTH_EMULATOR_HOST
  // or emulatorHost: '127.0.0.1:9099'
}

// ../../docs/guides/authentication.md:158
Future<void> authenticationGuideLine158() async {
  final app = FirebaseApp.withOptions(const FirebaseOptions(
    apiKey: 'unused',            // required by FirebaseOptions, not sent with these credentials
    applicationId: '1:1234567890:dart:server',
    projectId: 'my-project',
  ));

  // Application Default Credentials: GOOGLE_APPLICATION_CREDENTIALS, gcloud, or the metadata server.
  app.authProvider = applicationDefaultCredentials();

  // Or a service account key (the decoded JSON of the key file, or its content as a string):
  app.authProvider = OAuthTokenProvider.serviceAccount(
      jsonDecode(File(keyFilePath).readAsStringSync()));

  final firestore = Firestore.instanceFor(app: app);
}

// ../../docs/guides/emulator_and_testing.md:22
Future<void> emulatorAndTestingGuideLine22() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key', // the emulator accepts any key and application id
      applicationId: '1:1234567890:dart:demo',
      projectId: 'demo-my-app',
    ),
  );
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
  );
}

// ../../docs/guides/emulator_and_testing.md:39
Future<void> emulatorAndTestingGuideLine39() async {
  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST']; // host:port
  final FirestoreSettings settings = emulator == null
      ? FirestoreSettings()
      : FirestoreSettings().withEmulator(
          emulator.substring(0, emulator.lastIndexOf(':')),
          int.parse(emulator.substring(emulator.lastIndexOf(':') + 1)),
        );
}

// ../../docs/guides/emulator_and_testing.md:57
Future<void> emulatorAndTestingGuideLine57() async {
  final Firestore asAlice = Firestore.instanceFor(
    app: FirebaseApp.withOptions(app.options, name: 'alice'),
    settings: FirestoreSettings().withEmulator('127.0.0.1', 8080, mockUserToken: {'sub': 'alice'}),
  );
}

// ../../docs/guides/emulator_and_testing.md:70
Future<void> emulatorAndTestingGuideLine70() async {
  late Firestore db;
  int instances = 0;

  setUp(() {
    // A new app name gives each test its own instance (and its own cache).
    final FirebaseApp testApp = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        applicationId: '1:1234567890:dart:test',
        projectId: 'demo-my-app',
      ),
      name: 'test-${instances++}',
    );
    db = Firestore.instanceFor(
      app: testApp,
      settings: FirestoreSettings().withEmulator('127.0.0.1', 8080),
    );
  });

  tearDown(() async {
    await db.terminate();
    await db.clearPersistence();
  });

  test('writes and reads a document', () async {
    // A collection name of its own keeps tests independent on a shared emulator.
    final DocumentReference<Map<String, Object?>> doc =
        db.collection('test-${DateTime.now().microsecondsSinceEpoch}').doc('a');
    await doc.set({'n': 1});
    expect((await doc.get()).data, {'n': 1});
  });
}

// ../../docs/guides/firebase_app.md:9
Future<void> firebaseAppGuideLine9() async {
  final FirebaseApp defaultApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );

  // More apps, for other projects or other users, have names of their own.
  final FirebaseApp secondary = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:dart:secondary',
      projectId: 'other-project',
    ),
    name: 'secondary',
  );
  print(identical(FirebaseApp.instance, defaultApp)); // true
  print(identical(FirebaseApp.getInstance('secondary'), secondary)); // true
}

// ../../docs/guides/firebase_app.md:67
Future<void> firebaseAppGuideLine67() async {
  final AppDependencies dependencies = AppDependencies();
  final FirebaseApp connectedApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
    name: 'connected',
    dependencies: dependencies,
  );

  // From the plugin's callback:
  dependencies.connectivity.add(true);
}

// ../../docs/guides/getting_started.md:24
Future<void> gettingStartedGuideLine24() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the Web API key of the project>',
      applicationId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );

  // Returns at once: the client opens its cache and connects in the background,
  // and every operation waits for that.
  final Firestore firestore = Firestore.instanceFor(app: app);
}

// ../../docs/guides/getting_started.md:53
Future<void> gettingStartedGuideLine53() async {
  final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');

  // Writes complete when the backend has acknowledged them.
  await cities.doc('SF').set({'name': 'San Francisco', 'state': 'CA', 'population': 870000});
  await cities.doc('SF').update({'population': FieldValue.increment(1)});
  final DocumentReference<Map<String, Object?>> added = await cities.add({'name': 'Tokyo'});

  // One read.
  final DocumentSnapshot<Map<String, Object?>> sf = await cities.doc('SF').get();
  print(sf.data);

  // A query.
  final QuerySnapshot<Map<String, Object?>> californian = await cities
      .where('state', isEqualTo: 'CA')
      .orderBy('population', Direction.descending)
      .limit(10)
      .get();
  for (final QueryDocumentSnapshot<Map<String, Object?>> city in californian.docs) {
    print('${city.id}: ${city.data}');
  }

  // Changes in real time, until the subscription is cancelled.
  final subscription = cities.where('state', isEqualTo: 'CA').snapshots.listen(
    (QuerySnapshot<Map<String, Object?>> snapshot) {
      for (final DocumentChange<Map<String, Object?>> change in snapshot.docChanges) {
        print('${change.type}: ${change.document.id}');
      }
    },
  );
  await subscription.cancel();
  await added.delete();
}

// ../../docs/guides/getting_started.md:97
Future<void> gettingStartedGuideLine97() async {
  // Writes that the backend has not acknowledged yet are kept in a persistent
  // cache and sent by the next instance; with a memory cache they are lost.
  await firestore.waitForPendingWrites();
  await firestore.terminate();
}

// ../../docs/guides/getting_started.md:140
Future<void> gettingStartedGuideLine140() async {
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    settings: FirestoreSettings(experimentalForceLongPolling: true),
  );
}

// ../../docs/guides/multiple_clients.md:70
Future<void> multipleClientsGuideLine70() async {
  final Directory directory = Directory('/home/ada/.local/share/my_app');

  // In the background isolate: the same project, another app name, another cache file.
  final FirebaseApp worker = FirebaseApp.withOptions(app.options, name: 'background-sync');
  final Firestore workerFirestore = Firestore.instanceFor(
    app: worker,
    openDatabase: sqliteOpener(directory),
  );
}

// ../../docs/guides/multiple_clients.md:96
Future<void> multipleClientsGuideLine96() async {
  await firestore.terminate();
  await firestore.clearPersistence();
}

// ../../docs/guides/offline_persistence.md:17
Future<void> offlinePersistenceGuideLine17() async {
  // Persistent (needs an openDatabase): unused documents are removed once the
  // cache grows beyond about 100 MB, the default.
  final FirestoreSettings persistent = FirestoreSettings(
    cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024),
  );

  // Never removes anything.
  final FirestoreSettings unlimited = FirestoreSettings(
    cacheSettings: PersistentCacheSettings(sizeBytes: FirestoreSettings.cacheSizeUnlimited),
  );

  // In memory, dropping documents as soon as no listener needs them (the default
  // for a memory cache)...
  final FirestoreSettings eager = FirestoreSettings(cacheSettings: const MemoryCacheSettings());

  // ...or keeping them up to a size, so that a query that was listened to before
  // can be answered offline.
  final FirestoreSettings lru = FirestoreSettings(
    cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings(sizeBytes: 40 * 1024 * 1024)),
  );
}

// ../../docs/guides/offline_persistence.md:55
Future<void> offlinePersistenceGuideLine55() async {
  final Directory directory = Directory('/home/ada/.local/share/my_app');
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory),
    settings: FirestoreSettings(cacheSettings: PersistentCacheSettings()),
  );
}

// ../../docs/guides/offline_persistence.md:80
Future<void> offlinePersistenceGuideLine80() async {
  // Only the cache, never the network.
  final DocumentSnapshot<Map<String, Object?>> cached =
      await firestore.doc('cities/SF').get(Source.cache);
  print(cached.metadata.isFromCache); // true

  // A write made offline is in the cache at once; its future completes when the
  // backend has accepted it, so do not wait for it before showing the change.
  final Future<void> write = firestore.doc('cities/SF').update({'visited': true});

  // Listeners say whether a snapshot holds writes the backend has not seen.
  firestore.doc('cities/SF').getSnapshots(MetadataChanges.include).listen(
    (DocumentSnapshot<Map<String, Object?>> snapshot) {
      print('pending: ${snapshot.metadata.hasPendingWrites}');
    },
  );

  // To take the client offline (or online) on purpose:
  await firestore.disableNetwork();
  await firestore.enableNetwork();
}

// ../../docs/guides/offline_persistence.md:117
Future<void> offlinePersistenceGuideLine117() async {
  final Directory directory = Directory('/home/ada/.local/share/my_app')
    ..createSync(recursive: true);
  if (!Platform.isWindows) {
    Process.runSync('chmod', <String>['700', directory.path]);
  }
}

// ../../docs/guides/offline_persistence.md:138
Future<void> offlinePersistenceGuideLine138() async {
  // IndexedDB: SQLite runs in the page on a copy of the whole database in memory.
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    openDatabase: sqliteWebOpener(sqlite3Wasm: Uri.parse('sqlite3.wasm')),
  );
}

// ../../docs/guides/offline_persistence.md:156
Future<void> offlinePersistenceGuideLine156() async {
  final Firestore firestore = Firestore.instanceFor(
    app: app,
    openDatabase: sqliteWebOpener(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      opfsWorker: Uri.parse('sqlite_opfs_worker.js'),
    ),
  );
}

// ../../docs/guides/offline_persistence.md:192
Future<void> offlinePersistenceGuideLine192() async {
  await firestore.terminate();        // the cache must not be in use by this instance
  await firestore.clearPersistence(); // deletes the files (or the browser storage)
  final Firestore fresh = Firestore.instanceFor(app: app);
}

// ../../docs/guides/offline_persistence.md:211
Future<void> offlinePersistenceGuideLine211() async {
  final indexes = firestore.persistentCacheIndexManager; // null with a memory cache
  await indexes?.enableIndexAutoCreation();
}

// ../../docs/guides/pipelines.md:21
Future<void> pipelinesGuideLine21() async {
  final PipelineSnapshot snapshot = await firestore
      .pipeline()
      .collection('books')
      .where(field('rating').greaterThan(4))
      .sort([field('rating').descending()])
      .limit(10)
      .execute();

  for (final PipelineResult result in snapshot.results) {
    print('${result.id}: ${result.data()}');
  }
}

// ../../docs/guides/pipelines.md:55
Future<void> pipelinesGuideLine55() async {
  // Computed fields and grouped aggregations.
  await firestore
      .pipeline()
      .collection('books')
      .addFields([field('title').toUpper().as('upperTitle')])
      .aggregate(
        [countAll().as('count'), field('rating').average().as('averageRating')],
        groups: ['genre'],
      )
      .execute();

  // Boolean expressions combine with and / or / not.
  await firestore
      .pipeline()
      .collectionGroup('reviews')
      .where(or(field('stars').equal(5), field('featured').equal(true)))
      .select(['title', 'stars'])
      .execute();

  // An existing query as a pipeline: the same documents in the same order.
  final PipelineSnapshot same = await firestore
      .pipeline()
      .createFrom(users.where('age', isGreaterThanOrEqualTo: 18).orderBy('age'))
      .execute();
}

// ../../docs/guides/pipelines.md:112
Future<void> pipelinesGuideLine112() async {
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
}

// ../../docs/guides/pipelines.md:152
Future<void> pipelinesGuideLine152() async {
  final PipelineSnapshot written = await firestore
      .pipeline()
      .collection('books')
      .where(field('published').lessThan(1900))
      .update(transformedFields: [constant(true).as('classic')])
      .execute(atomic: true); // in one transaction, committed at the end
  print(written.results.single.get('documents_modified'));
}

// ../../docs/guides/pipelines.md:173
Future<void> pipelinesGuideLine173() async {
  final PipelineSnapshot inSnapshot = await firestore.runTransaction(
    (Transaction transaction) => transaction.execute(
      firestore.pipeline().collection('books').where(field('genre').equal('Fantasy')),
    ),
    options: TransactionOptions(readOnly: true),
  );
}

// ../../docs/guides/pipelines.md:189
Future<void> pipelinesGuideLine189() async {
  final PipelineSnapshot explained = await firestore
      .pipeline()
      .collection('books')
      .where(field('rating').greaterThan(4))
      .execute(explainOptions: PipelineExplainOptions(mode: PipelineExplainMode.analyze));
  print(explained.explainStats);
}

// ../../docs/guides/queries_and_data.md:10
Future<void> queriesAndDataGuideLine10() async {
  // `app` is a FirebaseApp created with firebase_app_dart.
  final firestore = Firestore.instanceFor(app: app);
  final users = firestore.collection('users');
  await users.doc('ada').set({'name': 'Ada', 'age': 36});
  final adults = await users.whereGreaterThanOrEqualTo('age', 18).get();
}

// ../../docs/guides/queries_and_data.md:30
Future<void> queriesAndDataGuideLine30() async {
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

// ../../docs/guides/queries_and_data.md:53
Future<void> queriesAndDataGuideLine53() async {
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

// ../../docs/guides/queries_and_data.md:87
Future<void> queriesAndDataGuideLine87() async {
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

// ../../docs/guides/transactions_and_lifecycle.md:35
Future<void> transactionsAndLifecycleGuideLine35() async {
  final total = await firestore.runTransaction((transaction) async {
    final account = await transaction.get(firestore.doc('accounts/a'));
    final orders = await transaction.getQuery(
        firestore.collection('orders').where('account', isEqualTo: 'a'));
    final count = await transaction.getAggregate(firestore.collection('orders').count());
    return (account.data, orders.docs.length, count.getCount());
  }, options: TransactionOptions(readOnly: true));
}
