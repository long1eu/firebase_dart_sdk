// Compiled (not run) by web_compile_test.dart.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/web.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'AIzaSyDummyKeyForCompileOnly000000000000',
      appId: '1:123:web:abc',
      projectId: 'demo-test',
    ),
  );
  final IndexedDbKeyValueStore store = IndexedDbKeyValueStore();
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: store,
  );
  // ignore: avoid_print
  print(<Object?>[
    await installations.getId(),
    await installations.getIdAndToken(forceRefresh: true),
    installations.onIdChange.listen((String id) {}),
    MemoryKeyValueStore(),
  ]);
  await installations.delete();
  await installations.close();
  await store.close();
}
