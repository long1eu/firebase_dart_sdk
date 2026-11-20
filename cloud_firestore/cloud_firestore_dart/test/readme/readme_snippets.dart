// GENERATED from the README files by
// test/unit/api/readme_snippets_test.dart. Do not edit: change the README
// and regenerate (see that file).
//
// This file is only analyzed, never run.

// ignore_for_file: type=lint, unused_local_variable, unused_import
// ignore_for_file: unused_element

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cache_store_testing.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/indexeddb_cache.dart';
import 'package:cloud_firestore_dart/pipelines.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:firebase_auth_providers_dart/adc.dart'; // needs dart:io
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

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

class KeychainAuthStorage implements AuthStorage {
  @override
  Future<String?> read(String key) async { /* ... */ return null; } // null: no value

  @override
  Future<void> write(String key, String? value) async { /* null removes the key */ }
}

class Product {
  const Product({required this.name, required this.price});
  factory Product.fromMap(Map<String, Object?> data) =>
      Product(name: data['name']! as String, price: (data['price']! as num).toDouble());
  final String name;
  final double price;
  Map<String, Object?> toMap() => {'name': name, 'price': price};
}

class SortedMapStore implements CacheStore {
  final SplayTreeMap<Uint8List, Uint8List> _data =
      SplayTreeMap<Uint8List, Uint8List>(compareCacheStoreKeys);

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<Uint8List?> get(Uint8List key) async => _data[key];

  @override
  Future<List<CacheStoreEntry>> scan(Uint8List start, Uint8List end,
      {bool reverse = false, int? limit}) async {
    final Iterable<MapEntry<Uint8List, Uint8List>> range = _data.entries.where(
        (MapEntry<Uint8List, Uint8List> e) =>
            compareCacheStoreKeys(e.key, start) >= 0 &&
            compareCacheStoreKeys(e.key, end) < 0);
    final Iterable<MapEntry<Uint8List, Uint8List>> ordered =
        reverse ? range.toList().reversed : range;
    return <CacheStoreEntry>[
      for (final MapEntry<Uint8List, Uint8List> e
          in limit == null ? ordered : ordered.take(limit))
        CacheStoreEntry(e.key, e.value),
    ];
  }

  @override
  Future<void> write(List<CacheStoreEntry> puts, List<Uint8List> deletes) async {
    for (final CacheStoreEntry entry in puts) {
      _data[entry.key] = entry.value;
    }
    deletes.forEach(_data.remove);
  }
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

// ../../README.md:56
Future<void> rootReadmeLine56() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(apiKey: 'demo-key', appId: '1:1234567890:dart:demo', projectId: 'demo-my-app'),
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings().withEmulator('127.0.0.1', 8080), // drop this line for a real project
  );

  await firestore.collection('users').doc('ada').set({'name': 'Ada', 'age': 36});
  firestore
      .collection('users')
      .where('age', isGreaterThan: 30)
      .snapshots()
      .listen((snapshot) => print(snapshot.docs.length));
}

// README.md:63
Future<void> firestoreReadmeLine63() async {
  Future<void> main() async {
    final app = FirebaseApp.withOptions(const FirebaseOptions(
        apiKey: '<API key>', appId: '1:1234567890:web:abc', projectId: 'my-project'));
    final firestore = FirebaseFirestore.instanceFor(app: app);
    await firestore.doc('cities/SF').set({'name': 'San Francisco', 'state': 'CA'});
    final cities = await firestore.collection('cities').where('state', isEqualTo: 'CA').get();
    print(cities.docs.map((city) => city.data()));
    await firestore.terminate(); // a VM program exits once its instances are terminated
  }
}

// ../../firebase_core/firebase_app_dart/README.md:25
Future<void> appReadmeLine25() async {
  // The default app. The values are in the Firebase console, Project settings, Your apps.
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );
  print(identical(FirebaseApp.instance, app)); // true

  // Set token providers on the app (app.authProvider = ...) here, before the service reads them.

  // Hand the app to a service.
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
  await firestore.doc('greetings/first').set(<String, Object?>{'text': 'hello'});
  await firestore.terminate();
}

// ../../firebase_auth/firebase_auth_providers_dart/README.md:27
Future<void> authProvidersReadmeLine27() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the Web API key of the project>',
      appId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
  );
  // Before the Firestore instance is created: it becomes the token provider of the app.
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);

  await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: password);
  await firestore.doc('users/${auth.uid}/notes/first').set({'text': 'hello'});
  await auth.signOut();
}

// ../../firebase_auth/firebase_auth_providers_dart/README.md:88
Future<void> authProvidersReadmeLine88() async {
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  auth.authStateChanges().listen((AuthUser? user) => print(user?.uid ?? 'signed out'));

  // From Google Sign-In, or any other way your app signs the user in with Google.
  const String googleIdToken = '<a Google ID token>';
  final UserCredential result = await auth.signInWithCredential(
    GoogleAuthProvider.credential(idToken: googleIdToken),
  );
  print(result.additionalUserInfo?.isNewUser);
}

// ../../firebase_auth/firebase_auth_providers_dart/README.md:169
Future<void> authProvidersReadmeLine169() async {
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  final UserCredential result = await auth.signInWithOAuthLoopback(
    OAuthLoopbackProvider.google(
      clientId: '<the client id of a "Desktop app" OAuth client>',
      clientSecret: '<its client secret>', // not confidential for a desktop client, says Google
    ),
  );
  print(result.user?.email);
}

// ../../docs/migrating_from_vm_packages.md:67
Future<void> migrationGuideLine67() async {
}

// ../../docs/migrating_from_vm_packages.md:96
Future<void> migrationGuideLine96() async {
  final DocumentSnapshot<Map<String, Object?>> snapshot =
      await users.doc('ada').get();
  final Map<String, Object?>? data = snapshot.data(); // null if it does not exist
  final int? age = data?['age'] as int?;
}

// ../../docs/migrating_from_vm_packages.md:120
Future<void> migrationGuideLine120() async {
  app.setAutomaticDataCollectionEnabled(false);
}

// ../../docs/migrating_from_vm_packages.md:145
Future<void> migrationGuideLine145() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(cacheSettings: PersistentCacheSettings()),
    // openDatabase: yourOpener, see section 5
  );
}

// ../../docs/migrating_from_vm_packages.md:160
Future<void> migrationGuideLine160() async {
  final FirebaseFirestore emulated = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings().withEmulator('127.0.0.1', 8080),
  );
}

// ../../docs/migrating_from_vm_packages.md:189
Future<void> migrationGuideLine189() async {
}

// ../../docs/migrating_from_vm_packages.md:277
Future<void> migrationGuideLine277() async {
  final QuerySnapshot<Map<String, Object?>> result = await firestore
      .collection('users')
      .where(FieldPath.documentId, isEqualTo: 'ada')
      .get(const GetOptions(source: Source.serverAndCache));
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in result.docs) {
    print(doc.reference.path);
  }
  await firestore.terminate();
}

// ../../docs/migrating_from_vm_packages.md:308
Future<void> migrationGuideLine308() async {
  final DocumentReference<Map<String, Object?>> ref =
      firestore.collection('users').doc('ada');
  final DocumentSnapshot<Map<String, Object?>> snapshot = await ref.get();
}

