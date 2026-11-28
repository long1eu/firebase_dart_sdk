/// Firebase Remote Config for pure Dart: fetch, activate and realtime updates on the VM and the web.
///
/// Create a store and a [FirebaseInstallations] for the app (see `package:firebase_installations_dart`),
/// then a [FirebaseRemoteConfig] with your defaults. Reads are synchronous; [FirebaseRemoteConfig.fetch]
/// and [FirebaseRemoteConfig.activate] change what they return. Errors are
/// [FirebaseRemoteConfigException]s.
///
/// ```dart
/// import 'package:firebase_app_dart/firebase_app_dart.dart';
/// import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart';
///
/// Future<void> main() async {
///   final FirebaseApp app = FirebaseApp.withOptions(
///     const FirebaseOptions(
///       apiKey: '<the Web API key of the project>',
///       appId: '1:1234567890:web:0123456789abcdef',
///       projectId: 'my-project',
///     ),
///   );
///   final KeyValueStore store = MemoryKeyValueStore();
///   final FirebaseInstallations installations = FirebaseInstallations(app, store: store);
///   final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig(
///     app,
///     installations: installations,
///     defaults: <String, Object>{'welcome': 'Hello'},
///   );
///   await remoteConfig.fetchAndActivate();
///   print(remoteConfig.getString('welcome'));
///   await remoteConfig.close();
///   await installations.close();
/// }
/// ```
library firebase_remote_config_dart;

// Imported for the references in the documentation above.
import 'package:firebase_installations_dart/firebase_installations_dart.dart';
import 'package:firebase_remote_config_dart/src/exception.dart';
import 'package:firebase_remote_config_dart/src/firebase_remote_config.dart';

export 'package:firebase_installations_dart/firebase_installations_dart.dart'
    show
        FirebaseInstallations,
        FirebaseInstallationsException,
        KeyValueStore,
        MemoryKeyValueStore;
export 'package:firebase_remote_config_dart/src/exception.dart'
    show FirebaseRemoteConfigException, firebaseRemoteConfigExceptionCodes;
export 'package:firebase_remote_config_dart/src/experiments.dart'
    show RemoteConfigAnalytics;
export 'package:firebase_remote_config_dart/src/firebase_remote_config.dart'
    show FirebaseRemoteConfig;
export 'package:firebase_remote_config_dart/src/logger.dart'
    show RemoteConfigLogLevel, RemoteConfigLogger;
export 'package:firebase_remote_config_dart/src/types.dart'
    show
        FetchResult,
        RemoteConfigFetchStatus,
        RemoteConfigInfo,
        RemoteConfigUpdate,
        RolloutAssignment;
export 'package:firebase_remote_config_dart/src/value.dart'
    show RemoteConfigValue, ValueSource;
