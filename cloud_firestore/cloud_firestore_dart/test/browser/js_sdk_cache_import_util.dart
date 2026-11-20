// Helpers of the browser tests of importJsSdkCache (web_js_sdk_cache_import_*_test.dart): clients on every kind of
// cache, the fixtures of test/browser/js_sdk_cache_fixtures (written by the real JS SDK, see
// tool/bench/web_idb/js_import/fixtures.sh) loaded as the IndexedDB database of a JS app, and the emulator's REST API
// to seed a project and read what the backend holds.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/indexeddb_cache.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/js_sdk_import/js_sdk_database_platform.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../../example/cache_store/indexeddb/indexeddb_cache_store.dart';
import 'emulator_port.dart';
import 'js_sdk_cache_fixture.dart';

typedef Json = Map<String, Object?>;

final Uri sqlite3Wasm = Uri.base.resolve('sqlite3.wasm');
final Uri opfsWorker = Uri.base.resolve('opfs/sqlite_opfs_worker.js');

/// The caches an import can go to.
enum Destination {
  /// SQLite in IndexedDB (the default web opener).
  sqliteIndexedDb,

  /// SQLite in the origin private file system, in a worker.
  sqliteOpfs,

  /// The memory cache (pending writes only with `allowMemoryCache`).
  memory,

  /// The key-value cache over the IndexedDB store of example/cache_store/indexeddb.
  keyValue,

  /// The IndexedDB engine (`indexedDbCacheSettings`), on its own database (not the JS one).
  indexedDbEngine,
}

Future<bool> fetchable(Uri uri) async {
  try {
    return (await web.window.fetch(uri.toString().toJS).toDart).ok;
  } catch (_) {
    return false;
  }
}

/// Why [destination] can not be tested in this run, or null.
Future<String?> unavailable(Destination destination) async {
  if ((destination == Destination.sqliteIndexedDb ||
          destination == Destination.sqliteOpfs) &&
      !await fetchable(sqlite3Wasm)) {
    return 'test/browser/sqlite3.wasm is missing: run tool/build_web_test_assets.sh';
  }
  if (destination == Destination.sqliteOpfs && !await fetchable(opfsWorker)) {
    return 'test/browser/opfs/sqlite_opfs_worker.js is missing: run tool/build_web_test_assets.sh';
  }
  return null;
}

int _names = 0;

/// A name no other test of the run uses.
String uniqueName(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

/// A client and its app. [close] terminates it (a page that goes away); the test's tear-down closes it if the test
/// did not.
class ImportClient {
  ImportClient._(this.app, this.firestore);

  final FirebaseApp app;
  final FirebaseFirestore firestore;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await firestore.terminate();
    await app.delete();
  }
}

/// A client of [projectId] on a cache of [destination] named after [appName] (a later client with the same name and
/// destination opens the same cache), signed in as [uid] through the emulator's mock token (signed out when null),
/// against the emulator on [host] (by default the private one).
Future<ImportClient> openClient({
  required String projectId,
  required Destination destination,
  required String appName,
  String? uid,
  String? host,
}) async {
  await loadEmulatorPort();
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:browser',
      projectId: projectId,
    ),
    name: appName,
  );
  final (String emulator, int port) = host == null
      ? (emulatorHost, emulatorPort)
      : (
          host.substring(0, host.lastIndexOf(':')),
          int.parse(host.substring(host.lastIndexOf(':') + 1)),
        );
  final Settings settings =
      Settings(
        cacheSettings: switch (destination) {
          Destination.sqliteIndexedDb || Destination.sqliteOpfs => null,
          Destination.memory => const MemoryCacheSettings(),
          Destination.keyValue => keyValueCacheSettings(
            store: IndexedDbCacheStore('kv-$appName'),
          ),
          Destination.indexedDbEngine => indexedDbCacheSettings(),
        },
      ).withEmulator(
        emulator,
        port,
        mockUserToken: uid == null ? null : <String, Object?>{'sub': uid},
      );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: switch (destination) {
      Destination.sqliteIndexedDb => sqliteWebOpener(sqlite3Wasm: sqlite3Wasm),
      Destination.sqliteOpfs => sqliteWebOpener(
        sqlite3Wasm: sqlite3Wasm,
        opfsWorker: opfsWorker,
      ),
      _ => null,
    },
    settings: settings,
  );
  await firestore.initialized;
  final ImportClient client = ImportClient._(app, firestore);
  addTearDown(client.close);
  return client;
}

