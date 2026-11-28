// Round 3: deleting and re-creating apps on a native-style core (spec 5.12,
// as-built A18). Like the Android, iOS and macOS cores of firebase_core, the
// fake core here keeps the firebase_app_dart app of a deleted app and refuses
// to delete the default app.

@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart'
    show
        FirebaseAppPlatform,
        FirebasePlatform,
        duplicateApp,
        noAppExists,
        noDefaultAppDelete;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart/firebase_remote_config_dart.dart'
    as rc;
import 'package:firebase_remote_config_dart_platform/firebase_remote_config_dart_platform.dart';
import 'package:firebase_remote_config_dart_platform/src/firebase_remote_config_platform.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// A `firebase_core` implementation that behaves as the native ones do for a
/// delete: the app leaves the list, nothing else happens to the
/// `firebase_app_dart` app of that name. A delete waits for [deleteGate]
/// while it is set.
final class NativeStyleCore extends FirebasePlatform {
  final Map<String, _NativeApp> _apps = <String, _NativeApp>{};

  /// Holds each delete of a named app until it completes.
  Completer<void>? deleteGate;

  @override
  List<FirebaseAppPlatform> get apps =>
      List<FirebaseAppPlatform>.unmodifiable(_apps.values);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    final String appName = name ?? defaultFirebaseAppName;
    final _NativeApp? existing = _apps[appName];
    if (existing != null) {
      if (options != null && existing.options != options) {
        throw duplicateApp(appName);
      }
      return existing;
    }
    if (options == null) {
      throw FirebaseException(plugin: 'core', code: 'no-options');
    }
    return _apps[appName] = _NativeApp(this, appName, options);
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final _NativeApp? app = _apps[name];
    if (app == null) {
      throw noAppExists(name);
    }
    return app;
  }
}

class _NativeApp extends FirebaseAppPlatform {
  _NativeApp(this._core, super.name, super.options);

  final NativeStyleCore _core;

  @override
  bool get isAutomaticDataCollectionEnabled => true;

  @override
  Future<void> delete() async {
    if (name == defaultFirebaseAppName) {
      throw noDefaultAppDelete();
    }
    final Completer<void>? gate = _core.deleteGate;
    if (gate != null) {
      await gate.future;
    }
    _core._apps.remove(name);
  }

  @override
  Future<void> setAutomaticDataCollectionEnabled(bool enabled) async {}

  @override
  Future<void> setAutomaticResourceManagementEnabled(bool enabled) async {}
}

final NativeStyleCore core = NativeStyleCore();

/// The adapter instance behind [app].
DartFirebaseRemoteConfig platformOf(FirebaseApp app) =>
    DartFirebaseRemoteConfig.forApp(app);

/// Options with another app id than [options].
const FirebaseOptions otherOptions = FirebaseOptions(
  apiKey: apiKey,
  appId: '1:1:web:2',
  messagingSenderId: '1',
  projectId: projectId,
);

final RemoteConfigSettings noInterval = RemoteConfigSettings(
  fetchTimeout: const Duration(seconds: 60),
  minimumFetchInterval: Duration.zero,
);

bool isListed(dart_app.FirebaseApp app) => dart_app.Firebase.apps.any(
  (dart_app.FirebaseApp candidate) => identical(candidate, app),
);

