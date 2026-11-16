// A FirebaseFirestore instance with its offline cache in SQLite, written, closed,
// opened again and read back without a network.
//
//     firebase emulators:start --only firestore --project demo-example
//     dart run example/main.dart
//
// FIRESTORE_EMULATOR_HOST picks another emulator (default 127.0.0.1:8080).
//
// The same `sqliteOpener` works in Flutter (pass a directory from
// path_provider) and in a browser (no directory; put sqlite3.wasm next to the
// page, see the README):
//
//     openDatabase: sqliteOpener(
//       directory: kIsWeb ? null : '${(await getApplicationSupportDirectory()).path}/firestore',
//     ),

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

Future<void> main() async {
  final Directory directory = Directory.systemTemp.createTempSync('cache_');

  FirebaseFirestore firestore = open(directory.path);
  final DocumentReference<Map<String, Object?>> doc = firestore.doc(
    'examples/sqlite',
  );
  await doc.set(<String, Object?>{'saved': DateTime.now().toIso8601String()});
  await firestore.terminate();
  await firestore.app.delete();

  // The same app name opens the same SQLite file.
  firestore = open(directory.path);
  await firestore.disableNetwork();
  final DocumentSnapshot<Map<String, Object?>> cached = await firestore
      .doc('examples/sqlite')
      .get(const GetOptions(source: Source.cache));
  print('from the cache on disk: ${cached.data()}');

  await firestore.terminate();
  await firestore.clearPersistence();
  await firestore.app.delete();
  directory.deleteSync(recursive: true);
}

FirebaseFirestore open(String directory) {
  final List<String> emulator =
      (Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080')
          .split(':');
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-example',
    ),
  );
  return FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory: directory),
    settings: Settings(
      cacheSettings: PersistentCacheSettings(),
    ).withEmulator(emulator[0], int.parse(emulator[1])),
  );
}
