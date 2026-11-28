// Tests through the official firebase_remote_config API, against a fake
// backend: the per-app instances, every member of the platform interface
// (spec 5.12, member table) and the error mapping on the VM.
//
// The cases that need time to pass (a fetch timeout, the one-second retry of
// Installations, the random wait of the realtime auto-fetch) run in
// testWidgets, whose clock is fake: tester.pump moves it.

@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_remote_config_dart_platform/src/firebase_remote_config_platform.dart';
import 'package:firebase_remote_config_platform_interface/firebase_remote_config_platform_interface.dart'
    show FirebaseRemoteConfigPlatform;
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';
import 'harness.dart';

/// Pumps the fake clock in steps of 100 ms until [future] completes, then
/// returns it; fails the test when it has not completed after [limit].
Future<T> settle<T>(
  WidgetTester tester,
  Future<T> future, {
  Duration limit = const Duration(seconds: 30),
}) async {
  bool done = false;
  unawaited(
    future.then<void>(
      (T _) {
        done = true;
      },
      onError: (Object _, StackTrace _) {
        done = true;
      },
    ),
  );
  const Duration step = Duration(milliseconds: 100);
  for (Duration waited = Duration.zero; !done && waited < limit;) {
    await tester.pump(step);
    waited += step;
  }
  if (!done) {
    // Awaiting it would hang the test until the runner's limit.
    fail('The future did not complete within $limit of fake time.');
  }
  return future;
}

/// Deletes [app] (its clients close) and lets the closing finish, so that
/// testWidgets finds no timer left.
Future<void> deleteApp(WidgetTester tester, FirebaseApp app) async {
  await settle(tester, app.delete());
  await tester.pump(const Duration(seconds: 1));
}

/// The adapter instance behind [app].
DartFirebaseRemoteConfig platformOf(FirebaseApp app) =>
    DartFirebaseRemoteConfig.forApp(app);

