// A custom PlatformDependencies: connectivity events from your own source and
// a storage of your own.
//
//     dart run example/platform_dependencies.dart
//
// Needs nothing else: no emulator, no network. The connectivity events are
// simulated with a timer; in a Flutter app they come from a plugin such as
// connectivity_plus. Firestore (cloud_firestore_dart) listens to
// app.onNetworkConnected: a `true` restarts its failed streams at once instead
// of after their backoff.

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_app_dart/platform_dependencies.dart';
import 'package:rxdart/rxdart.dart';

/// The services this program gives the app.
///
/// The app reads every member once, when it is created: keep the subject in a
/// field so that the app and your connectivity source share the same object.
class AppDependencies extends PlatformDependencies {
  /// Fed by your connectivity source.
  final BehaviorSubject<bool> connectivity = BehaviorSubject<bool>.seeded(true);

  /// Where the app keeps its settings.
  final MapStorage settings = MapStorage();

  @override
  BehaviorSubject<bool> get onNetworkConnected => connectivity;

  @override
  LocalStorage get storage => settings;
}

/// A [LocalStorage] on top of a map. A real one writes to disk (for example
/// with shared_preferences): [get] is synchronous, so load the values before
/// you create the app.
class MapStorage extends LocalStorage {
  /// The stored values.
  final Map<String, String> values = <String, String>{};

  @override
  String? get(String key) => values[key];

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

Future<void> main() async {
  final AppDependencies dependencies = AppDependencies();
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: '<YOUR_API_KEY>',
      applicationId: '1:1234567890:dart:example',
      projectId: 'my-project',
    ),
    dependencies: dependencies,
  );

  // The app hands out the subject of the dependencies.
  print(
    'same subject: '
    '${identical(app.onNetworkConnected, dependencies.connectivity)}',
  );

  // What a service such as Firestore sees.
  final StreamSubscription<bool> subscription = app.onNetworkConnected.listen(
    (bool connected) => print('connected: $connected'),
  );

  // Simulated events of a connectivity plugin.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  dependencies.connectivity.add(false);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  dependencies.connectivity.add(true);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  await subscription.cancel();

  // The app writes its own settings to the storage you gave it.
  app.setDataCollectionDefaultEnabled(enabled: false);
  print('stored settings: ${dependencies.settings.values}');

  await dependencies.connectivity.close();
}
