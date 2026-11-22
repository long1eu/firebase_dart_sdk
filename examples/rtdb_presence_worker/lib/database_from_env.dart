// Creates the Realtime Database instance from flags and environment
// variables, so that no project or host is written into a file.

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';

/// Thrown when the configuration does not say which backend to use.
class ConfigurationError implements Exception {
  ConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The database that the configuration describes:
///
/// - [emulatorHost] (`host:port`), by default `FIREBASE_DATABASE_EMULATOR_HOST`:
///   the emulator, over plain WebSocket. The project is `demo-example`.
/// - [databaseUrl], by default `FIREBASE_DATABASE_URL`: the namespace (and the
///   host, without an emulator) of the database.
///
/// With neither, the configuration is refused: the default URL of a
/// `demo-example` project would name a database that does not exist.
FirebaseDatabase databaseFromConfiguration({
  String? emulatorHost,
  String? databaseUrl,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? host =
      _nonEmpty(emulatorHost) ??
      _nonEmpty(env['FIREBASE_DATABASE_EMULATOR_HOST']);
  final String? url =
      _nonEmpty(databaseUrl) ?? _nonEmpty(env['FIREBASE_DATABASE_URL']);
  if (host == null && url == null) {
    throw ConfigurationError(
      'Set FIREBASE_DATABASE_EMULATOR_HOST (host:port of a Database emulator) '
      'or give a database URL (--database-url or FIREBASE_DATABASE_URL).',
    );
  }
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(
      apiKey: env['FIREBASE_API_KEY'] ?? '',
      // Any non-empty id works outside of Android and iOS.
      appId: '1:1234567890:dart:example',
      projectId: 'demo-example',
    ),
  );
  return FirebaseDatabase(app, databaseUrl: url, emulatorHost: host);
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
