// Creates the Firestore instance from environment variables, so that the same
// program runs against the emulator and against a real project, and no
// project id or key is written into a file.
//
// The three examples in examples/ carry the same copy of this file; copy it
// into your own program as it is.

import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/adc.dart';

/// Thrown when the environment does not say which backend to use.
class ConfigurationError implements Exception {
  ConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Firestore instance that [environment] describes:
///
/// - `FIRESTORE_EMULATOR_HOST` (`host:port`): the emulator. The project is
///   `FIREBASE_PROJECT_ID`, or `demo-example`; a `demo-` project never reaches
///   a real one.
/// - Otherwise a real project: `FIREBASE_PROJECT_ID` is required, and the
///   requests carry Application Default Credentials (the key file named by
///   `GOOGLE_APPLICATION_CREDENTIALS`, `gcloud auth application-default
///   login`, or the metadata server on Cloud Run and Compute Engine). Those
///   credentials bypass security rules; access is decided by IAM (the
///   `Cloud Datastore User` role).
/// - `FIRESTORE_DATABASE`: a named database, default `(default)`.
/// - `FIREBASE_API_KEY`: the Web API key of the project, optional. It is sent
///   with every request when set; an empty key is not sent.
///
/// The memory cache is used (no `openDatabase`): nothing is written to disk.
/// [appName] names the `FirebaseApp`; a program that needs one instance can
/// leave it out.
Firestore firestoreFromEnvironment({
  Map<String, String>? environment,
  String appName = FirebaseApp.defaultAppName,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? emulator = _nonEmpty(env['FIRESTORE_EMULATOR_HOST']);
  final String? projectId = _nonEmpty(env['FIREBASE_PROJECT_ID']);
  if (emulator == null && projectId == null) {
    throw ConfigurationError(
      'Set FIRESTORE_EMULATOR_HOST (host:port of a Firestore emulator) or '
      'FIREBASE_PROJECT_ID (a real project, with Application Default '
      'Credentials).',
    );
  }

  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: env['FIREBASE_API_KEY'] ?? '',
      // Any non-empty id works outside of Android and iOS.
      applicationId: '1:1234567890:dart:example',
      projectId: projectId ?? 'demo-example',
    ),
    name: appName,
  );

  FirestoreSettings settings = FirestoreSettings();
  if (emulator != null) {
    final int colon = emulator.lastIndexOf(':');
    final int? port = colon < 0
        ? null
        : int.tryParse(emulator.substring(colon + 1));
    if (port == null) {
      throw ConfigurationError(
        'FIRESTORE_EMULATOR_HOST must be host:port, not "$emulator".',
      );
    }
    settings = settings.withEmulator(emulator.substring(0, colon), port);
  } else {
    // Before the instance is created: it reads the provider of the app once.
    app.authProvider = applicationDefaultCredentials();
  }

  return Firestore.instanceFor(
    app: app,
    database: _nonEmpty(env['FIRESTORE_DATABASE']) ?? '(default)',
    settings: settings,
  );
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
