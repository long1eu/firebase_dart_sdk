// Creates the FirebaseStorage instance from flags and environment variables,
// so that the same program runs against the emulators and against a real
// project, and no project id, key or password is written into a file.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_auth_providers_dart/firebase_auth_providers_dart.dart';
import 'package:firebase_storage_dart/firebase_storage_dart.dart';

/// Thrown when the flags and the environment do not say which backend to use.
class ConfigurationError implements Exception {
  ConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the global flags and the environment say. A flag wins over its
/// environment variable.
class StorageConfig {
  StorageConfig({
    this.projectId,
    this.bucket,
    this.emulatorHost,
    this.authEmulatorHost,
    this.apiKey,
    this.email,
    this.password,
    this.createAccount = false,
  });

  /// `--project` / `FIREBASE_PROJECT_ID`; `demo-example` with an emulator.
  final String? projectId;

  /// `--bucket` / `STORAGE_BUCKET`; `<project>.appspot.com` when not given.
  final String? bucket;

  /// `--emulator-host` / `FIREBASE_STORAGE_EMULATOR_HOST`
  /// (`host:port`).
  final String? emulatorHost;

  /// `--auth-emulator-host` / `FIREBASE_AUTH_EMULATOR_HOST` (`host:port`).
  final String? authEmulatorHost;

  /// `--api-key` / `FIREBASE_API_KEY`: needed to sign in to a real project.
  final String? apiKey;

  /// `--email` / `STORAGE_EMAIL`: signs in before the command runs.
  final String? email;

  /// `--password` / `STORAGE_PASSWORD`.
  final String? password;

  /// `--create-account`: create the user first (the Auth emulator accepts
  /// any new address); an existing user is signed in.
  final bool createAccount;
}

/// A [FirebaseStorage] and the Auth client behind it; [close] releases both.
class StorageSession {
  StorageSession._(this.storage, this._auth);

  final FirebaseStorage storage;
  final FirebaseUserAuth? _auth;

  Future<void> close() async {
    storage.close();
    await _auth?.dispose();
  }
}

Future<StorageSession> openStorage(StorageConfig config) async {
  final String? emulator = _nonEmpty(config.emulatorHost);
  final String? authEmulator = _nonEmpty(config.authEmulatorHost);
  final String? projectId =
      _nonEmpty(config.projectId) ?? (emulator == null ? null : 'demo-example');
  if (projectId == null) {
    throw ConfigurationError(
      'Set --emulator-host (or FIREBASE_STORAGE_EMULATOR_HOST), or --project (or '
      'FIREBASE_PROJECT_ID) for a real project.',
    );
  }
  final String bucket = _nonEmpty(config.bucket) ?? '$projectId.appspot.com';
  final String? email = _nonEmpty(config.email);
  final String? password = _nonEmpty(config.password);
  if ((email == null) != (password == null)) {
    throw ConfigurationError('--email and --password go together.');
  }
  final String? apiKey =
      _nonEmpty(config.apiKey) ?? (emulator == null ? null : 'fake-api-key');
  if (email != null && apiKey == null) {
    throw ConfigurationError(
      'Signing in to a real project needs --api-key (or FIREBASE_API_KEY).',
    );
  }

  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: apiKey ?? '',
      // Any non-empty id works outside of Android and iOS.
      appId: '1:1234567890:dart:example',
      projectId: projectId,
      storageBucket: bucket,
    ),
    name: 'storage_cli',
  );

  FirebaseUserAuth? auth;
  if (email != null && password != null) {
    // Registers itself as the token provider of the app, which Storage reads
    // for every request.
    auth = await FirebaseUserAuth.forApp(app, emulatorHost: authEmulator);
    if (config.createAccount) {
      try {
        await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') {
          rethrow;
        }
        await auth.signInWithEmailAndPassword(email: email, password: password);
      }
    } else {
      await auth.signInWithEmailAndPassword(email: email, password: password);
    }
  }

  return StorageSession._(
    FirebaseStorage(app, bucket: bucket, emulatorHost: emulator),
    auth,
  );
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// The value of the first of [names] that is set in the environment.
String? firstEnvironment(List<String> names, [Map<String, String>? env]) {
  final Map<String, String> source = env ?? Platform.environment;
  for (final String name in names) {
    final String? value = _nonEmpty(source[name]);
    if (value != null) {
      return value;
    }
  }
  return null;
}