// ../../docs/migrating_from_vm_packages.md:343
Future<void> migrationGuideLine343() async {
  print('${firestore.projectId} / ${firestore.databaseId}');
}

// ../../docs/migrating_from_vm_packages.md:366
Future<void> migrationGuideLine366() async {
    final configRef = firestore.doc('config/plans');
    final userRef = users.doc('ada');
    await firestore.runTransaction<void>((Transaction tx) async {
      final config = await tx.get(configRef);
      tx.update(userRef, <String, Object?>{'plan': config.data()!['plan']});
    });
}

// ../../docs/migrating_from_vm_packages.md:382
Future<void> migrationGuideLine382() async {
    await firestore.runTransaction<void>(
      (Transaction tx) async {},
      maxAttempts: 6,
    );
}

// ../../docs/migrating_from_vm_packages.md:405
Future<void> migrationGuideLine405() async {
    await firestore.terminate();
    try {
      await users.doc('ada').get();
    } on FirestoreException catch (e) {
      print(e.errorCode == FirestoreErrorCode.failedPrecondition); // true
    }
}

// ../../docs/guides/authentication.md:51
Future<void> authenticationGuideLine51() async {
  // A signed-in Firebase Auth user: the security rules see request.auth.
  final auth = await FirebaseUserAuth.forApp(app);
  final firestore = FirebaseFirestore.instanceFor(app: app);
  await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: 'the password'); // or signInAnonymously(), ...

  // A server (bypasses security rules; access is decided by IAM):
  //   app.authProvider = OAuthTokenProvider.serviceAccount(serviceAccountJson);
  //   app.authProvider = applicationDefaultCredentials();   // package:.../adc.dart
}

// ../../docs/guides/authentication.md:73
Future<void> authenticationGuideLine73() async {
  final app = FirebaseApp.withOptions(const FirebaseOptions(
    apiKey: '<the Web API key of the project>',
    appId: '1:1234567890:dart:example',
    projectId: 'my-project',
  ));

  // Before the Firestore instance is created: it becomes the token provider of the app.
  final auth = await FirebaseUserAuth.forApp(app);
  final firestore = FirebaseFirestore.instanceFor(app: app);

  await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: password);
  // or: auth.signInAnonymously(), auth.createUserWithEmailAndPassword(...),
  //     auth.signInWithCustomToken(tokenFromYourServer)

  await firestore.doc('users/${auth.uid}/notes/first').set({'text': 'hello'});

  await auth.signOut();
}

// ../../docs/guides/authentication.md:192
Future<void> authenticationGuideLine192() async {
  final auth = await FirebaseUserAuth.forApp(app);
  const settings = ActionCodeSettings(
    url: 'https://my-project.web.app/finish-sign-in', // must be an authorized domain
    handleCodeInApp: true, // required for a sign-in link
  );
  await auth.sendSignInLinkToEmail(email: 'ada@example.com', actionCodeSettings: settings);
  // Keep the address until the link comes back (the backend wants it again).

  // Later, with the link the app received:
  const link = '<the link of the email>';
  if (auth.isSignInWithEmailLink(link)) {
    await auth.signInWithEmailLink(email: 'ada@example.com', emailLink: link);
  }
}

// ../../docs/guides/authentication.md:218
Future<void> authenticationGuideLine218() async {
  final auth = await FirebaseUserAuth.forApp(app);
  const googleIdToken = '<an ID token from Google Sign-In>';
  const appleIdToken = '<an ID token from Sign in with Apple>';
  const rawNonce = '<the nonce whose SHA-256 the app sent to Apple>';
  const oidcIdToken = '<an ID token of your OpenID Connect provider>';

  await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: googleIdToken));
  await auth.signInWithCredential(AppleAuthProvider.credentialWithIDToken(appleIdToken, rawNonce));
  await auth.signInWithCredential(OAuthProvider('oidc.my-provider').credential(idToken: oidcIdToken));
  // Access tokens: FacebookAuthProvider.credential(token), GithubAuthProvider.credential(token),
  // TwitterAuthProvider.credential(accessToken: ..., secret: ...), YahooAuthProvider.credential(token).
}

// ../../docs/guides/authentication.md:243
Future<void> authenticationGuideLine243() async {
  final auth = await FirebaseUserAuth.forApp(app);
  const googleIdToken = '<an ID token from Google Sign-In>';
  try {
    await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: googleIdToken));
  } on FirebaseAuthException catch (e) {
    if (e.code == 'account-exists-with-different-credential' && e.credential != null) {
      await auth.signInWithEmailAndPassword(email: e.email!, password: password);
      await auth.linkWithCredential(e.credential!);
    }
  }
}

// ../../docs/guides/authentication.md:276
Future<void> authenticationGuideLine276() async {
  final auth = await FirebaseUserAuth.forApp(app,
      storage: FileAuthStorage('${Platform.environment['HOME']}/.config/my_tool/session.json'));
  // auth.currentUser is the user of the last run, if there was one.
}

// ../../docs/guides/authentication.md:284
Future<void> authenticationGuideLine284() async {
}

// ../../docs/guides/authentication.md:313
Future<void> authenticationGuideLine313() async {
  final auth = await FirebaseUserAuth.forApp(app,
      emulatorHost: FirebaseUserAuth.emulatorHostFromEnvironment); // FIREBASE_AUTH_EMULATOR_HOST
  // or emulatorHost: '127.0.0.1:9099'
}

// ../../docs/guides/authentication.md:339
Future<void> authenticationGuideLine339() async {
  final app = FirebaseApp.withOptions(const FirebaseOptions(
    apiKey: '',                  // an empty key is not sent; any other key is, with each request
    appId: '1:1234567890:dart:server',
    projectId: 'my-project',
  ));

  // Application Default Credentials: GOOGLE_APPLICATION_CREDENTIALS, gcloud, or the metadata server.
  app.authProvider = applicationDefaultCredentials();

  // Or a service account key (the decoded JSON of the key file, or its content as a string):
  app.authProvider = OAuthTokenProvider.serviceAccount(
      jsonDecode(File(keyFilePath).readAsStringSync()));

  final firestore = FirebaseFirestore.instanceFor(app: app);
}

// ../../docs/guides/cookbook.md:48
Future<void> cookbookGuideLine48() async {
  final ordered = firestore.collection('posts').orderBy('day');
  DocumentSnapshot<Map<String, Object?>>? last;
  while (true) {
    var page = ordered.limit(20);
    if (last != null) page = page.startAfterDocument(last);
    final snapshot = await page.get();
    if (snapshot.isEmpty) break;
    // ... show snapshot.docs ...
    if (snapshot.length < 20) break; // a short page is the last one
    last = snapshot.docs.last;
  }
}

// ../../docs/guides/cookbook.md:75
Future<void> cookbookGuideLine75() async {
  final ordered = firestore.collection('messages').orderBy('rank');
  final pages = <StreamSubscription<QuerySnapshot<Map<String, Object?>>>>[];
  DocumentSnapshot<Map<String, Object?>>? end;

  // Called when the user reaches the bottom of the list.
  Future<void> loadNextPage() async {
    var next = ordered.limit(20);
    if (end != null) next = next.startAfterDocument(end!);
    final first = await next.get();
    if (first.isEmpty) return;
    end = first.docs.last;
    pages.add(ordered
        .startAtDocument(first.docs.first)
        .endAtDocument(first.docs.last)
        .snapshots()
        .listen((snapshot) {
      // ... replace the rows of this page with snapshot.docs ...
    }));
  }
}