// ---- Fixtures ----

final Map<String, Future<Json>> _fixtures = <String, Future<Json>>{};

/// The fixture `js_sdk_cache_fixtures/<name>.json` (or js_sdk_cache_fixture.json for `legacy`), as decoded JSON. Each
/// call returns a new copy that the caller may change.
Future<Json> fixture(String name) async {
  final Json json = await (_fixtures[name] ??= () async {
    final Uri uri = name == 'legacy'
        ? jsSdkCacheFixture
        : Uri.base.resolve('js_sdk_cache_fixtures/$name.json');
    final web.Response response = await web.window
        .fetch(uri.toString().toJS)
        .toDart;
    if (!response.ok) {
      throw StateError('Fetching $uri failed: HTTP ${response.status}');
    }
    return (jsonDecode((await response.text().toDart).toDart)
            as Map<Object?, Object?>)
        .cast<String, Object?>();
  }());
  return (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>)
      .cast<String, Object?>();
}

/// The store [name] of [dump], or null.
Json? store(Json dump, String name) {
  for (final Object? s in dump['stores']! as List<Object?>) {
    final Json store = (s! as Map<Object?, Object?>).cast<String, Object?>();
    if (store['name'] == name) {
      return store;
    }
  }
  return null;
}

/// The values of the records of the store [name] of [dump].
List<Json> records(Json dump, String name) => <Json>[
  for (final Object? r
      in (store(dump, name)?['records'] as List<Object?>?) ?? const <Object?>[])
    ((r! as Map<Object?, Object?>)['value']! as Map<Object?, Object?>)
        .cast<String, Object?>(),
];

/// Loads [dump] as the database of a new JS app of [projectId], and returns the name of that app.
Future<String> loadAsJsApp(Json dump, {required String projectId}) async {
  final String jsApp = uniqueName('js-app');
  await loadJsSdkCacheDump(
    dump,
    databaseName: jsDatabaseName(jsApp, projectId),
  );
  addTearDown(() => deleteJsDatabase(jsDatabaseName(jsApp, projectId)));
  return jsApp;
}

String jsDatabaseName(String jsApp, String projectId) =>
    'firestore/$jsApp/$projectId/main';

Future<void> deleteJsDatabase(String name) async {
  final Completer<void> done = Completer<void>();
  final web.IDBOpenDBRequest request = web.window.indexedDB.deleteDatabase(
    name,
  );
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.complete()).toJS;
  request.onblocked = ((web.Event _) {}).toJS;
  await done.future;
}

/// The number of rows of each store of the JS database [name] (null when there is no such database), and its
/// version as `version`.
Future<Map<String, int>?> jsStoreCounts(String name) async {
  final JsSdkDatabase? db = await openJsSdkDatabase(name);
  if (db == null) {
    return null;
  }
  try {
    return <String, int>{
      'version': db.version,
      for (final String s in <String>[
        'mutations',
        'documentMutations',
        'documentOverlays',
        'remoteDocumentsV14',
      ])
        if (db.hasStore(s)) s: (await db.readAll(s)).length,
    };
  } finally {
    db.close();
  }
}

/// Sets the LocalStorage key by which the JS SDK marks the client [clientId] of [databaseName] as gone.
void markJsClientZombied(String databaseName, String clientId) {
  final String prefix = databaseName.substring(
    0,
    databaseName.length - 'main'.length,
  );
  web.window.localStorage.setItem(
    'firestore_zombie_${prefix}_$clientId',
    'true',
  );
  addTearDown(
    () => web.window.localStorage.removeItem(
      'firestore_zombie_${prefix}_$clientId',
    ),
  );
}

