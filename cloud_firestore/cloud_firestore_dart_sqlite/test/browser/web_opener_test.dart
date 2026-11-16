// The opener in a browser, through the public API, against a private
// Firestore emulator. It needs, next to this file (see test/browser/README.md):
//
//   sqlite3.wasm             the build of the sqlite3 version in pubspec.lock
//   sqlite_opfs_worker.js    dart run cloud_firestore_dart_sqlite:setup_web test/browser
//   emulator_port.txt        the port of the emulator (default 8090)
//
//   dart test -p chrome -c dart2js test/browser/web_opener_test.dart
//
// Without sqlite3.wasm the tests skip themselves; without the worker the OPFS
// test does.

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

typedef Json = Map<String, Object?>;

final Uri opfsWorker = Uri.base.resolve('sqlite_opfs_worker.js');

int _names = 0;
String newName(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

Future<String?> missing(String file) async {
  try {
    final web.Response response = await web.window
        .fetch(Uri.base.resolve(file).toString().toJS)
        .toDart;
    return response.ok ? null : 'test/browser/$file is missing';
  } catch (e) {
    return 'test/browser/$file cannot be fetched: $e';
  }
}

int emulatorPort = 8090;

FirebaseApp newApp(String name) => FirebaseApp.withOptions(
  const FirebaseOptions(
    apiKey: 'demo-key',
    applicationId: '1:1234567890:dart:browser',
    projectId: 'demo-test',
  ),
  name: name,
);

FirestoreSettings settings() => FirestoreSettings(
  cacheSettings: PersistentCacheSettings(),
).withEmulator('127.0.0.1', emulatorPort);

Firestore client(String appName, OpenDatabase openDatabase) =>
    Firestore.instanceFor(
      app: newApp(appName),
      openDatabase: openDatabase,
      settings: settings(),
    );

Future<void> shutDown(Firestore firestore) async {
  await firestore.terminate();
  firestore.app!.delete();
}

/// Writes one document online and one offline, reopens the cache offline and
/// reads both back.
Future<void> writeReopenRead(OpenDatabase Function() opener) async {
  final String app = newName('sqlite-web');
  final String collection = newName('sqlite_web');

  Firestore firestore = client(app, opener());
  await firestore.collection(collection).doc('synced').set(<String, Object?>{
    'n': 1,
  });
  await firestore.disableNetwork();
  unawaited(
    firestore.collection(collection).doc('pending').set(<String, Object?>{
      'n': 2,
    }),
  );
  expect(
    (await firestore.collection(collection).doc('pending').get(Source.cache))
        .data,
    <String, Object?>{'n': 2},
  );
  await shutDown(firestore);

  firestore = client(app, opener());
  await firestore.disableNetwork();
  final QuerySnapshot<Json> cached = await firestore
      .collection(collection)
      .orderBy('n')
      .get(Source.cache);
  expect(cached.metadata.isFromCache, isTrue);
  expect(
    cached.docs.map((QueryDocumentSnapshot<Json> d) => d.data).toList(),
    <Json>[
      <String, Object?>{'n': 1},
      <String, Object?>{'n': 2},
    ],
  );
  await firestore.enableNetwork();
  await firestore.waitForPendingWrites();
  await firestore.terminate();
  await firestore.clearPersistence();
  firestore.app!.delete();
}

void main() {
  String? skip;
  String? skipOpfs;

  setUpAll(() async {
    skip = await missing('sqlite3.wasm');
    skipOpfs = skip ?? await missing('sqlite_opfs_worker.js');
    try {
      final web.Response response = await web.window
          .fetch(Uri.base.resolve('emulator_port.txt').toString().toJS)
          .toDart;
      if (response.ok) {
        emulatorPort =
            int.tryParse((await response.text().toDart).toDart.trim()) ??
            emulatorPort;
      }
    } catch (_) {
      // The default port.
    }
  });

  test('IndexedDB: writes are read back from storage after a reopen', () async {
    if (skip != null) {
      markTestSkipped(skip!);
      return;
    }
    await writeReopenRead(() => sqliteOpener());
    // The default storage is IndexedDB.
    final Database db = await sqliteOpener()(newName('probe'), version: 1);
    expect(db, isA<SqliteWebDatabase>());
    db.close();
  });

  test('OPFS: writes are read back from storage after a reopen', () async {
    if (skipOpfs != null) {
      markTestSkipped(skipOpfs!);
      return;
    }
    final String name = newName('probe');
    final Database db = await sqliteOpener(opfsWorker: opfsWorker)(
      name,
      version: 1,
    );
    if (db is! SqliteOpfsDatabase) {
      db.close();
      markTestSkipped('this browser has no synchronous OPFS access');
      return;
    }
    await db.clearStorage();
    await writeReopenRead(() => sqliteOpener(opfsWorker: opfsWorker));
  });

  test('a second client on the same cache gets a memory cache from '
      'openWithMemoryFallback', () async {
    if (skip != null) {
      markTestSkipped(skip!);
      return;
    }
    final String app = newName('sqlite-tab');
    final Firestore first = await openWithMemoryFallback(
      app: newApp(app),
      openDatabase: sqliteOpener(),
      settings: settings(),
    );
    expect(first.persistentCacheIndexManager, isNotNull);

    // Another app of the same name in this page stands in for a second tab:
    // the cache name is derived from the app name.
    final FirebaseApp other = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        applicationId: '1:1234567890:dart:browser',
        projectId: 'demo-test',
      ),
      name: '$app-2',
    );
    final Firestore second = await openWithMemoryFallback(
      app: other,
      // The same storage name as the first one.
      openDatabase:
          (
            String name, {
            int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen,
          }) => sqliteOpener(lockTimeout: const Duration(milliseconds: 300))(
            name.replaceFirst('$app-2', app),
            version: version ?? 1,
            onConfigure: onConfigure ?? (_) async {},
            onCreate: onCreate ?? (_, _) async {},
            onUpgrade: onUpgrade ?? (_, _, _) async {},
            onDowngrade: onDowngrade ?? (_, _, _) async {},
            onOpen: onOpen ?? (_) async {},
          ),
      settings: settings(),
    );
    expect(second.persistentCacheIndexManager, isNull);

    await shutDown(second);
    await first.terminate();
    await first.clearPersistence();
    first.app!.delete();
  });
}