// ../../docs/guides/cookbook.md:114
Future<void> cookbookGuideLine114() async {
  final orders = firestore.collection('orders');
  final count = (await orders.count().get()).count;

  final revenue = AggregateField.sum('total');
  final average = AggregateField.average('total');
  final paid = await orders
      .where('status', isEqualTo: 'paid')
      .aggregate([AggregateField.count(), revenue, average])
      .get();
  print('${paid.count} paid, ${paid.get(revenue)} in total, ${paid.get(average)} each');
}

// ../../docs/guides/cookbook.md:136
Future<void> cookbookGuideLine136() async {
  final page = firestore.collection('pages').doc('home');
  await page.update({'views': FieldValue.increment(1)});

  // Distributed: one of several shard documents per write, the total from a sum.
  final shards = page.collection('shards'); // shards '0' to '3' created with {'count': 0}
  await shards
      .doc('${Random().nextInt(4)}')
      .update({'count': FieldValue.increment(1)});
  final total = AggregateField.sum('count');
  final views = (await shards.aggregate([total]).get()).get(total);
}

// ../../docs/guides/cookbook.md:176
Future<void> cookbookGuideLine176() async {
  final post = firestore.collection('posts').doc('hello');
  await post.update({'tags': FieldValue.arrayUnion(['news', 'firestore'])});
  await post.update({'tags': FieldValue.arrayRemove(['news'])});
}

// ../../docs/guides/cookbook.md:197
Future<void> cookbookGuideLine197() async {
  final note = firestore.collection('notes').doc('n1');
  note.snapshots(includeMetadataChanges: true).listen((snapshot) {
    final Object? exact = snapshot['updatedAt']; // null while the write is pending
    final Object? estimate =
        snapshot.get('updatedAt', serverTimestamps: ServerTimestampBehavior.estimate); // the local clock
    final Object? previous =
        snapshot.get('updatedAt', serverTimestamps: ServerTimestampBehavior.previous); // the value before
    final bool pending = snapshot.metadata.hasPendingWrites;
  });
  await note.update({'text': 'second', 'updatedAt': FieldValue.serverTimestamp()});
}

// ../../docs/guides/cookbook.md:219
Future<void> cookbookGuideLine219() async {
}

// ../../docs/guides/cookbook.md:230
Future<void> cookbookGuideLine230() async {
  final products = firestore.collection('products').withConverter<Product>(
        fromFirestore: (snapshot, options) => Product.fromMap(snapshot.data()!),
        toFirestore: (product, options) => product.toMap(),
      );
  await products.doc('pen').set(const Product(name: 'Pen', price: 1.5));
  final Product pen = (await products.doc('pen').get()).data()!;
  final expensive = await products.where('price', isGreaterThan: 10).get();
  await products.doc('pen').update({'price': 2}); // update still takes a map
}

// ../../docs/guides/cookbook.md:249
Future<void> cookbookGuideLine249() async {
  final byAda = await firestore
      .collectionGroup('reviews')
      .where('author', isEqualTo: 'ada')
      .get();
  for (final review in byAda) {
    print('${review.reference.parent.parent!.id}: ${review['stars']}'); // the product's id
  }
}

// ../../docs/guides/cookbook.md:268
Future<void> cookbookGuideLine268() async {
  final users = firestore.collection('users');
  final ids = <String>[/* the document ids you want */];
  final teams = await users.where('team', whereIn: ['team1', 'team2']).get();
  final coders = await users.where('skills', arrayContainsAny: ['dart', 'go']).get();

  // More than 30 values: one query per chunk of 30, merged by document id.
  final found = <String, QueryDocumentSnapshot<Map<String, Object?>>>{};
  for (var i = 0; i < ids.length; i += 30) {
    final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
    for (final doc in await users.where(FieldPath.documentId, whereIn: chunk).get()) {
      found[doc.id] = doc;
    }
  }
}

// ../../docs/guides/cookbook.md:293
Future<void> cookbookGuideLine293() async {
  final tasks = firestore.collection('tasks');
  final mineOrUrgent = await tasks
      .where(Filter.or([
        Filter('owner', isEqualTo: 'ada'),
        Filter('priority', isGreaterThanOrEqualTo: 3),
      ]))
      .get();
  final openOnes = await tasks
      .where(Filter.and([
        Filter.or([
          Filter('owner', isEqualTo: 'ada'),
          Filter('priority', isGreaterThanOrEqualTo: 3),
        ]),
        Filter('done', isEqualTo: false),
      ]))
      .get();
}

// ../../docs/guides/cookbook.md:321
Future<void> cookbookGuideLine321() async {
  final rows = <Map<String, Object?>>[/* from a file, an API, another database */];
  final cities = firestore.collection('cities');
  for (var start = 0; start < rows.length; start += 400) {
    final end = start + 400 > rows.length ? rows.length : start + 400;
    final batch = firestore.batch();
    for (final row in rows.sublist(start, end)) {
      batch.set(cities.doc(row['id']! as String), {'name': row['name'], 'population': row['pop']});
    }
    await batch.commit();
    print('written $end of ${rows.length}');
  }
}

// ../../docs/guides/cookbook.md:344
Future<void> cookbookGuideLine344() async {
  Future<int> moveStock(DocumentReference<Map<String, Object?>> from,
      DocumentReference<Map<String, Object?>> to, int amount) {
    return firestore.runTransaction<int>((transaction) async {
      final source = await transaction.get(from); // all reads first
      final target = await transaction.get(to);
      final available = source.get('stock') as int? ?? 0;
      if (available < amount) throw StateError('only $available left');
      transaction
        ..update(from, {'stock': available - amount})
        ..set(to, {'stock': ((target.get('stock') as int?) ?? 0) + amount}, const SetOptions(merge: true));
      return available - amount;
    });
  }
}

// ../../docs/guides/cookbook.md:390
Future<void> cookbookGuideLine390() async {
  final accounts = firestore.collection('accounts');
  final orders = firestore.collection('orders');
  final report = await firestore.runTransaction((transaction) async {
    final account = await transaction.get(accounts.doc('ada'));
    final list = await transaction.getQuery(orders.where('account', isEqualTo: 'ada'));
    final spent = AggregateField.sum('total');
    final sum = await transaction.getAggregate(
        orders.where('account', isEqualTo: 'ada').aggregate([spent]));
    return '${account.get('credit')} credit, ${list.length} orders, ${sum.get(spent)} spent';
  }, readOnly: true);
}

// ../../docs/guides/cookbook.md:413
Future<void> cookbookGuideLine413() async {
  Future<int> deleteCollection(CollectionReference<Map<String, Object?>> collection) async {
    var deleted = 0;
    while (true) {
      final page = await collection.limit(200).get(const GetOptions(source: Source.server));
      if (page.isEmpty) return deleted;
      final batch = collection.firestore.batch();
      for (final doc in page) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += page.length;
    }
  }
}

