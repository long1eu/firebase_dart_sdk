// A Flutter program that uses the official firebase_storage API, with
// firebase_storage_dart doing the work underneath.
//
// On Linux the FirebaseStorageDart.use() call is optional: Flutter registers
// the package before main() runs. On the other platforms it replaces the
// official implementation. Run it against an emulator started with
// `firebase emulators:start --only storage` (project demo-test) and open
// rules.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_dart_platform/firebase_storage_dart_platform.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseStorageDart.use();
  await Firebase.initializeApp(
    // Use your own options (flutterfire configure) for a real project.
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:1:web:1',
      messagingSenderId: '1',
      projectId: 'demo-test',
      storageBucket: 'demo-test.appspot.com',
    ),
  );
  final FirebaseStorage storage = FirebaseStorage.instance;
  await storage.useStorageEmulator('127.0.0.1', 9199);

  final Reference ref = storage.ref('notes/hello.txt');
  final UploadTask upload = ref.putString('Hello from Dart');
  upload.snapshotEvents.listen((TaskSnapshot snapshot) {
    debugPrint('${snapshot.state}: ${snapshot.bytesTransferred} bytes');
  });
  await upload;

  final FullMetadata metadata = await ref.getMetadata();
  debugPrint('${metadata.fullPath}: ${metadata.size} bytes');
  debugPrint(await ref.getDownloadURL());
  final ListResult notes = await storage.ref('notes').listAll();
  debugPrint(notes.items.map((Reference item) => item.name).join(', '));
}
