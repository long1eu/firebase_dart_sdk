// Setup shared by the examples in this directory: a FirebaseApp for a demo
// project and settings that point at the local Firestore emulator.
//
// Start an emulator with
//
//     firebase emulators:start --only firestore --project demo-example
//
// and run any example with
//
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 dart run example/<name>.dart

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';

/// A `demo-` project id keeps the emulator from talking to a real project.
const String projectId = 'demo-example';

/// A new [FirebaseApp] for the demo project. The emulator accepts any API key
/// and application id.
FirebaseApp exampleApp([String name = FirebaseApp.defaultAppName]) {
  return FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:example',
      projectId: projectId,
    ),
    name: name,
  );
}

/// Settings for the emulator named by `FIRESTORE_EMULATOR_HOST` (default
/// `127.0.0.1:8080`). The settings have to be passed when the instance is
/// created; they cannot be changed afterwards.
FirestoreSettings emulatorSettings({
  LocalCacheSettings cacheSettings = const MemoryCacheSettings(),
  Object? mockUserToken,
}) {
  final String emulator =
      Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
  final int colon = emulator.lastIndexOf(':');
  final String host = emulator.substring(0, colon);
  final int port = int.parse(emulator.substring(colon + 1));
  return FirestoreSettings(
    cacheSettings: cacheSettings,
  ).withEmulator(host, port, mockUserToken: mockUserToken);
}

/// A [Firestore] instance with an in-memory cache, connected to the emulator.
Future<Firestore> connect([String appName = FirebaseApp.defaultAppName]) {
  return Firestore.instanceFor(
    app: exampleApp(appName),
    settings: emulatorSettings(),
  );
}

final String _runId = DateTime.now().microsecondsSinceEpoch.toString();

/// The path of a collection that is new on every run, so that an example
/// gives the same output however often it is run against one emulator.
String scratch(String name) => 'examples/$_runId/$name';