// ../../docs/guides/cookbook.md:438
Future<void> cookbookGuideLine438() async {
  final theme = firestore.collection('settings').doc('theme');
  theme
      .snapshots(source: ListenSource.cache)
      .listen((snapshot) => print(snapshot['mode']));

  // A one-time read that only asks the server (and fills the cache):
  final fresh = await theme.get(const GetOptions(source: Source.server));
}

// ../../docs/guides/cookbook.md:459
Future<void> cookbookGuideLine459() async {
  final todos = firestore.collection('todos');
  todos.snapshots(includeMetadataChanges: true).listen((snapshot) {
    final offline = snapshot.metadata.isFromCache; // offline, or not synced yet
    for (final doc in snapshot) {
      final saving = doc.metadata.hasPendingWrites; // a local change the server has not confirmed
      // ... draw doc with a "saving" mark when `saving` ...
    }
  });

  // Optimistic UI: do not await the write; the listener shows it at once.
  unawaited(todos.doc('eggs').set({'title': 'Buy eggs'}));

  // Before exiting: wait until the server has every write made so far.
  await firestore.waitForPendingWrites();
  await firestore.terminate();
}

// ../../docs/guides/cookbook.md:489
Future<void> cookbookGuideLine489() async {
  final recipes = firestore.collection('recipes');
  await recipes.doc('pancakes').set({
    'meal': 'breakfast',
    'embedding': VectorValue([0.9, 0.1, 0.0]), // a vector, not a plain array
  });
  final nearest = await recipes
      .where('meal', isEqualTo: 'breakfast') // filters apply before the search
      .findNearest(vectorField: 'embedding', queryVector: [1.0, 0.2, 0.0], limit: 5, distanceMeasure: DistanceMeasure.cosine,
          distanceResultField: 'distance')
      .get();
  for (final doc in nearest) {
    print('${doc.id}: ${doc.get('distance')}');
  }
}

// ../../docs/guides/cookbook.md:514
Future<void> cookbookGuideLine514() async {
  final snapshot = await firestore.collection('events').orderBy('at').get();
  await File('events.json').writeAsString(jsonEncode(snapshot.toJson()));

  // Later, or in another process:
  final json = jsonDecode(await File('events.json').readAsString()) as Map<String, Object?>;
  final restored = QuerySnapshot<Map<String, Object?>>.fromJson(firestore, json);
}

// ../../docs/guides/custom_cache_store.md:9
Future<void> customCacheStoreGuideLine9() async {
  Future<void> withMyStore(CacheStore store) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(cacheSettings: keyValueCacheSettings(store: store)),
    );
    await firestore.collection('notes').add(<String, Object?>{'text': 'kept in my store'});
  }
}

// ../../docs/guides/custom_cache_store.md:89
Future<void> customCacheStoreGuideLine89() async {
}

// ../../docs/guides/custom_cache_store.md:153
Future<void> customCacheStoreGuideLine153() async {
  void checkMyStore(CacheStore Function() newEmptyStore) {
    for (final CacheStoreCheck check in cacheStoreConformanceChecks) {
      test(check.name, () => check.run(newEmptyStore));
    }
  }
}

// ../../docs/guides/emulator_and_testing.md:22
Future<void> emulatorAndTestingGuideLine22() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key', // the emulator accepts any key and application id
      appId: '1:1234567890:dart:demo',
      projectId: 'demo-my-app',
    ),
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings().withEmulator('127.0.0.1', 8080),
  );
}

// ../../docs/guides/emulator_and_testing.md:39
Future<void> emulatorAndTestingGuideLine39() async {
  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST']; // host:port
  final Settings settings = emulator == null
      ? Settings()
      : Settings().withEmulator(
          emulator.substring(0, emulator.lastIndexOf(':')),
          int.parse(emulator.substring(emulator.lastIndexOf(':') + 1)),
        );
}

// ../../docs/guides/emulator_and_testing.md:77
Future<void> emulatorAndTestingGuideLine77() async {
  final FirebaseFirestore asAlice = FirebaseFirestore.instanceFor(
    app: FirebaseApp.withOptions(app.options, name: 'alice'),
    settings: Settings().withEmulator('127.0.0.1', 8080, mockUserToken: {'sub': 'alice'}),
  );
}

// ../../docs/guides/emulator_and_testing.md:110
Future<void> emulatorAndTestingGuideLine110() async {
  late FirebaseFirestore db;
  int instances = 0;

  setUp(() {
    // A new app name gives each test its own instance (and its own cache).
    final FirebaseApp testApp = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:dart:test',
        projectId: 'demo-my-app',
      ),
      name: 'test-${instances++}',
    );
    db = FirebaseFirestore.instanceFor(
      app: testApp,
      settings: Settings().withEmulator('127.0.0.1', 8080),
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
    expect((await doc.get()).data(), {'n': 1});
  });
}

// ../../docs/guides/error_handling.md:33
Future<void> errorHandlingGuideLine33() async {
  try {
    await firestore.doc('cities/LA').update({'visited': true});
  } on FirestoreException catch (e) {
    if (e.errorCode == FirestoreErrorCode.notFound) {
      await firestore.doc('cities/LA').set({'visited': true});
    } else {
      rethrow;
    }
  }
}

// ../../docs/guides/error_handling.md:174
Future<void> errorHandlingGuideLine174() async {
  // The change is in the cache now; the future completes when the backend has it.
  unawaited(
    firestore.doc('cities/SF').set({'name': 'San Francisco'}).catchError(
      (Object e) => print('the backend rejected the write: $e'),
    ),
  );

  // Listeners say which snapshots hold writes that the backend has not seen yet.
  firestore.doc('cities/SF').snapshots(includeMetadataChanges: true).listen(
    (DocumentSnapshot<Map<String, Object?>> snapshot) {
      print('pending: ${snapshot.metadata.hasPendingWrites}');
    },
    onError: (Object e) => print('listener failed: $e'),
  );
}

// ../../docs/guides/error_handling.md:218
Future<void> errorHandlingGuideLine218() async {
  StreamSubscription<QuerySnapshot<Map<String, Object?>>> listen() {
    return users.snapshots().listen(
      (QuerySnapshot<Map<String, Object?>> snapshot) {
        print('${snapshot.docs.length} users');
      },
      onError: (Object error) {
        if (error is FirestoreException &&
            error.errorCode == FirestoreErrorCode.permissionDenied) {
          // The stream is closed. Listen again once the user may read the data,
          // for example after a sign-in.
          print('not allowed to read users');
        } else {
          print('listener failed: $error');
        }
      },
    );
  }

  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription = listen();
}

// ../../docs/guides/error_handling.md:297
Future<void> errorHandlingGuideLine297() async {
  final int total = await firestore.runTransaction(
    (Transaction transaction) async {
      final DocumentSnapshot<Map<String, Object?>> counter =
          await transaction.get(firestore.doc('counters/visits'));
      final int value = ((counter.data()?['value'] as int?) ?? 0) + 1;
      transaction.set(firestore.doc('counters/visits'), {'value': value});
      return value;
    },
    maxAttempts: 10,
  );
}

