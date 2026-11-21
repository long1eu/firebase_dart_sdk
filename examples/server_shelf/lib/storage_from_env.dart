// Creates the FirebaseStorage instance from environment variables, so that
// the same program runs against the emulator and against a real project, and
// no project id or key is written into a file.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

/// Thrown when the environment does not say which backend to use.
class StorageConfigurationError implements Exception {
  StorageConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Storage client that [environment] describes:
///
/// - `FIREBASE_STORAGE_EMULATOR_HOST` (`host:port`): the emulator. The project
///   is `FIREBASE_PROJECT_ID` or `demo-test`; the bucket is `STORAGE_BUCKET`
///   or `<project>.appspot.com`.
/// - Otherwise a real project: `FIREBASE_PROJECT_ID` is required, and the
///   requests carry Application Default Credentials. They bypass the Storage
///   security rules; access is decided by IAM.
FirebaseStorage storageFromEnvironment({
  Map<String, String>? environment,
  String appName = defaultFirebaseAppName,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? emulator = _nonEmpty(env['FIREBASE_STORAGE_EMULATOR_HOST']);
  final String? projectId =
      _nonEmpty(env['FIREBASE_PROJECT_ID']) ??
      (emulator == null ? null : 'demo-test');
  if (projectId == null) {
    throw StorageConfigurationError(
      'Set FIREBASE_STORAGE_EMULATOR_HOST (host:port of a Storage emulator) '
      'or FIREBASE_PROJECT_ID (a real project, with Application Default '
      'Credentials).',
    );
  }
  final String bucket =
      _nonEmpty(env['STORAGE_BUCKET']) ?? '$projectId.appspot.com';
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: env['FIREBASE_API_KEY'] ?? '',
      appId: '1:1234567890:dart:example',
      projectId: projectId,
      storageBucket: bucket,
    ),
    name: appName,
  );
  if (emulator == null) {
    app.authProvider = applicationDefaultCredentials();
  }
  return FirebaseStorage(app, emulatorHost: emulator);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
