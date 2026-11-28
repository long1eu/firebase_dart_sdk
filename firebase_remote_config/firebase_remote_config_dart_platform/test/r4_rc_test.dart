// Round 4 of the adapter tests (spec 5.12, as-built A18, A22): every error
// leaving the adapter is a FirebaseException of firebase_remote_config, the
// settings, the deletion service registered at instance creation, and the
// default store after close. The native-style core (an app re-created with
// other options) is in r3_rc_native_core_test.dart.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart_platform/firebase_remote_config_dart_platform.dart';
import 'package:firebase_remote_config_dart_platform/src/default_store_io.dart';
import 'package:firebase_remote_config_dart_platform/src/firebase_remote_config_platform.dart';
import 'package:firebase_remote_config_platform_interface/firebase_remote_config_platform_interface.dart'
    show FirebaseRemoteConfigPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'harness.dart';

/// The adapter instance behind [app].
DartFirebaseRemoteConfig platformOf(FirebaseApp app) =>
    DartFirebaseRemoteConfig.forApp(app);

/// A service whose dispose holds `FirebaseApp.delete` between the disposal of
/// the services and the delete of the app.
final class _HoldDelete implements FirebaseService {}

/// A value the injected failures carry; no message may contain it.
const String _secret = 'secret-value-4711';

/// A store whose every call throws a [StateError] carrying [_secret].
final class _ThrowingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError(_secret);

  @override
  Future<void> write(String key, String? value) async =>
      throw StateError(_secret);

  @override
  Future<String?> update(
    String key,
    String? Function(String? current) transform,
  ) async => throw StateError(_secret);

  @override
  Stream<String> get changes => const Stream<String>.empty();

  @override
  Future<void> close() async {}
}

/// A path_provider that answers the application support directory with
/// [supportPath] and counts the calls.
final class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.supportPath);

  final String supportPath;

  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    return supportPath;
  }
}

/// An `internal` FirebaseException whose message and text do not contain
/// [_secret].
Matcher get _valueFreeInternal => isRemoteConfigCode('internal')
    .having(
      (FirebaseException e) => e.message ?? '',
      'message',
      isNot(contains(_secret)),
    )
    .having(
      (FirebaseException e) => e.toString(),
      'toString',
      isNot(contains(_secret)),
    );

