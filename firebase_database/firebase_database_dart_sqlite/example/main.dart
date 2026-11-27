// The SQLite cache: a value written in one session is read from disk in the next, offline.
//
// Shows: sqlitePersistence, keepSynced, goOffline, a get() answered from the cache after a restart.
// Platform: Dart VM (also Flutter on Android, iOS, macOS, Linux and Windows).
// Run: FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9100 dart run example/main.dart
// Backend: Realtime Database emulator, project demo-example. The cache is a temporary directory,
// removed at the end.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';

Future<void> main() async {
  final String? host = FirebaseDatabase.emulatorHostFromEnvironment;
  if (host == null || host.isEmpty) {
    stderr.writeln(
      'Set FIREBASE_DATABASE_EMULATOR_HOST=host:port (the local emulator).',
    );
    exit(64);
  }

  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-example',
    ),
  );
  // Where the cache file lives. In an app, use its support directory.
  final Directory cacheDir = Directory.systemTemp.createTempSync(
    'rtdb_sqlite_example',
  );
  final String path = '${cacheDir.path}/firebase_database';
  final String key = 'example-sqlite-${DateTime.now().microsecondsSinceEpoch}';

  try {
    // Session 1: online. Only data under a listener or keepSynced is cached.
    final FirebaseDatabase first = FirebaseDatabase(
      app,
      emulatorHost: host,
      persistence: sqlitePersistence(path),
    );
    final DatabaseReference ref = first.ref(key);
    await ref.keepSynced(true);
    await ref.set('hello from the first session');
    print('session 1 wrote: hello from the first session');
    print('session 1 persistence on disk: ${first.persistenceEnabled}');
    await first.close();

    // Session 2: a new instance on the same cache file, offline from the start. The server is
    // not reachable for it, so the value can only come from the SQLite file.
    final FirebaseDatabase second = FirebaseDatabase(
      app,
      emulatorHost: host,
      persistence: sqlitePersistence(path),
    );
    second.goOffline();
    final DataSnapshot snapshot = await second.ref(key).get();
    print('session 2 read offline: ${snapshot.value}');
    await second.close();

    // Remove the test data from the server.
    final FirebaseDatabase cleanup = FirebaseDatabase(app, emulatorHost: host);
    await cleanup.ref(key).remove();
    await cleanup.close();
  } finally {
    cacheDir.deleteSync(recursive: true);
  }
}