// ../../docs/guides/error_handling.md:321
Future<void> errorHandlingGuideLine321() async {
  bool isRetryable(FirestoreException error) {
    switch (error.errorCode) {
      case FirestoreErrorCode.unavailable:
      case FirestoreErrorCode.deadlineExceeded:
      case FirestoreErrorCode.resourceExhausted:
      case FirestoreErrorCode.internal:
      case FirestoreErrorCode.aborted:
        return true;
      default:
        return false;
    }
  }

  Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 5,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    final Random random = Random();
    Duration delay = initialDelay;
    for (int attempt = 1; ; attempt++) {
      try {
        return await operation();
      } on FirestoreException catch (error) {
        if (attempt >= maxAttempts || !isRetryable(error)) {
          rethrow;
        }
        await Future<void>.delayed(delay * (0.5 + random.nextDouble()));
        delay *= 1.5;
      }
    }
  }

  final AggregateQuerySnapshot count = await withRetry(() => users.count().get());
  print(count.count);
}

// ../../docs/guides/firebase_app.md:9
Future<void> firebaseAppGuideLine9() async {
  final FirebaseApp defaultApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );

  // More apps, for other projects or other users, have names of their own.
  final FirebaseApp secondary = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      appId: '1:1234567890:dart:secondary',
      projectId: 'other-project',
    ),
    name: 'secondary',
  );
  print(identical(FirebaseApp.instance, defaultApp)); // true
  print(identical(Firebase.app('secondary'), secondary)); // true
}

// ../../docs/guides/firebase_app.md:93
Future<void> firebaseAppGuideLine93() async {
  final AppDependencies dependencies = AppDependencies();
  final FirebaseApp connectedApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      appId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
    name: 'connected',
    dependencies: dependencies,
  );

  // From the plugin's callback:
  dependencies.connectivity.add(true);
}

// ../../docs/guides/for_ai_agents.md:39
Future<void> forAiAgentsGuideLine39() async {
  Future<void> main() async {
    // Synchronous. A `demo-` project id keeps the emulator away from real projects; the emulator
    // accepts any API key and application id.
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:dart:demo',
        projectId: 'demo-my-app',
      ),
    );

    // The package does not read FIRESTORE_EMULATOR_HOST itself.
    final String emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
    final int colon = emulator.lastIndexOf(':');
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings().withEmulator(
        emulator.substring(0, colon),
        int.parse(emulator.substring(colon + 1)),
      ),
    );

    try {
      final CollectionReference<Map<String, Object?>> users = firestore.collection('users');
      await users.doc('ada').set(<String, Object?>{'name': 'Ada', 'age': 36});
      await users.doc('ada').update(<String, Object?>{'age': FieldValue.increment(1)});

      final DocumentSnapshot<Map<String, Object?>> ada = await users.doc('ada').get();
      print('${ada.id}: ${ada.data()}');

      final QuerySnapshot<Map<String, Object?>> adults = await users
          .where('age', isGreaterThanOrEqualTo: 18)
          .orderBy('age', descending: true)
          .limit(10)
          .get();
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc in adults.docs) {
        print('${doc.id} ${doc.data()['name']}');
      }
    } on FirestoreException catch (e) {
      stderr.writeln('Firestore failed: ${e.code} ${e.message}');
      exitCode = 1;
    } finally {
      // Without this the open gRPC channel keeps the process alive.
      await firestore.terminate();
    }
  }
}

// ../../docs/guides/for_ai_agents.md:98
Future<void> forAiAgentsGuideLine98() async {
  Future<void> main() async {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: '', // an empty key is not sent
        appId: '1:1234567890:dart:server', // any unique id works on a server
        projectId: Platform.environment['FIREBASE_PROJECT_ID'] ?? 'my-project',
      ),
    );

    // Before FirebaseFirestore.instanceFor. GOOGLE_APPLICATION_CREDENTIALS, then gcloud's application
    // default login, then the metadata server (Cloud Run, Compute Engine, GKE).
    // These credentials bypass security rules; IAM decides (role Cloud Datastore User).
    app.authProvider = applicationDefaultCredentials();

    // One instance for the whole process, shared by every request. No openDatabase: nothing is
    // written to disk, and eager garbage collection drops documents no listener needs.
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(
        cacheSettings: const MemoryCacheSettings(gcSettings: MemoryEagerGcSettings()),
      ),
    );

    // Source.server: never answer a request from a stale cache.
    final DocumentSnapshot<Map<String, Object?>> config = await firestore
        .doc('config/app')
        .get(const GetOptions(source: Source.server));
    print(config.exists ? config.data() : 'no config');

    await firestore.terminate();
  }
}

// ../../docs/guides/for_ai_agents.md:371
Future<void> forAiAgentsGuideLine371() async {
  void main() {
    late FirebaseFirestore db;
    int instances = 0;

    setUp(() {
      // A new app name per test gives each test its own instance and cache.
      final FirebaseApp app = FirebaseApp.withOptions(
        const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1234567890:dart:test',
          projectId: 'demo-my-app',
        ),
        name: 'test-${instances++}',
      );
      db = FirebaseFirestore.instanceFor(
        app: app,
        settings: Settings().withEmulator('127.0.0.1', 8080),
      );
    });

    tearDown(() async {
      await db.terminate();
      await db.clearPersistence();
    });

    test('writes and reads a document', () async {
      final DocumentReference<Map<String, Object?>> doc = db
          .collection('test-${DateTime.now().microsecondsSinceEpoch}')
          .doc('a');
      await doc.set(<String, Object?>{'n': 1});
      expect((await doc.get()).data(), <String, Object?>{'n': 1});
    });
  }
}

// ../../docs/guides/getting_started.md:47
Future<void> gettingStartedGuideLine47() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the Web API key of the project>',
      appId: '1:1234567890:web:0123456789abcdef',
      projectId: 'my-project',
    ),
  );

  // Returns at once: the client opens its cache and connects in the background,
  // and every operation waits for that.
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);
}

// ../../docs/guides/getting_started.md:99
Future<void> gettingStartedGuideLine99() async {
  final CollectionReference<Map<String, Object?>> cities = firestore.collection('cities');

  // Writes complete when the backend has acknowledged them.
  await cities.doc('SF').set({'name': 'San Francisco', 'state': 'CA', 'population': 870000});
  await cities.doc('SF').update({'population': FieldValue.increment(1)});
  final DocumentReference<Map<String, Object?>> added = await cities.add({'name': 'Tokyo'});

  // One read.
  final DocumentSnapshot<Map<String, Object?>> sf = await cities.doc('SF').get();
  print(sf.data());

  // A query.
  final QuerySnapshot<Map<String, Object?>> californian = await cities
      .where('state', isEqualTo: 'CA')
      .orderBy('population', descending: true)
      .limit(10)
      .get();
  for (final QueryDocumentSnapshot<Map<String, Object?>> city in californian.docs) {
    print('${city.id}: ${city.data()}');
  }

  // Changes in real time, until the subscription is cancelled.
  final subscription = cities.where('state', isEqualTo: 'CA').snapshots().listen(
    (QuerySnapshot<Map<String, Object?>> snapshot) {
      for (final DocumentChange<Map<String, Object?>> change in snapshot.docChanges) {
        print('${change.type}: ${change.doc.id}');
      }
    },
  );
  await subscription.cancel();
  await added.delete();
}

