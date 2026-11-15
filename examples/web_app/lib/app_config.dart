/// What both pages read from their address: which backend and which cache.
///
/// This file imports neither `cloud_firestore_dart.dart` nor `lite.dart`, so
/// that the Lite page does not pull in the main library.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The Firebase options of the app.
///
/// `demo-example` is a demo project id: the emulator accepts it without a
/// real project behind it. To use a real project, put its web app options
/// here (Firebase console, Project settings, Your apps) and open the page with
/// `?emulator=none`.
const FirebaseOptions firebaseOptions = FirebaseOptions(
  apiKey: 'demo-key',
  applicationId: '1:1234567890:web:example',
  projectId: 'demo-example',
);

/// The collection both pages read and write.
const String notesCollection = 'web_app_notes';

/// The cache of the page of the main library.
enum CacheChoice {
  /// No `openDatabase`: the cache is gone when the page is closed.
  memory,

  /// SQLite (WebAssembly) stored in IndexedDB.
  indexeddb,

  /// SQLite (WebAssembly) in a worker, stored in the origin private file
  /// system, or in IndexedDB where the browser lacks synchronous OPFS access.
  opfs,
}

/// The settings of a page, read from its query string:
///
/// - `emulator=<host>:<port>`: the Firestore emulator (default
///   `127.0.0.1:8080`); `emulator=none` uses the production backend.
/// - `cache=memory|indexeddb|opfs` (default `memory`; main page only).
class AppConfig {
  const AppConfig({
    required this.emulatorHost,
    required this.emulatorPort,
    required this.cache,
  });

  factory AppConfig.fromUri(Uri uri) {
    final String emulator = uri.queryParameters['emulator'] ?? '127.0.0.1:8080';
    String? host;
    int? port;
    if (emulator != 'none') {
      final int colon = emulator.lastIndexOf(':');
      if (colon <= 0) {
        throw FormatException(
          'emulator must be <host>:<port> or none',
          emulator,
        );
      }
      host = emulator.substring(0, colon);
      port = int.parse(emulator.substring(colon + 1));
    }
    final String cacheName = uri.queryParameters['cache'] ?? 'memory';
    final CacheChoice cache = CacheChoice.values.firstWhere(
      (CacheChoice choice) => choice.name == cacheName,
      orElse: () => CacheChoice.memory,
    );
    return AppConfig(emulatorHost: host, emulatorPort: port, cache: cache);
  }

  /// Null when the page talks to the production backend.
  final String? emulatorHost;
  final int? emulatorPort;
  final CacheChoice cache;

  String get backendLabel => emulatorHost == null
      ? 'production (${firebaseOptions.projectId})'
      : 'emulator $emulatorHost:$emulatorPort';
}

/// [uri] with the query parameter [key] set to [value], the others kept.
Uri withQueryParameter(Uri uri, String key, String value) {
  return uri.replace(
    queryParameters: <String, String>{...uri.queryParameters, key: value},
  );
}
