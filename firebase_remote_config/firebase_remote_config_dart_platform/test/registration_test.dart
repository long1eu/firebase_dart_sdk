// The registration and the default store, in a file of their own: they must
// run before anything else installs the package, and `use` takes no store
// here.

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show FirebasePlatform, MethodChannelFirebase;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart_platform/firebase_remote_config_dart_platform.dart';
import 'package:firebase_remote_config_dart_platform/src/core.dart';
import 'package:firebase_remote_config_dart_platform/src/firebase_remote_config_platform.dart';
import 'package:firebase_remote_config_platform_interface/firebase_remote_config_platform_interface.dart'
    show FirebaseRemoteConfigPlatform;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_backend.dart';
import 'harness.dart' show options;

/// A path_provider that answers the application support directory with
/// [supportPath].
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider(this.supportPath);

  final String supportPath;

  /// The number of `getApplicationSupportPath` calls.
  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    return supportPath;
  }
}

void main() {
  late Directory support;

  setUpAll(() {
    support = Directory.systemTemp.createTempSync('rc_adapter_support_');
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    support.deleteSync(recursive: true);
  });

  test('5.12 registerWith on Linux under flutter test registers the no-app '
      'instance and leaves firebase_core alone; use installs the Dart core; a '
      'replaced instance is not registered until use runs again', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(FirebaseRemoteConfigDart.isRegistered, isFalse);

    FirebaseRemoteConfigDart.registerWith();
    expect(FirebaseRemoteConfigDart.isRegistered, isTrue);
    final FirebaseRemoteConfigPlatform registered =
        FirebaseRemoteConfigPlatform.instance;
    expect(registered, isA<DartFirebaseRemoteConfig>());
    expect(FirebasePlatform.instance, isA<MethodChannelFirebase>());

    FirebaseRemoteConfigPlatform.instance = DartFirebaseRemoteConfig();
    expect(FirebaseRemoteConfigDart.isRegistered, isFalse);

    FirebaseRemoteConfigDart.use(httpClient: FakeBackend().client);
    expect(FirebaseRemoteConfigDart.isRegistered, isTrue);
    expect(FirebasePlatform.instance, isA<LinuxFirebaseCore>());
    final FirebasePlatform core = FirebasePlatform.instance;
    installCoreIfNeeded(force: true);
    expect(FirebasePlatform.instance, same(core), reason: 'kept, with apps');
  });

  test(
    '5.12 default store: without use(store:), every app keeps its records in '
    'one file store in firebase_dart under the application support '
    'directory; use after the first client throws',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final FakePathProvider paths = FakePathProvider(support.path);
      PathProviderPlatform.instance = paths;
      final FakeBackend backend = FakeBackend()
        ..entries = <String, String>{'greeting': 'hello'};
      FirebaseRemoteConfigDart.use(httpClient: backend.client);

      final FirebaseApp app = await Firebase.initializeApp(options: options);
      final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;
      expect(await remoteConfig.fetchAndActivate(), isTrue);
      expect(remoteConfig.getString('greeting'), 'hello');

      final Directory store = Directory(
        '${support.path}${Platform.pathSeparator}firebase_dart',
      );
      expect(store.existsSync(), isTrue);
      expect(
        File('${store.path}${Platform.pathSeparator}.owner.lock').existsSync(),
        isTrue,
      );
      final List<FileSystemEntity> records = store
          .listSync()
          .where(
            (FileSystemEntity entity) =>
                RegExp(r'[0-9a-f]{64}\.json$').hasMatch(entity.path),
          )
          .toList();
      expect(records, isNotEmpty, reason: 'one file per key');
      final int afterFirstApp = records.length;

      // A second app shares the store: a second FileKeyValueStore for the
      // same directory in this isolate would throw a StateError.
      final FirebaseApp second = await Firebase.initializeApp(
        name: 'second',
        options: options,
      );
      final FirebaseRemoteConfig other = FirebaseRemoteConfig.instanceFor(
        app: second,
      );
      expect(await other.fetchAndActivate(), isTrue);
      expect(other.getString('greeting'), 'hello');
      expect(
        store
            .listSync()
            .where(
              (FileSystemEntity entity) =>
                  RegExp(r'[0-9a-f]{64}\.json$').hasMatch(entity.path),
            )
            .length,
        greaterThan(afterFirstApp),
        reason: 'the records of the second app are under its own keys',
      );
      expect(paths.calls, 1, reason: 'the directory is looked up once');
      expect(app.name, defaultFirebaseAppName);

      expect(FirebaseRemoteConfigDart.use, throwsStateError);
    },
  );
}