// ../../docs/guides/getting_started.md:143
Future<void> gettingStartedGuideLine143() async {
  // Writes that the backend has not acknowledged yet are kept in a persistent
  // cache and sent by the next instance; with a memory cache they are lost.
  await firestore.waitForPendingWrites();
  await firestore.terminate();
}

// ../../docs/guides/getting_started.md:190
Future<void> gettingStartedGuideLine190() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(webExperimentalForceLongPolling: true),
  );
}

// ../../docs/guides/long_offline.md:120
Future<void> longOfflineGuideLine120() async {
  final Settings settings = Settings(
    cacheSettings: PersistentCacheSettings(
      // One pending write per document, instead of one per edit.
      mergeUnsentWrites: true,
      // Cache indexes for queries that scanned many backend documents.
      indexAutoCreation: true,
      // Fill them faster than 50 documents a minute.
      indexBackfill: IndexBackfillSettings(
        documentsPerRun: 200,
        interval: const Duration(seconds: 10),
      ),
    ),
  );
}

// ../../docs/guides/long_offline.md:211
Future<void> longOfflineGuideLine211() async {
  final int total = await firestore.getPendingWriteCount();
  final StreamSubscription<int> progress = firestore.pendingWriteCounts().listen(
    (int pending) => print('sent ${total - pending} of $total'),
  );
  await firestore.waitForPendingWrites();
  await progress.cancel();
}

// ../../docs/guides/migrating_from_flutterfire.md:107
Future<void> migratingFromFlutterfireGuideLine107() async {
  // The values of a web app of the project (Firebase console, Project settings,
  // Your apps) work on every platform. From a generated firebase_options.dart:
  // the same names: apiKey, appId, projectId.
  final FirebaseApp firebaseApp = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<the apiKey of DefaultFirebaseOptions.web>',
      appId: '<the appId of DefaultFirebaseOptions.web>',
      projectId: '<the projectId>',
    ),
  );
}

// ../../docs/guides/migrating_from_flutterfire.md:155
Future<void> migratingFromFlutterfireGuideLine155() async {
  final String cacheDirectory = '<the application support directory>';
  final FirebaseFirestore persistent = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory: cacheDirectory),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
}

// ../../docs/guides/migrating_from_flutterfire.md:182
Future<void> migratingFromFlutterfireGuideLine182() async {
  final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(app);
  final FirebaseFirestore signedIn = FirebaseFirestore.instanceFor(app: app);
  await auth.signInWithEmailAndPassword(email: 'ada@example.com', password: password);
}

// ../../docs/guides/migrating_from_flutterfire.md:337
Future<void> migratingFromFlutterfireGuideLine337() async {
  final QuerySnapshot<Map<String, Object?>> page = await firestore
      .collection('users')
      .where('age', isGreaterThanOrEqualTo: 18)
      .orderBy('age', descending: true)
      .limit(20)
      .get(const GetOptions(source: Source.cache));
  print(page.length);
  for (final DocumentChange<Map<String, Object?>> change in page.docChanges) {
    print(change.doc.id);
  }

  final AggregateQuerySnapshot totals = await users.aggregate(<AggregateField>[
    AggregateField.count(),
    AggregateField.sum('age'),
  ]).get();
  print('${totals.count} users, ${totals.get(AggregateField.sum('age'))} years');
}

// ../../docs/guides/multiple_clients.md:122
Future<void> multipleClientsGuideLine122() async {
  // In the background isolate: the same project, another app name, another cache file.
  final FirebaseApp worker = FirebaseApp.withOptions(app.options, name: 'background-sync');
  final FirebaseFirestore workerFirestore = FirebaseFirestore.instanceFor(
    app: worker,
    openDatabase: sqliteOpener(directory: '/home/ada/.local/share/my_app'),
  );
}

// ../../docs/guides/multiple_clients.md:145
Future<void> multipleClientsGuideLine145() async {
  await firestore.terminate();
  await firestore.clearPersistence();
}

// ../../docs/guides/offline_persistence.md:31
Future<void> offlinePersistenceGuideLine31() async {
  // Persistent (needs an openDatabase): unused documents are removed once the
  // cache grows beyond about 100 MB, the default.
  final Settings persistent = Settings(
    cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024),
  );

  // Never removes anything.
  final Settings unlimited = Settings(
    cacheSettings: PersistentCacheSettings(sizeBytes: Settings.cacheSizeUnlimited),
  );

  // In memory, dropping documents as soon as no listener needs them (the default
  // for a memory cache)...
  final Settings eager = Settings(cacheSettings: const MemoryCacheSettings());

  // ...or keeping them up to a size, so that a query that was listened to before
  // can be answered offline.
  final Settings lru = Settings(
    cacheSettings: MemoryCacheSettings(gcSettings: MemoryLruGcSettings(sizeBytes: 40 * 1024 * 1024)),
  );
}

// ../../docs/guides/offline_persistence.md:73
Future<void> offlinePersistenceGuideLine73() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory: '/home/ada/.local/share/my_app'),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
}

// ../../docs/guides/offline_persistence.md:108
Future<void> offlinePersistenceGuideLine108() async {
  final OpenDatabase opener = sqliteOpener(
    directory: '/home/ada/.local/share/my_app',
    pageCacheMb: 32,
  );
}

// ../../docs/guides/offline_persistence.md:129
Future<void> offlinePersistenceGuideLine129() async {
  // Only the cache, never the network.
  final DocumentSnapshot<Map<String, Object?>> cached =
      await firestore.doc('cities/SF').get(const GetOptions(source: Source.cache));
  print(cached.metadata.isFromCache); // true

  // A write made offline is in the cache at once; its future completes when the
  // backend has accepted it, so do not wait for it before showing the change.
  final Future<void> write = firestore.doc('cities/SF').update({'visited': true});

  // Listeners say whether a snapshot holds writes the backend has not seen.
  firestore.doc('cities/SF').snapshots(includeMetadataChanges: true).listen(
    (DocumentSnapshot<Map<String, Object?>> snapshot) {
      print('pending: ${snapshot.metadata.hasPendingWrites}');
    },
  );

  // To take the client offline (or online) on purpose:
  await firestore.disableNetwork();
  await firestore.enableNetwork();
}

// ../../docs/guides/offline_persistence.md:189
Future<void> offlinePersistenceGuideLine189() async {
  final int total = await firestore.getPendingWriteCount();
  final StreamSubscription<int> progress = firestore.pendingWriteCounts().listen(
    (int pending) => print('syncing ${total - pending} of $total'),
  );
  // ...
  await progress.cancel();
}

// ../../docs/guides/offline_persistence.md:227
Future<void> offlinePersistenceGuideLine227() async {
  final Settings settings = Settings(
    cacheSettings: PersistentCacheSettings(mergeUnsentWrites: true),
  );
}

// ../../docs/guides/offline_persistence.md:357
Future<void> offlinePersistenceGuideLine357() async {
  final Directory directory = Directory('/home/ada/.local/share/my_app')
    ..createSync(recursive: true);
  if (!Platform.isWindows) {
    Process.runSync('chmod', <String>['700', directory.path]);
  }
}

