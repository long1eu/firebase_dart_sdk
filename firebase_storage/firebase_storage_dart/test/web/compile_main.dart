// Compiled (not run) by web_compile_test.dart.

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

Future<void> main() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'key',
      appId: '1:123:dart:abc',
      projectId: 'demo-test',
      storageBucket: 'demo-test.appspot.com',
    ),
  );
  final FirebaseStorage storage = FirebaseStorage(
    app,
    emulatorHost: FirebaseStorage.emulatorHostFromEnvironment,
  );
  final Reference ref = storage.ref('a/b.txt');
  // ignore: avoid_print
  print(<Object?>[
    await ref.openRead(0, 10).length,
    await ref.getBytes(maxSize: 10),
    await ref.metadata(),
  ]);
  storage.close();
}
