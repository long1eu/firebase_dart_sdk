// A bundle for the first paint: a server process reads a query once and
// writes its result as a Firestore bundle; a client with an empty cache loads
// that bundle and shows the documents before it has talked to the backend.
// Then its listener takes over and the backend only sends what changed since
// the bundle was made.
//
// The bundle comes from `QuerySnapshot.toJson()`, whose `bundle` field holds
// the query (under the name in `bundleName`) and its documents. A server SDK
// (for example `firestore.bundle()` of the Node.js Admin SDK) builds the same
// format.
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/performance/bundle_first_paint.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';

import '../common.dart';
import '../sqlite_database.dart';

Future<void> main() async {
  final String path = scratch('articles');

  // --- Server: write some data, read the query, keep the bundle. ---
  final Firestore server = connect('server');
  final CollectionReference<Map<String, Object?>> articles = server.collection(
    path,
  );
  final WriteBatch batch = server.batch();
  for (int i = 0; i < 200; i++) {
    batch.set(articles.doc('a$i'), <String, Object?>{
      'title': 'Article $i',
      'published': i,
    });
  }
  await batch.commit();
  final Map<String, Object?> json =
      (await articles
              .orderBy('published', Direction.descending)
              .limit(20)
              .get())
          .toJson();
  final String bundle = json['bundle']! as String;
  final String bundleName = json['bundleName']! as String;
  print('bundle: ${utf8.encode(bundle).length} bytes, query "$bundleName"');

  // --- Client: a new app with an empty SQLite cache. ---
  final Directory directory = Directory.systemTemp.createTempSync(
    'firestore_example_',
  );
  final Firestore client = Firestore.instanceFor(
    app: exampleApp('client'),
    openDatabase: sqliteOpener(directory),
    settings: emulatorSettings(cacheSettings: PersistentCacheSettings()),
  );

  final Stopwatch firstPaint = Stopwatch()..start();
  // In an app the bundle would come from your server or a CDN, or be shipped
  // as an asset; loadBundleStream takes the body of an HTTP response.
  await client.loadBundle(utf8.encode(bundle)).future;
  final Query<Map<String, Object?>> latest = (await client.getNamedQuery(
    bundleName,
  ))!;
  final QuerySnapshot<Map<String, Object?>> cached = await latest.get(
    Source.cache,
  );
  firstPaint.stop();
  print(
    'first paint from the bundle: ${cached.length} articles in '
    '${firstPaint.elapsedMilliseconds} ms, first is '
    '"${cached.docs.first['title']}"',
  );

  // Meanwhile the server published one more article.
  await articles.doc('a200').set(<String, Object?>{
    'title': 'Article 200',
    'published': 200,
  });

  // The listener starts from the bundled documents and the read time of the
  // bundle, so the backend sends what changed since.
  final Stopwatch inSync = Stopwatch()..start();
  final Completer<void> synced = Completer<void>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      latest.snapshots.listen((QuerySnapshot<Map<String, Object?>> snapshot) {
        print(
          'listener: ${snapshot.length} articles, first is '
          '"${snapshot.docs.first['title']}", from cache: '
          '${snapshot.metadata.isFromCache} (${inSync.elapsedMilliseconds} ms)',
        );
        if (!snapshot.metadata.isFromCache && !synced.isCompleted) {
          synced.complete();
        }
      });
  await synced.future;
  await subscription.cancel();

  // Loading the same bundle again (the next start of the app) only reads its
  // metadata: the cache already has a bundle with this id that is as new, so
  // nothing is applied. The task still reports success with the totals of the
  // bundle.
  final Stopwatch again = Stopwatch()..start();
  await client.loadBundle(utf8.encode(bundle)).future;
  print('second load of the same bundle: ${again.elapsedMilliseconds} ms');

  await client.terminate();
  await server.terminate();
  directory.deleteSync(recursive: true);
}