// ../../docs/guides/offline_persistence.md:382
Future<void> offlinePersistenceGuideLine382() async {
  // IndexedDB: SQLite runs in the page on a copy of the whole database in memory.
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(), // loads sqlite3.wasm next to the page
  );
}

// ../../docs/guides/offline_persistence.md:399
Future<void> offlinePersistenceGuideLine399() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(opfsWorker: Uri.parse('sqlite_opfs_worker.js')),
  );
}

// ../../docs/guides/offline_persistence.md:439
Future<void> offlinePersistenceGuideLine439() async {
  await firestore.terminate();        // the cache must not be in use by this instance
  await firestore.clearPersistence(); // deletes the files (or the browser storage)
  final FirebaseFirestore fresh = FirebaseFirestore.instanceFor(app: app);
}

// ../../docs/guides/offline_persistence.md:458
Future<void> offlinePersistenceGuideLine458() async {
  final indexes = firestore.persistentCacheIndexManager; // null with a memory cache
  await indexes?.enableIndexAutoCreation();
}

// ../../docs/guides/performance.md:176
Future<void> performanceGuideLine176() async {
  await firestore.persistentCacheIndexManager?.enableIndexAutoCreation();

  // Or, for an app that lives offline: settings for FirebaseFirestore.instanceFor
  // that turn automatic creation on from every start and fill faster,
  final Settings settings = Settings(
    cacheSettings: PersistentCacheSettings(
      indexAutoCreation: true,
      indexBackfill: IndexBackfillSettings(
        documentsPerRun: 200,
        interval: const Duration(seconds: 10),
      ),
    ),
  );
  // and a fill now, during a loading screen (at most 20,000 documents).
  await firestore.persistentCacheIndexManager?.fillIndexes(maxDocuments: 20000);

  // An index for a query that automatic creation skips (deprecated API).
  // ignore: deprecated_member_use
  await firestore.setIndexConfigurationFromJSON('''
  {
    "indexes": [
      {
        "collectionGroup": "orders",
        "queryScope": "COLLECTION",
        "fields": [{"fieldPath": "total", "order": "DESCENDING"}]
      }
    ],
    "fieldOverrides": []
  }''');
}

// ../../docs/guides/performance.md:246
Future<void> performanceGuideLine246() async {
  final Settings settings = Settings(
    cacheSettings: PersistentCacheSettings(sizeBytes: 200 * 1024 * 1024),
  );
}

// ../../docs/guides/performance.md:298
Future<void> performanceGuideLine298() async {
  final Stream<QuerySnapshot<Map<String, Object?>>> local = users
      .where('online', isEqualTo: true)
      .snapshots(source: ListenSource.cache);
}

// ../../docs/guides/performance.md:313
Future<void> performanceGuideLine313() async {
  final QuerySnapshot<Map<String, Object?>> page1 =
      await users.orderBy('name').limit(25).get();
  final QuerySnapshot<Map<String, Object?>> page2 = await users
      .orderBy('name')
      .startAfterDocument(page1.docs.last)
      .limit(25)
      .get();
}

// ../../docs/guides/performance.md:332
Future<void> performanceGuideLine332() async {
  final AggregateQuerySnapshot snapshot = await users.where('active', isEqualTo: true).count().get();
  print(snapshot.count);
}

// ../../docs/guides/performance.md:373
Future<void> performanceGuideLine373() async {
  final LoadBundleTaskSnapshot progress = await firestore.loadBundle(bundleBytes).future;
  final Query<Map<String, Object?>>? latest = await firestore.namedQuery('latest-stories');
  final QuerySnapshot<Map<String, Object?>> firstScreen = await latest!.get(const GetOptions(source: Source.cache));
}

// ../../docs/guides/performance.md:392
Future<void> performanceGuideLine392() async {
  final DocumentSnapshot<Map<String, Object?>> cached = await users.doc('ada').get(const GetOptions(source: Source.cache));
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

// ../../docs/guides/pipelines.md:74
Future<void> pipelinesGuideLine74() async {
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

// ../../docs/guides/pipelines.md:131
Future<void> pipelinesGuideLine131() async {
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

// ../../docs/guides/pipelines.md:171
Future<void> pipelinesGuideLine171() async {
  final PipelineSnapshot written = await firestore
      .pipeline()
      .collection('books')
      .where(field('published').lessThan(1900))
      .update(transformedFields: [constant(true).as('classic')])
      .execute(atomic: true); // in one transaction, committed at the end
  print(written.results.single.get('documents_modified'));
}

// ../../docs/guides/pipelines.md:192
Future<void> pipelinesGuideLine192() async {
  final PipelineSnapshot inSnapshot = await firestore.runTransaction(
    (Transaction transaction) => transaction.execute(
      firestore.pipeline().collection('books').where(field('genre').equal('Fantasy')),
    ),
    readOnly: true,
  );
}

// ../../docs/guides/pipelines.md:208
Future<void> pipelinesGuideLine208() async {
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
  final firestore = FirebaseFirestore.instanceFor(app: app);
  final users = firestore.collection('users');
  await users.doc('ada').set({'name': 'Ada', 'age': 36});
  final adults = await users.where('age', isGreaterThanOrEqualTo: 18).get();
}

// ../../docs/guides/queries_and_data.md:57
Future<void> queriesAndDataGuideLine57() async {
  final count = await users.count().get();                 // AggregateQuerySnapshot
  final agg = await users.aggregate([
    AggregateField.sum('age'),
    AggregateField.average('age'),
  ]).get();
  final either = await users
      .where(Filter.or([
        Filter('city', isEqualTo: 'Paris'),
        Filter('city', isEqualTo: 'Rome'),
      ]))
      .get();
  final last3 = await users.orderBy('age').limitToLast(3).get();
  final near = await users
      .findNearest(vectorField: 'embedding', queryVector: VectorValue([0.1, 0.2, 0.3]), limit: 5,
          distanceMeasure: DistanceMeasure.cosine)
      .get();
}

// ../../docs/guides/queries_and_data.md:80
Future<void> queriesAndDataGuideLine80() async {
  final converter = FirestoreDataConverter<City>.from(
    fromFirestore: (snapshot, options) => City.fromMap(snapshot.data()!),
    toFirestore: (city, options) => city.toMap(),
  );

  final cities = firestore.collection('cities').withConverter<City>(fromFirestore: converter.fromFirestore, toFirestore: converter.toFirestore);
  await cities.doc('sf').set(const City('San Francisco', 870000));   // CollectionReference<City>
  final City sf = (await cities.doc('sf').get()).data()!;               // DocumentSnapshot<City>
  final big = await cities.where('population', isGreaterThan: 500000).get();
  final names = [for (final c in big.docs) c.data().name];              // QueryDocumentSnapshot<City>
  final raw = cities.withoutConverter();                              // back to Map<String, Object?>
}

// ../../docs/guides/queries_and_data.md:114
Future<void> queriesAndDataGuideLine114() async {
  final settings = Settings(
      cacheSettings: PersistentCacheSettings(sizeBytes: 100 * 1024 * 1024));
  final task = firestore.loadBundle(bundleBytes);          // LoadBundleTask
  final json = (await query.get()).toJson();               // e.g. sent from a server to a client
  final snapshot = QuerySnapshot.fromJson(firestore, json);
  firestore.querySnapshotsFromJson(json).listen((_) {});   // resumes listening from that snapshot
  await firestore.waitForPendingWrites();
  firestore.snapshotsInSync().listen((_) {});
  await firestore.terminate();
}

// ../../docs/guides/server.md:19
Future<void> serverGuideLine19() async {
  Future<void> main() async {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: '', // an empty key is not sent
        appId: '1:1234567890:dart:server',
        projectId: 'my-project',
      ),
    );
    // Before the instance is created: the instance reads the provider of the app once.
    app.authProvider = applicationDefaultCredentials();
    // No openDatabase: the cache is in memory.
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(app: app);

    final StreamSubscription<QuerySnapshot<Map<String, Object?>>> listener = firestore
        .collection('jobs')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((QuerySnapshot<Map<String, Object?>> snapshot) {
          print('${snapshot.length} pending jobs');
        });

    // Wait for Ctrl-C or SIGTERM (SIGTERM cannot be watched on Windows).
    final Completer<void> stop = Completer<void>();
    final List<StreamSubscription<ProcessSignal>> signals = <StreamSubscription<ProcessSignal>>[
      ProcessSignal.sigint.watch().listen((_) => stop.isCompleted ? null : stop.complete()),
      if (!Platform.isWindows)
        ProcessSignal.sigterm.watch().listen((_) => stop.isCompleted ? null : stop.complete()),
    ];
    await stop.future;
    for (final StreamSubscription<ProcessSignal> signal in signals) {
      await signal.cancel();
    }

    await listener.cancel();
    await firestore.waitForPendingWrites().timeout(const Duration(seconds: 5));
    await firestore.terminate(); // without it the process does not exit
  }
}

// ../../docs/guides/server.md:110
Future<void> serverGuideLine110() async {
  final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST']; // host:port
  final FirebaseApp serverApp = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: '',
      appId: '1:1234567890:dart:server',
      projectId: emulator == null ? 'my-project' : 'demo-my-project',
    ),
    name: 'server',
  );
  Settings settings = Settings();
  if (emulator != null) {
    final int colon = emulator.lastIndexOf(':');
    settings = settings.withEmulator(
      emulator.substring(0, colon),
      int.parse(emulator.substring(colon + 1)),
    );
  } else {
    serverApp.authProvider = applicationDefaultCredentials();
  }
  final FirebaseFirestore db = FirebaseFirestore.instanceFor(app: serverApp, settings: settings);
}

