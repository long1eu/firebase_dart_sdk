// Gets the installation id and an auth token of a Firebase app.
//
// There is no emulator for Firebase Installations; pass your own project:
//
//     dart run example/main.dart <api key> <app id> <project id>

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_installations_dart/io.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run example/main.dart <api key> <app id> <project id>',
    );
    exit(64);
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: arguments[0],
      appId: arguments[1],
      projectId: arguments[2],
    ),
  );
  // Keep the store in a directory of the user, so the installation survives
  // restarts. A temporary one is enough for this example.
  final Directory directory = Directory.systemTemp.createTempSync('fis');
  final FirebaseInstallations installations = FirebaseInstallations(
    app,
    store: FileKeyValueStore(directory.path),
  );
  try {
    final String id = await installations.getId();
    final String token = await installations.getToken();
    print('Installation id: $id; auth token of ${token.length} characters');
  } on FirebaseInstallationsException catch (e) {
    print('Failed: ${e.code}: ${e.message}');
  } finally {
    await installations.close();
    await installations.store.close();
  }
}