void main() {
  registerForTests();

  group('5.12 instances', () {
    test('5.12 delegateFor: one per-app instance per app name', () async {
      final FirebaseApp app = await newApp();
      final FirebaseApp other = await newApp();
      final FirebaseRemoteConfigPlatform first =
          FirebaseRemoteConfigPlatform.instanceFor(app: app);
      expect(FirebaseRemoteConfigPlatform.instanceFor(app: app), same(first));
      expect(first, same(platformOf(app)));
      expect(first, isNot(same(platformOf(other))));
      expect(first, isNot(same(FirebaseRemoteConfigPlatform.instance)));
      expect(platformOf(app).client, same(platformOf(app).client));
      expect(
        platformOf(app).client,
        isNot(same(platformOf(other).client)),
        reason: 'one client per app',
      );
    });

    test(
      '5.12 constructor and app: the per-app instance has its app, the '
      'registered instance has none and creates no client (A18: internal)',
      () async {
        final FirebaseApp app = await newApp();
        expect(platformOf(app).app.name, app.name);
        final DartFirebaseRemoteConfig registered =
            FirebaseRemoteConfigPlatform.instance as DartFirebaseRemoteConfig;
        final int requests = backend.requests.length;
        expect(
          () => registered.client,
          throwsA(isRemoteConfigCode('internal')),
        );
        expect(backend.requests, hasLength(requests));
      },
    );

    test('5.12 setInitialValues: the map is ignored and the instance itself '
        'is returned', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfigPlatform platform =
          FirebaseRemoteConfigPlatform.instanceFor(
            app: app,
            pluginConstants: <dynamic, dynamic>{
              'parameters': <String, Object?>{
                'greeting': <String, Object?>{
                  'value': <int>[104, 105],
                  'source': 'remote',
                },
              },
              'lastFetchStatus': 'success',
            },
          );
      expect(platform, same(platformOf(app)));
      expect(platform.getAll(), isEmpty);
      expect(platform.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
    });

    test('5.12 per-app wiring: the requests carry the app options and the '
        'languageCode of use()', () async {
      final FirebaseApp app = await newApp();
      backend.entries = <String, String>{'greeting': 'hello'};
      await FirebaseRemoteConfig.instanceFor(app: app).fetch();
      expect(backend.to(installationsHost), hasLength(1));
      final RecordedRequest fetch = backend.fetches.single;
      expect(
        fetch.url.path,
        '/v1/projects/$projectId/namespaces/firebase:fetch',
      );
      expect(fetch.header('X-Goog-Api-Key'), apiKey);
      expect(fetch.json['app_id'], '1:1:web:1');
      expect(fetch.json['language_code'], languageCode);
    });

    test('5.12 per-app wiring: two apps keep their records apart in the one '
        'store', () async {
      final FirebaseApp app = await newApp();
      final FirebaseApp other = await newApp();
      backend.entries = <String, String>{'greeting': 'hello'};
      await FirebaseRemoteConfig.instanceFor(app: app).fetchAndActivate();
      backend.entries = <String, String>{'greeting': 'other'};
      await FirebaseRemoteConfig.instanceFor(app: other).fetchAndActivate();
      expect(
        FirebaseRemoteConfig.instanceFor(app: app).getString('greeting'),
        'hello',
      );
      expect(
        FirebaseRemoteConfig.instanceFor(app: other).getString('greeting'),
        'other',
      );
      expect(backend.to(installationsHost), hasLength(2));
    });
  });

  group('5.12 fetch status and time', () {
    test('5.12 lastFetchTime: the epoch (UTC) before a fetch, then the time '
        'of the last successful fetch', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.ensureInitialized();
      expect(
        remoteConfig.lastFetchTime,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(remoteConfig.lastFetchTime.isUtc, isTrue);

      final DateTime before = DateTime.now();
      await remoteConfig.fetch();
      final DateTime fetched = remoteConfig.lastFetchTime;
      // The stored time has millisecond precision.
      expect(
        fetched.isBefore(before.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(fetched.isAfter(DateTime.now()), isFalse);

      backend.fetchStatus = 500;
      await expectLater(remoteConfig.setConfigSettings(_noCache), completes);
      await expectLater(remoteConfig.fetch(), throwsA(isA<Object>()));
      expect(
        remoteConfig.lastFetchTime,
        fetched,
        reason: 'a failed fetch keeps the time of the last success',
      );
    });

    test('5.12 lastFetchStatus: noFetchYet, success, failure', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.ensureInitialized();
      expect(remoteConfig.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
      await remoteConfig.setConfigSettings(_noCache);
      await remoteConfig.fetch();
      expect(remoteConfig.lastFetchStatus, RemoteConfigFetchStatus.success);
      backend.fetchStatus = 500;
      await expectLater(
        remoteConfig.fetch(),
        throwsRemoteConfigCode('remote-config-server-error'),
      );
      expect(remoteConfig.lastFetchStatus, RemoteConfigFetchStatus.failure);
    });

    test(
      '5.12 lastFetchStatus: the client throttled becomes throttle',
      () async {
        final FirebaseApp app = await newApp();
        final FirebaseRemoteConfig remoteConfig =
            FirebaseRemoteConfig.instanceFor(app: app);
        backend.fetchStatus = 429;
        await expectLater(
          remoteConfig.fetch(),
          throwsRemoteConfigCode('throttled'),
        );
        expect(remoteConfig.lastFetchStatus, RemoteConfigFetchStatus.throttle);
      },
    );
  });

  group('5.12 settings', () {
    test('5.12 settings: 60 s and 12 h before setConfigSettings', () async {
      final FirebaseApp app = await newApp();
      final RemoteConfigSettings settings = FirebaseRemoteConfig.instanceFor(
        app: app,
      ).settings;
      expect(settings.fetchTimeout, const Duration(seconds: 60));
      expect(settings.minimumFetchInterval, const Duration(hours: 12));
    });

    test('5.12 setConfigSettings: kept by the adapter as a copy', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      final RemoteConfigSettings given = RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 7),
        minimumFetchInterval: const Duration(minutes: 3),
      );
      await remoteConfig.setConfigSettings(given);
      given.fetchTimeout = const Duration(seconds: 99);
      expect(remoteConfig.settings.fetchTimeout, const Duration(seconds: 7));
      expect(
        remoteConfig.settings.minimumFetchInterval,
        const Duration(minutes: 3),
      );
    });

    test('5.12 fetch: within the minimumFetchInterval of the settings the '
        'fetch sends nothing', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.fetch();
      await remoteConfig.fetch();
      expect(backend.fetches, hasLength(1), reason: '12 h by default');

      await remoteConfig.setConfigSettings(_noCache);
      await remoteConfig.fetch();
      expect(backend.fetches, hasLength(2));
    });
  });

  group('5.12 activate, ensureInitialized, fetchAndActivate', () {
    test('5.12 ensureInitialized completes on a fresh app', () async {
      final FirebaseApp app = await newApp();
      await expectLater(
        FirebaseRemoteConfig.instanceFor(app: app).ensureInitialized(),
        completes,
      );
    });

    test('5.12 fetch drops the result; activate then answers true, then '
        'false', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      backend.entries = <String, String>{'greeting': 'hello'};
      await remoteConfig.fetch();
      expect(remoteConfig.getString('greeting'), '', reason: 'not active');
      expect(await remoteConfig.activate(), isTrue);
      expect(remoteConfig.getString('greeting'), 'hello');
      expect(await remoteConfig.activate(), isFalse);
    });

    test('5.12 fetchAndActivate: true for a new template, false when the '
        'active one is current', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      backend.entries = <String, String>{'greeting': 'hello'};
      expect(await remoteConfig.fetchAndActivate(), isTrue);
      expect(remoteConfig.getString('greeting'), 'hello');
      expect(await remoteConfig.fetchAndActivate(), isFalse);
      expect(backend.fetches, hasLength(1), reason: 'the second is cached');
    });
  });

  group('5.12 values', () {
    test('5.12 getValue: remote wins over the default; the default over the '
        'static value', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.setDefaults(<String, dynamic>{
        'greeting': 'default',
        'only_default': 'fallback',
      });
      backend.entries = <String, String>{'greeting': 'Bună ziua €'};
      await remoteConfig.fetchAndActivate();

      final RemoteConfigValue remote = remoteConfig.getValue('greeting');
      expect(remote.source, ValueSource.valueRemote);
      expect(remote.asString(), 'Bună ziua €', reason: 'UTF-8 round trip');

      final RemoteConfigValue fallback = remoteConfig.getValue('only_default');
      expect(fallback.source, ValueSource.valueDefault);
      expect(fallback.asString(), 'fallback');

      final RemoteConfigValue missing = remoteConfig.getValue('missing');
      expect(missing.source, ValueSource.valueStatic);
      expect(missing.asString(), '');
      expect(missing.asBool(), isFalse);
      expect(missing.asInt(), 0);
      expect(missing.asDouble(), 0.0);
    });

    test('5.12 getBool/getInt/getDouble/getString use FlutterFire\'s '
        'conversions', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      backend.entries = <String, String>{
        'true_upper': 'TRUE',
        'one': '1',
        'yes': 'yes',
        'decimal': '3.5',
        'hex': '0x10',
        'word': 'abc',
      };
      await remoteConfig.fetchAndActivate();

      expect(remoteConfig.getBool('true_upper'), isTrue);
      expect(remoteConfig.getBool('one'), isTrue);
      expect(remoteConfig.getBool('yes'), isFalse, reason: 'only true and 1');
      expect(remoteConfig.getInt('decimal'), 0, reason: 'int.tryParse');
      expect(remoteConfig.getInt('hex'), 16, reason: 'int.tryParse');
      expect(remoteConfig.getInt('one'), 1);
      expect(remoteConfig.getDouble('decimal'), 3.5);
      expect(remoteConfig.getDouble('word'), 0.0);
      expect(remoteConfig.getString('word'), 'abc');
      expect(remoteConfig.getString('missing'), '');
    });

    test('5.12 getAll: the union of the remote and the default keys, each as '
        'getValue', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.setDefaults(<String, dynamic>{
        'both': 'default',
        'default_only': 'd',
      });
      backend.entries = <String, String>{'both': 'remote', 'remote_only': 'r'};
      await remoteConfig.fetchAndActivate();

      final Map<String, RemoteConfigValue> all = remoteConfig.getAll();
      expect(all.keys.toSet(), <String>{'both', 'default_only', 'remote_only'});
      expect(all['both']!.source, ValueSource.valueRemote);
      expect(all['both']!.asString(), 'remote');
      expect(all['default_only']!.source, ValueSource.valueDefault);
      expect(all['default_only']!.asString(), 'd');
      expect(all['remote_only']!.source, ValueSource.valueRemote);
    });

    test('5.12 setDefaults: values kept as toString(); a new call replaces '
        'the map', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.setDefaults(<String, dynamic>{
        'flag': true,
        'count': 3,
        'ratio': 1.5,
        'whole': 2.0,
        'name': 'x',
      });
      expect(remoteConfig.getString('flag'), 'true');
      expect(remoteConfig.getBool('flag'), isTrue);
      expect(remoteConfig.getString('count'), '3');
      expect(remoteConfig.getInt('count'), 3);
      expect(remoteConfig.getString('ratio'), '1.5');
      expect(remoteConfig.getDouble('ratio'), 1.5);
      expect(remoteConfig.getString('whole'), 2.0.toString());
      expect(remoteConfig.getString('name'), 'x');

      await remoteConfig.setDefaults(<String, dynamic>{'other': 'y'});
      expect(remoteConfig.getValue('flag').source, ValueSource.valueStatic);
      expect(remoteConfig.getAll().keys, <String>['other']);
    });
  });

  group('5.12 custom signals', () {
    test('5.12 setCustomSignals: the client stores them and the next fetch '
        'sends them; null removes one', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await remoteConfig.fetch();
      expect(
        backend.fetches.single.json.containsKey('custom_signals'),
        isFalse,
      );

      await remoteConfig.setCustomSignals(<String, Object?>{
        'tier': 'gold',
        'level': 3,
      });
      await remoteConfig.fetch();
      expect(
        backend.fetches,
        hasLength(2),
        reason: 'new signals skip the cache',
      );
      expect(backend.fetches.last.json['custom_signals'], <String, Object?>{
        'tier': 'gold',
        'level': '3',
      });

      await remoteConfig.setCustomSignals(<String, Object?>{
        'tier': null,
        'level': null,
      });
      await remoteConfig.fetch();
      expect(backend.fetches, hasLength(3));
      expect(backend.fetches.last.json.containsKey('custom_signals'), isFalse);
    });

    test('5.12 setCustomSignals: an ArgumentError of the client becomes '
        'invalid-argument and nothing is stored', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await expectLater(
        remoteConfig.setCustomSignals(<String, Object?>{'long': 'x' * 501}),
        throwsRemoteConfigCode('invalid-argument'),
      );
      await expectLater(
        remoteConfig.setCustomSignals(<String, Object?>{'': 'empty key'}),
        throwsRemoteConfigCode('invalid-argument'),
      );
      expect(platformOf(app).client.customSignals, isEmpty);
    });
  });

  group('5.12 onConfigUpdated', () {
    test('5.12 onConfigUpdated: a realtime 403 reaches the app as a '
        'FirebaseException of the adapter (internal on the VM)', () async {
      final FirebaseApp app = await newApp();
      backend.realtimeStatus = 403;
      await expectLater(
        FirebaseRemoteConfig.instanceFor(app: app).onConfigUpdated,
        emitsError(isRemoteConfigCode('internal')),
      );
      expect(backend.to(realtimeHost), hasLength(1));
    });

    testWidgets('5.12 onConfigUpdated: an update is FlutterFire\'s '
        'RemoteConfigUpdate with the changed keys', (
      WidgetTester tester,
    ) async {
      freshStore();
      final FirebaseApp app = await settle(tester, newApp());
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      backend.entries = <String, String>{'greeting': 'hello', 'same': 's'};
      expect(await settle(tester, remoteConfig.fetchAndActivate()), isTrue);

      backend
        ..entries = <String, String>{
          'greeting': 'hi',
          'same': 's',
          'added': 'a',
        }
        ..templateVersion = 2
        ..realtimeFirstChunk = '[{\n  "latestTemplateVersionNumber": "2"\n}\n';
      final List<RemoteConfigUpdate> updates = <RemoteConfigUpdate>[];
      final List<Object> errors = <Object>[];
      final StreamSubscription<RemoteConfigUpdate> subscription = remoteConfig
          .onConfigUpdated
          .listen(updates.add, onError: errors.add);
      // The connection, the message, then the auto-fetch after its random
      // wait of up to 3 s.
      for (int i = 0; i < 60 && updates.isEmpty && errors.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(errors, isEmpty);
      expect(updates, hasLength(1));
      expect(updates.single, isA<RemoteConfigUpdate>());
      expect(updates.single.updatedKeys, <String>{'greeting', 'added'});
      expect(
        backend.fetches.last.header('X-Firebase-RC-Fetch-Type'),
        'REALTIME/1',
      );
      expect(
        remoteConfig.getString('greeting'),
        'hello',
        reason: 'fetched only',
      );
      expect(await settle(tester, remoteConfig.activate()), isTrue);
      expect(remoteConfig.getString('greeting'), 'hi');

      // Not awaited: the cancel future of the stream completes in the root
      // zone, which the fake clock of testWidgets never runs, so awaiting it
      // hangs the test.
      unawaited(subscription.cancel());
      await deleteApp(tester, app);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('5.12 errors on the VM', () {
    test('5.12 fetch-client-network becomes network-error', () async {
      final FirebaseApp app = await newApp();
      backend.fetchUnreachable = true;
      await expectLater(
        FirebaseRemoteConfig.instanceFor(app: app).fetch(),
        throwsRemoteConfigCode('network-error'),
      );
    });

    testWidgets(
      '5.12 fetch-timeout becomes network-error',
      (WidgetTester tester) async {
        freshStore();
        final FirebaseApp app = await settle(tester, newApp());
        final FirebaseRemoteConfig remoteConfig =
            FirebaseRemoteConfig.instanceFor(app: app);
        await settle(
          tester,
          remoteConfig.setConfigSettings(
            RemoteConfigSettings(
              fetchTimeout: const Duration(seconds: 1),
              minimumFetchInterval: Duration.zero,
            ),
          ),
        );
        final Completer<void> gate = backend.fetchGate = Completer<void>();
        final Future<void> fetch = remoteConfig.fetch();
        final Future<void> expectation = expectLater(
          fetch,
          throwsRemoteConfigCode('network-error'),
        );
        await settle(tester, fetch.catchError((Object _) {}));
        await expectation;
        expect(backend.fetches, hasLength(1), reason: 'the request was sent');
        expect(remoteConfig.lastFetchStatus, RemoteConfigFetchStatus.failure);

        gate.complete();
        await deleteApp(tester, app);
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );

    testWidgets('5.12 installations-error caused by network-error becomes '
        'network-error', (WidgetTester tester) async {
      freshStore();
      final FirebaseApp app = await settle(tester, newApp());
      backend.installationsUnreachable = true;
      final Future<void> fetch = FirebaseRemoteConfig.instanceFor(
        app: app,
      ).fetch();
      final Future<void> expectation = expectLater(
        fetch,
        throwsRemoteConfigCode('network-error'),
      );
      // Installations retries once after 1 s.
      await settle(tester, fetch.catchError((Object _) {}));
      await expectation;
      expect(backend.to(installationsHost), hasLength(2));
      expect(backend.fetches, isEmpty);

      await deleteApp(tester, app);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test(
      '5.12 installations-error with another cause becomes internal',
      () async {
        final FirebaseApp app = await newApp();
        backend.installationsStatus = 403;
        await expectLater(
          FirebaseRemoteConfig.instanceFor(app: app).fetch(),
          throwsRemoteConfigCode('internal'),
        );
        expect(backend.fetches, isEmpty);
      },
    );

    test('5.12 a 429 (fetch-throttle) becomes throttled; the next fetch '
        'inside the window is throttled and sends nothing', () async {
      final FirebaseApp app = await newApp();
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      backend.fetchStatus = 429;
      await expectLater(
        remoteConfig.fetch(),
        throwsRemoteConfigCode('throttled'),
      );
      backend.fetchStatus = null;
      await expectLater(
        remoteConfig.fetch(),
        throwsRemoteConfigCode('throttled'),
      );
      expect(backend.fetches, hasLength(1));
    });

    test(
      '5.12 a 503 (fetch-status with throttledUntil) becomes throttled',
      () async {
        final FirebaseApp app = await newApp();
        backend.fetchStatus = 503;
        await expectLater(
          FirebaseRemoteConfig.instanceFor(app: app).fetch(),
          throwsRemoteConfigCode('throttled'),
        );
      },
    );

    test('5.12 a 403 becomes forbidden', () async {
      final FirebaseApp app = await newApp();
      backend.fetchStatus = 403;
      await expectLater(
        FirebaseRemoteConfig.instanceFor(app: app).fetch(),
        throwsRemoteConfigCode('forbidden'),
      );
    });

    test(
      '5.12 another status (500, 400) becomes remote-config-server-error',
      () async {
        final FirebaseApp app = await newApp();
        final FirebaseRemoteConfig remoteConfig =
            FirebaseRemoteConfig.instanceFor(app: app);
        await remoteConfig.setConfigSettings(_noCache);
        backend.fetchStatus = 500;
        await expectLater(
          remoteConfig.fetch(),
          throwsRemoteConfigCode('remote-config-server-error'),
        );
        backend.fetchStatus = 400;
        await expectLater(
          remoteConfig.fetchAndActivate(),
          throwsRemoteConfigCode('remote-config-server-error'),
        );
      },
    );

    test('5.12 a store in use by another process: internal with the store\'s '
        'message', () async {
      final FirebaseApp app = await newApp();
      store.failure = FailingStore.inUse;
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await expectLater(
        remoteConfig.ensureInitialized(),
        throwsA(
          isRemoteConfigCode('internal').having(
            (FirebaseException e) => e.message,
            'message',
            FailingStore.inUse.message,
          ),
        ),
      );
      await expectLater(
        remoteConfig.fetch(),
        throwsA(
          isRemoteConfigCode('internal').having(
            (FirebaseException e) => e.message,
            'message',
            FailingStore.inUse.message,
          ),
        ),
      );
      expect(backend.requests, isEmpty);
    });

    test('5.12 options Remote Config cannot use: the calls throw internal, the '
        'reads answer from the defaults, nothing sent', () async {
      final FirebaseApp app = await newApp(
        appOptions: const FirebaseOptions(
          apiKey: apiKey,
          appId: '1:1:web:1',
          messagingSenderId: '1',
          projectId: '',
        ),
      );
      final FirebaseRemoteConfig remoteConfig =
          FirebaseRemoteConfig.instanceFor(app: app);
      await expectLater(
        remoteConfig.fetch(),
        throwsRemoteConfigCode('internal'),
      );
      await remoteConfig.setDefaults(<String, dynamic>{'greeting': 'hi'});
      expect(remoteConfig.getString('greeting'), 'hi');
      expect(remoteConfig.getString('missing'), '');
      expect(remoteConfig.lastFetchStatus, RemoteConfigFetchStatus.noFetchYet);
      expect(backend.requests, isEmpty);
    });
  });
}

/// Settings that let every fetch reach the backend.
final RemoteConfigSettings _noCache = RemoteConfigSettings(
  fetchTimeout: const Duration(seconds: 60),
  minimumFetchInterval: Duration.zero,
);
