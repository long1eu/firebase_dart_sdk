// Setup shared by the examples in this directory: a FirebaseApp for a demo
// project and a FirebaseStorage connected to the local Storage emulator.
//
// Start an emulator from the root of the repository (the buckets are
// demo-test.appspot.com with open rules and demo-test-auth.appspot.com with
// rules that need a signed-in user)
//
//     ./tool/start_storage_emulator.sh 9199
//
// and run any example with
//
//     FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 dart run example/<name>.dart

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

/// The bucket with open rules of the emulator script.
const String openBucket = 'demo-test.appspot.com';

/// The bucket whose rules need a signed-in user.
const String authBucket = 'demo-test-auth.appspot.com';

/// A new [FirebaseApp] for the `demo-test` project. The emulator accepts any
/// API key and application id.
FirebaseApp exampleApp([String name = defaultFirebaseAppName]) {
  return FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:example',
      projectId: 'demo-test',
      storageBucket: openBucket,
    ),
    name: name,
  );
}

/// A [FirebaseStorage] connected to the emulator named by
/// `FIREBASE_STORAGE_EMULATOR_HOST`. The program stops with a message when the
/// variable is not set, so that an example never reaches a real project.
FirebaseStorage emulatorStorage({
  String bucket = openBucket,
  String? mockUserToken,
  String appName = defaultFirebaseAppName,
}) {
  final String? host = FirebaseStorage.emulatorHostFromEnvironment;
  if (host == null || host.isEmpty) {
    stderr.writeln(
      'Set FIREBASE_STORAGE_EMULATOR_HOST=host:port (see example/common.dart).',
    );
    exit(64);
  }
  return FirebaseStorage(
    exampleApp(appName),
    bucket: bucket,
    emulatorHost: host,
    mockUserToken: mockUserToken,
  );
}

/// A folder name that no earlier run has used, so that examples do not see
/// each other's objects.
String freshFolder(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';