void main() {
  setUpAll(() {
    // Before the first use of Firebase, which caches the implementation.
    FirebasePlatform.instance = core;
    FirebaseRemoteConfigDart.use(
      store: store,
      httpClient: backend.client,
      languageCode: languageCode,
      useDartCore: false,
    );
  });
  setUp(() {
    backend.reset();
    freshStore();
    store.failure = null;
    core.deleteGate = null;
  });

  test('A18 a read or fetch during the delete window gets defaults or internal '
      'and creates no clients; after the delete and a re-create, a use '
      'creates clients again', () async {
    final FirebaseApp app = await newApp();
    final DartFirebaseRemoteConfig platform = platformOf(app);
    await platform.setDefaults(<String, dynamic>{'greeting': 'default'});
    backend.entries = <String, String>{'greeting': 'remote'};
    expect(await platform.fetchAndActivate(), isTrue);
    final rc.FirebaseRemoteConfig before = platform.client;

    final Completer<void> gate = Completer<void>();
    core.deleteGate = gate;
    final Future<void> deleting = app.delete();
    await Future<void>.delayed(Duration.zero);
    final int requests = backend.requests.length;

    expect(Firebase.app(app.name).name, app.name, reason: 'still listed');
    expect(platform.getString('greeting'), 'default');
    expect(platform.getValue('greeting').source, ValueSource.valueDefault);
    expect(platform.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
    await expectLater(platform.fetch(), throwsRemoteConfigCode('internal'));
    await expectLater(
      platform.setCustomSignals(<String, Object?>{'tier': 'gold'}),
      throwsRemoteConfigCode('internal'),
    );
    expect(() => platform.client, throwsA(isRemoteConfigCode('internal')));
    expect(backend.requests, hasLength(requests), reason: 'no new clients');

    gate.complete();
    await deleting;
    expect(() => platform.client, throwsA(isA<FirebaseException>()));

    final FirebaseApp again = await Firebase.initializeApp(
      name: app.name,
      options: options,
    );
    final rc.FirebaseRemoteConfig after = platformOf(again).client;
    expect(after, isNot(same(before)));
    await platform.setConfigSettings(noInterval);
    backend.entries = <String, String>{'greeting': 'again'};
    expect(await platform.fetchAndActivate(), isTrue);
    expect(platform.getString('greeting'), 'again');
    await again.delete();
  });

  test('A18 native-style delete and re-create with the same options reuses '
      'the same Dart app', () async {
    final FirebaseApp app = await newApp();
    final rc.FirebaseRemoteConfig before = platformOf(app).client;
    final dart_app.FirebaseApp dartApp = before.app;
    await app.delete();
    expect(isListed(dartApp), isTrue, reason: 'the native core keeps it');

    final FirebaseApp again = await Firebase.initializeApp(
      name: app.name,
      options: options,
    );
    final DartFirebaseRemoteConfig platform = platformOf(again);
    final rc.FirebaseRemoteConfig after = platform.client;
    expect(after, isNot(same(before)), reason: 'the old clients were closed');
    expect(after.app, same(dartApp));
    expect(platform.client, same(after));

    backend.entries = <String, String>{'greeting': 'same'};
    expect(await platform.fetchAndActivate(), isTrue);
    expect(platform.getString('greeting'), 'same');
    await again.delete();
  });

  test('A18 native-style re-create with other options: the old Dart app is '
      'still listed, reads give defaults and fetch throws internal naming the '
      'remedy', () async {
    final FirebaseApp app = await newApp();
    final DartFirebaseRemoteConfig platform = platformOf(app);
    await platform.setDefaults(<String, dynamic>{'greeting': 'default'});
    backend.entries = <String, String>{'greeting': 'remote'};
    expect(await platform.fetchAndActivate(), isTrue);
    final dart_app.FirebaseApp dartApp = platform.client.app;
    await app.delete();

    final FirebaseApp again = await Firebase.initializeApp(
      name: app.name,
      options: otherOptions,
    );
    expect(platformOf(again), same(platform));
    expect(isListed(dartApp), isTrue);
    expect(dartApp.options.appId, options.appId);
    final int requests = backend.requests.length;

    expect(platform.getString('greeting'), 'default');
    expect(platform.getValue('greeting').source, ValueSource.valueDefault);
    expect(platform.getAll().keys, <String>['greeting']);
    expect(platform.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
    await expectLater(
      platform.fetch(),
      throwsA(
        isRemoteConfigCode('internal').having(
          (FirebaseException e) => e.message,
          'message',
          allOf(contains('other options'), contains('restart')),
        ),
      ),
    );
    expect(() => platform.client, throwsA(isRemoteConfigCode('internal')));
    expect(isListed(dartApp), isTrue);
    expect(backend.requests, hasLength(requests));
  });
}