// ---- The emulator's REST API ----

Future<Object?> _rest(
  String method,
  String path, {
  Object? body,
  String? host,
}) async {
  await loadEmulatorPort();
  final String base = 'http://${host ?? '$emulatorHost:$emulatorPort'}';
  final web.Response response = await web.window
      .fetch(
        '$base$path'.toJS,
        web.RequestInit(
          method: method,
          headers:
              <String, String>{
                    'Authorization': 'Bearer owner',
                    'Content-Type': 'application/json',
                  }.jsify()!
                  as web.HeadersInit,
          body: body == null ? null : jsonEncode(body).toJS,
        ),
      )
      .toDart;
  final String text = (await response.text().toDart).toDart;
  if (response.status == 404) {
    return null;
  }
  if (!response.ok) {
    throw StateError('$method $path: HTTP ${response.status} $text');
  }
  return text.isEmpty ? null : jsonDecode(text);
}

String _documents(String projectId) =>
    '/v1/projects/$projectId/databases/(default)/documents';

String _encodePath(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');

/// Deletes every document of [projectId] in the emulator.
Future<void> clearProject(String projectId, {String? host}) => _rest(
  'DELETE',
  '/emulator/v1/projects/$projectId/databases/(default)/documents',
  host: host,
);

/// Writes [seed] (path to proto3 JSON fields) into [projectId].
Future<void> seedProject(String projectId, Json seed, {String? host}) async {
  for (final MapEntry<String, Object?> entry in seed.entries) {
    await _rest(
      'PATCH',
      '${_documents(projectId)}/${_encodePath(entry.key)}',
      body: <String, Object?>{'fields': entry.value},
      host: host,
    );
  }
}

/// The proto3 JSON fields of the documents [paths] of [projectId] (null for a missing one).
Future<Json> readBackend(
  String projectId,
  Iterable<String> paths, {
  String? host,
}) async => <String, Object?>{
  for (final String path in paths)
    path: switch (await _rest(
      'GET',
      '${_documents(projectId)}/${_encodePath(path)}',
      host: host,
    )) {
      null => null,
      final Object document =>
        (document as Map<Object?, Object?>)['fields'] ?? <String, Object?>{},
    },
};

/// [fields] with every server timestamp (a time from 2025 to 2099) replaced by `<server time>` and the references
/// to [fromProject] made references to [toProject].
Object? normalize(
  Object? fields, {
  required String fromProject,
  required String toProject,
}) {
  if (fields is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in fields.entries)
        entry.key! as String: switch (entry.key) {
          'timestampValue'
              when entry.value is String &&
                  (entry.value! as String).compareTo('2025') >= 0 &&
                  (entry.value! as String).compareTo('2100') < 0 =>
            '<server time>',
          'referenceValue' when entry.value is String =>
            (entry.value! as String).replaceFirst(
              'projects/$fromProject/',
              'projects/$toProject/',
            ),
          _ => normalize(
            entry.value,
            fromProject: fromProject,
            toProject: toProject,
          ),
        },
    };
  } else if (fields is List) {
    return <Object?>[
      for (final Object? e in fields)
        normalize(e, fromProject: fromProject, toProject: toProject),
    ];
  }
  return fields;
}

/// Expects the documents of [projectId] to be [expected] (from a fixture: what the backend held after the JS SDK sent
/// the same writes to [referenceProject]), document by document.
Future<void> expectBackend(
  String projectId,
  Json expected, {
  required String referenceProject,
  String? host,
}) async {
  final Json actual = await readBackend(projectId, expected.keys, host: host);
  for (final String path in expected.keys) {
    expect(
      normalize(actual[path], fromProject: projectId, toProject: projectId),
      normalize(
        expected[path],
        fromProject: referenceProject,
        toProject: projectId,
      ),
      reason: path,
    );
  }
}

Matcher refusal(JsSdkCacheImportRefusal reason) => throwsA(
  isA<JsSdkCacheImportException>().having(
    (JsSdkCacheImportException e) => e.reason,
    'reason',
    reason,
  ),
);