// ../../docs/guides/server.md:311
Future<void> serverGuideLine311() async {
  // Claim a job once, whichever process gets there first.
  final DocumentReference<Map<String, Object?>> job = firestore.doc('jobs/job-1');
  final bool claimed = await firestore.runTransaction<bool>((Transaction transaction) async {
    final DocumentSnapshot<Object?> snapshot = await transaction.get(job);
    if (!snapshot.exists || snapshot['status'] != 'pending') {
      return false;
    }
    transaction.update(job, <String, Object?>{'status': 'running', 'worker': 'worker-a'});
    return true;
  });
  print(claimed ? 'mine' : 'taken');
}

// ../../docs/guides/transactions_and_lifecycle.md:55
Future<void> transactionsAndLifecycleGuideLine55() async {
  final total = await firestore.runTransaction((transaction) async {
    final account = await transaction.get(firestore.doc('accounts/a'));
    final orders = await transaction.getQuery(
        firestore.collection('orders').where('account', isEqualTo: 'a'));
    final count = await transaction.getAggregate(firestore.collection('orders').count());
    return (account.data(), orders.docs.length, count.count);
  }, readOnly: true);
}

// ../../docs/guides/troubleshooting.md:59
Future<void> troubleshootingGuideLine59() async {
  FirebaseFirestore.setLogLevel(LogLevel.debug);
}

// ../../docs/guides/troubleshooting.md:288
Future<void> troubleshootingGuideLine288() async {
  final Settings settings = Settings(
    webExperimentalForceLongPolling: true,
    webExperimentalLongPollingOptions: const WebExperimentalLongPollingOptions(timeoutDuration: Duration(seconds: 25)),
  );
}

// ../../docs/guides/web.md:24
Future<void> webGuideLine24() async {
  void main() {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:web:example',
        projectId: 'demo-example',
      ),
    );
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings().withEmulator('127.0.0.1', 8080),
    );

    final web.Element list = web.document.querySelector('#notes')!;
    firestore.collection('notes').snapshots().listen((
      QuerySnapshot<Map<String, Object?>> snapshot,
    ) {
      list.textContent = '';
      for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot.docs) {
        list.append(web.document.createElement('li')..textContent = '${doc.data()['text']}');
      }
    });
  }
}

// ../../docs/guides/web.md:173
Future<void> webGuideLine173() async {
  final Settings settings = Settings(
    webExperimentalForceLongPolling: true,
    webExperimentalLongPollingOptions: const WebExperimentalLongPollingOptions(timeoutDuration: Duration(seconds: 25)),
  );
}

// ../../docs/guides/web.md:224
Future<void> webGuideLine224() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(opfsWorker: Uri.parse('sqlite_opfs_worker.js')),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
}

// ../../docs/guides/web.md:281
Future<void> webGuideLine281() async {
  final FirebaseFirestore firestore = await openWithMemoryFallback(
    app: app,
    openDatabase: sqliteOpener(),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
  // Null with a memory cache: this tab did not get the persistent one.
  final bool persistent = firestore.persistentCacheIndexManager != null;
}

// ../../docs/guides/web.md:306
Future<void> webGuideLine306() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(),
    settings: Settings(cacheSettings: PersistentCacheSettings()),
  );
  // At every start, before the first write.
  try {
    final JsSdkCacheImportResult result = await importJsSdkCache(firestore);
    print('${result.status.name}: ${result.batches} pending writes of '
        '${result.users} users, ${result.documents} documents');
  } on JsSdkCacheImportException catch (e) {
    // Nothing was imported; the next start tries again.
    print('Not imported (${e.reason.name}): ${e.message}');
  }
}

// ../../docs/guides/web.md:431
Future<void> webGuideLine431() async {
  // One client of the page: `client` names its app ('client-left', 'client-right').
  Future<FirebaseFirestore> startClient(String client, String email) async {
    final FirebaseApp clientApp = FirebaseApp.withOptions(app.options, name: client);
    final FirebaseUserAuth auth = await FirebaseUserAuth.forApp(clientApp);
    await auth.signInWithEmailAndPassword(email: email, password: password);
    return FirebaseFirestore.instanceFor(app: clientApp);
  }
}

// ../../docs/guides/web.md:459
Future<void> webGuideLine459() async {
  final Settings settings = Settings().withEmulator('127.0.0.1', 8080);
}

// ../../docs/guides/web.md:541
Future<void> webGuideLine541() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: indexedDbCacheSettings(
        sizeBytes: 40 * 1024 * 1024,
        indexAutoCreation: true,
      ),
    ),
  );
}

// ../../docs/guides/web.md:636
Future<void> webGuideLine636() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(cacheSettings: indexedDbCacheSettings(multiTab: true)),
  );
}