/// Expects every member of [platform] that needs the client to fail with
/// `internal`, and the reads to answer from the defaults without throwing.
Future<void> expectEveryMemberInternal(
  DartFirebaseRemoteConfig platform,
) async {
  await platform.setDefaults(<String, dynamic>{'greeting': 'default'});
  await expectLater(platform.activate(), throwsRemoteConfigCode('internal'));
  await expectLater(
    platform.ensureInitialized(),
    throwsRemoteConfigCode('internal'),
  );
  await expectLater(platform.fetch(), throwsRemoteConfigCode('internal'));
  await expectLater(
    platform.fetchAndActivate(),
    throwsRemoteConfigCode('internal'),
  );
  await expectLater(
    platform.setCustomSignals(<String, Object?>{'tier': 'gold'}),
    throwsRemoteConfigCode('internal'),
  );
  await expectLater(
    platform.onConfigUpdated,
    emitsError(isRemoteConfigCode('internal')),
  );
  expect(() => platform.client, throwsA(isRemoteConfigCode('internal')));

  expect(platform.getString('greeting'), 'default');
  expect(platform.getValue('greeting').source, ValueSource.valueDefault);
  expect(platform.getString('missing'), '');
  expect(platform.getValue('missing').source, ValueSource.valueStatic);
  expect(platform.getBool('missing'), isFalse);
  expect(platform.getInt('missing'), 0);
  expect(platform.getDouble('missing'), 0.0);
  expect(platform.getAll().keys, <String>['greeting']);
  expect(platform.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
  expect(
    platform.lastFetchTime,
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// Replaces the configuration of the clients created from now on with
/// [config] for the current test.
void useConfigForTest(DartRemoteConfigConfig config) {
  final DartRemoteConfigConfig saved = DartFirebaseRemoteConfig.config;
  DartFirebaseRemoteConfig.config = config;
  addTearDown(() => DartFirebaseRemoteConfig.config = saved);
}

void main() {
  registerForTests();

  group('A18 every error is a FirebaseException of firebase_remote_config', () {
    test('A18 the registered instance (no app): every member that needs the '
        'client throws internal, nothing as StateError or no-app; the reads '
        'answer from the defaults', () async {
      final DartFirebaseRemoteConfig registered =
          FirebaseRemoteConfigPlatform.instance as DartFirebaseRemoteConfig;
      await expectEveryMemberInternal(registered);
      expect(backend.requests, isEmpty);
    });

    test('A18 after the app is deleted: every member that needs the client '
        'throws internal; the reads answer from the defaults', () async {
      final FirebaseApp app = await newApp();
      final DartFirebaseRemoteConfig platform = platformOf(app);
      await platform.ensureInitialized();
      await app.delete();
      final int requests = backend.requests.length;

      await expectEveryMemberInternal(platform);
      expect(backend.requests, hasLength(requests));
    });

    test('A18 a StateError from the store becomes internal with a value-free '
        'message', () async {
      useConfigForTest(
        DartRemoteConfigConfig(
          store: _ThrowingStore(),
          httpClient: backend.client,
          languageCode: languageCode,
        ),
      );
      final FirebaseApp app = await newApp();
      final DartFirebaseRemoteConfig platform = platformOf(app);
      await expectLater(
        platform.ensureInitialized(),
        throwsA(_valueFreeInternal),
      );
      await expectLater(platform.fetch(), throwsA(_valueFreeInternal));
      await expectLater(platform.activate(), throwsA(_valueFreeInternal));
      await platform.setDefaults(<String, dynamic>{'greeting': 'default'});
      expect(platform.getString('greeting'), 'default');
      await app.delete();
    });

    test('A18 a StateError from the HTTP client becomes internal with a '
        'value-free message', () async {
      final http.Client throwing = MockClient(
        (http.Request request) async => throw StateError(_secret),
      );
      useConfigForTest(
        DartRemoteConfigConfig(
          store: store,
          httpClient: throwing,
          languageCode: languageCode,
        ),
      );
      final FirebaseApp app = await newApp();
      final DartFirebaseRemoteConfig platform = platformOf(app);
      await expectLater(platform.fetch(), throwsA(_valueFreeInternal));
      await expectLater(
        platform.fetchAndActivate(),
        throwsA(_valueFreeInternal),
      );
      await app.delete();
    });
  });

  group('A18 setConfigSettings', () {
    test('A18 Duration.zero for both settings is accepted and settings '
        'returns it', () async {
      final DartFirebaseRemoteConfig platform = platformOf(await newApp());
      await platform.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: Duration.zero,
          minimumFetchInterval: Duration.zero,
        ),
      );
      expect(platform.settings.fetchTimeout, Duration.zero);
      expect(platform.settings.minimumFetchInterval, Duration.zero);
    });

    test('A18 -1 µs for either setting gives invalid-argument and the old '
        'settings stay', () async {
      final DartFirebaseRemoteConfig platform = platformOf(await newApp());
      await platform.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 7),
          minimumFetchInterval: const Duration(minutes: 3),
        ),
      );
      const Duration minusOne = Duration(microseconds: -1);
      await expectLater(
        platform.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: minusOne,
            minimumFetchInterval: Duration.zero,
          ),
        ),
        throwsRemoteConfigCode('invalid-argument'),
      );
      await expectLater(
        platform.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: Duration.zero,
            minimumFetchInterval: minusOne,
          ),
        ),
        throwsRemoteConfigCode('invalid-argument'),
      );
      expect(platform.settings.fetchTimeout, const Duration(seconds: 7));
      expect(
        platform.settings.minimumFetchInterval,
        const Duration(minutes: 3),
      );
    });

    test('A18 settings is a copy: changing it changes nothing', () async {
      final DartFirebaseRemoteConfig platform = platformOf(await newApp());
      final RemoteConfigSettings copy = platform.settings;
      copy.fetchTimeout = const Duration(seconds: 1);
      copy.minimumFetchInterval = Duration.zero;
      expect(platform.settings.fetchTimeout, const Duration(seconds: 60));
      expect(platform.settings.minimumFetchInterval, const Duration(hours: 12));
    });
  });

  group('A18 the deletion service registered at instance creation', () {
    test('A18 an instance from instanceFor, then app.delete() with a slow '
        'sibling dispose: fetch() before it finishes throws internal and '
        'creates no clients; afterwards no service is left; a re-init with '
        'the same options gets new clients', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      // The official plugin creates its delegate on first use; settings
      // creates the adapter instance (and its service) without clients.
      expect(remoteConfig.settings.fetchTimeout, const Duration(seconds: 60));
      expect(backend.requests, isEmpty);

      final Completer<void> hold = Completer<void>();
      app.registerService<_HoldDelete>(
        _HoldDelete(),
        dispose: (_HoldDelete _) => hold.future,
      );
      final Future<void> deleting = app.delete();
      await Future<void>.delayed(Duration.zero);

      expect(Firebase.app(app.name).name, app.name, reason: 'still listed');
      await expectLater(
        remoteConfig.fetch(),
        throwsRemoteConfigCode('internal'),
      );
      await expectLater(
        platformOf(app).fetch(),
        throwsRemoteConfigCode('internal'),
      );
      expect(backend.requests, isEmpty, reason: 'no clients were created');

      hold.complete();
      await deleting;
      // firebase_core forgets every service of the app's name after the
      // delete, the adapter's with the sibling's.
      expect(app.getService<_HoldDelete>(), isNull);

      final FirebaseApp again = await Firebase.initializeApp(
        name: app.name,
        options: options,
      );
      expect(again.getService<_HoldDelete>(), isNull);
      final DartFirebaseRemoteConfig platform = platformOf(again);
      await platform.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 60),
          minimumFetchInterval: Duration.zero,
        ),
      );
      backend.entries = <String, String>{'greeting': 'again'};
      await platform.fetch();
      expect(backend.fetches, hasLength(1));
      expect(await platform.activate(), isTrue);
      expect(platform.getString('greeting'), 'again');
      await again.delete();
    });
  });

  group('A22 ApplicationSupportStore after close()', () {
    late Directory support;

    setUp(() {
      support = Directory.systemTemp.createTempSync('rc_r4_support_');
    });

    tearDown(() {
      support.deleteSync(recursive: true);
    });

    test('A22 after close() a read throws StateError and path_provider is '
        'not asked again; a second close() returns the same future', () async {
      final _FakePathProvider paths = _FakePathProvider(support.path);
      PathProviderPlatform.instance = paths;
      final ApplicationSupportStore defaultStore = ApplicationSupportStore();
      await defaultStore.write('k', 'v');
      expect(await defaultStore.read('k'), 'v');
      expect(paths.calls, 1);

      final Future<void> first = defaultStore.close();
      final Future<void> second = defaultStore.close();
      expect(identical(first, second), isTrue);
      await first;

      await expectLater(defaultStore.read('k'), throwsStateError);
      await expectLater(defaultStore.write('k', 'w'), throwsStateError);
      await expectLater(
        defaultStore.update('k', (String? current) => 'w'),
        throwsStateError,
      );
      expect(paths.calls, 1);
      expect(identical(defaultStore.close(), first), isTrue);
    });

    test('A22 closed before its first use: a read throws StateError and '
        'path_provider is never asked', () async {
      final _FakePathProvider paths = _FakePathProvider(support.path);
      PathProviderPlatform.instance = paths;
      final ApplicationSupportStore defaultStore = ApplicationSupportStore();
      await defaultStore.close();
      await expectLater(defaultStore.read('k'), throwsStateError);
      expect(paths.calls, 0);
    });
  });
}
