// Creates the FirebaseDatabase from environment variables. The server never
// reaches a real project by accident: it needs an emulator, or an explicit
// DATABASE_URL.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

/// Thrown when the environment does not say which backend to use.
class ConfigurationError implements Exception {
  ConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The database that [environment] describes (`Platform.environment` by
/// default):
///
/// - `FIREBASE_DATABASE_EMULATOR_HOST` (`host:port`): the emulator, project
///   `demo-example`, no credentials.
/// - `DATABASE_URL`: an explicit database URL. Without the emulator host it is
///   the only way to reach a real database, and then no credentials are set
///   up here: the rules decide what an unauthenticated client may do.
/// - Neither: a [ConfigurationError].
FirebaseDatabase databaseFromEnvironment({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? emulator = _nonEmpty(env['FIREBASE_DATABASE_EMULATOR_HOST']);
  final String? url = _nonEmpty(env['DATABASE_URL']);
  if (emulator == null && url == null) {
    throw ConfigurationError(
      'Set FIREBASE_DATABASE_EMULATOR_HOST (host:port of a Database emulator) '
      'or, to use a real database on purpose, DATABASE_URL.',
    );
  }
  if (emulator != null && !_hostPort.hasMatch(emulator)) {
    throw ConfigurationError(
      'FIREBASE_DATABASE_EMULATOR_HOST must be host:port, not "$emulator".',
    );
  }

  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '',
      // Any non-empty id works outside of Android and iOS.
      appId: '1:1234567890:dart:example',
      projectId: 'demo-example',
    ),
    name: 'rtdb-server-${DateTime.now().microsecondsSinceEpoch}',
  );
  return FirebaseDatabase(app, databaseUrl: url, emulatorHost: emulator);
}

final RegExp _hostPort = RegExp(r'^(\[[0-9a-fA-F:]+\]|[^:\s]+):\d+$');

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
