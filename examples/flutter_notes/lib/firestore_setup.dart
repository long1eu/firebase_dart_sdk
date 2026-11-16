import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';

// The backend, from --dart-define. By default the app talks to a Firestore
// emulator on 127.0.0.1:8080 (on the Android emulator, pass
// --dart-define=EMULATOR_HOST=10.0.2.2). For a real project pass
// --dart-define=USE_EMULATOR=false and the values of a web app of the project
// (Firebase console, Project settings, Your apps).
const bool useEmulator = bool.fromEnvironment(
  'USE_EMULATOR',
  defaultValue: true,
);
const String emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);
const int emulatorPort = int.fromEnvironment(
  'EMULATOR_PORT',
  defaultValue: 8080,
);
// A `demo-` project id never reaches a real project.
const String projectId = String.fromEnvironment(
  'PROJECT_ID',
  defaultValue: 'demo-notes',
);
// The emulator needs no key; an empty key is not sent.
const String apiKey = String.fromEnvironment('API_KEY');
const String applicationId = String.fromEnvironment(
  'APP_ID',
  defaultValue: '1:1234567890:web:0123456789abcdef',
);

/// Feeds the connectivity events of `connectivity_plus` to Firestore.
///
/// Firestore restarts its streams at once on every `true`, instead of
/// waiting for the rest of its backoff. `false` is ignored: a failed stream
/// is what makes the client consider itself offline.
class AppDependencies extends PlatformDependencies {
  AppDependencies() {
    _subscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) => connectivity.add(
        results.any((ConnectivityResult r) => r != ConnectivityResult.none),
      ),
    );
  }

  final BehaviorSubject<bool> connectivity = BehaviorSubject<bool>.seeded(true);
  late final StreamSubscription<List<ConnectivityResult>> _subscription;

  @override
  BehaviorSubject<bool> get onNetworkConnected => connectivity;

  Future<void> dispose() async {
    await _subscription.cancel();
    await connectivity.close();
  }
}

/// Creates the app and the Firestore instance, with the cache in a SQLite
/// file in the application support directory.
Future<FirebaseFirestore> createFirestore(AppDependencies dependencies) async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: apiKey,
      appId: applicationId,
      projectId: projectId,
    ),
    dependencies: dependencies,
  );

  final Directory directory = await getApplicationSupportDirectory();
  Settings settings = Settings(cacheSettings: PersistentCacheSettings());
  if (useEmulator) {
    settings = settings.withEmulator(emulatorHost, emulatorPort);
  }
  return FirebaseFirestore.instanceFor(
    app: app,
    settings: settings,
    openDatabase: sqliteOpener(directory: '${directory.path}/firestore'),
  );
}
