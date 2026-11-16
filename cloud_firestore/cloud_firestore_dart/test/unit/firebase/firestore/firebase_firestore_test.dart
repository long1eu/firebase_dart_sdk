// Asking for an instance again with other settings, ported from:
// - the Android SDK's FirebaseFirestoreTest (src/test, package root), where
//   setFirestoreSettings() after the start throws an IllegalStateException;
// - the JS SDK's test/integration/api/provider.test.ts (initializeFirestore()
//   twice) and the FirestoreSettings cases of
//   test/integration/api/validation.test.ts (connectFirestoreEmulator() after
//   use).
//
// Dart has no settings setter and no useEmulator(): the settings, emulator
// included, are passed to Firestore.instanceFor, so "setting them again" is a
// later instanceFor call with settings. A different value throws a
// StateError, the same value returns the existing instance. The instances use
// loopback settings, so nothing here reaches a network.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

const String _alreadyStarted =
    'FirebaseFirestore.instanceFor() has already been called with different settings '
    'for this app and database. Call it without settings to get the existing '
    'instance, or terminate() that instance first.';

Matcher get throwsAlreadyStarted => throwsA(
  isA<StateError>().having(
    (StateError e) => e.message,
    'message',
    _alreadyStarted,
  ),
);

/// Settings that point at a port nothing listens on.
Settings loopback({int port = 1}) =>
    Settings(host: '127.0.0.1', port: port, sslEnabled: false);

void main() {
  checkTestsLeaveNothingBehind();

  FirebaseApp newApp(String name) {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'fake-api-key',
        appId: '1:1234567890:dart:test',
        projectId: 'test-project',
      ),
      dependencies: null,
      name: name,
    );
    addTearDown(app.delete);
    return app;
  }

  FirebaseFirestore instanceFor(
    FirebaseApp app, {
    String database = '(default)',
    Settings? settings,
  }) {
    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: app,
      databaseId: database,
      settings: settings,
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  /// Uses [firestore] without a backend, like the first call that starts an
  /// instance upstream.
  Future<void> use(FirebaseFirestore firestore) async {
    await firestore.collection('foo').get(GetOptions(source: Source.cache));
  }

  group('FirebaseFirestoreTest', () {
    test('getInstance_withEmulator', () {
      final FirebaseApp app = newApp('getInstance_withEmulator');

      final FirebaseFirestore firestore = instanceFor(
        app,
        settings: Settings().withEmulator('10.0.2.2', 8080),
      );
      final Settings settings = firestore.settings;

      expect('${settings.host}:${settings.port}', '10.0.2.2:8080');
      expect(settings.sslEnabled, isFalse);
    });

    // Android merges the emulator host into settings set later; here both
    // are one value.
    test('getInstance_withEmulator_mergeSettingsSuccess', () {
      final FirebaseApp app = newApp(
        'getInstance_withEmulator_mergeSettingsSuccess',
      );

      final FirebaseFirestore firestore = instanceFor(
        app,
        settings: Settings(
          cacheSettings: const MemoryCacheSettings(),
        ).withEmulator('10.0.2.2', 8080),
      );
      final Settings settings = firestore.settings;

      expect('${settings.host}:${settings.port}', '10.0.2.2:8080');
      expect(settings.sslEnabled, isFalse);
      expect(settings.persistenceEnabled, isFalse);
    });

    test('getInstance_withEmulator_lateFailure', () {
      final FirebaseApp app = newApp('getInstance_withEmulator_lateFailure');

      final FirebaseFirestore firestore = instanceFor(
        app,
        settings: loopback(),
      );
      firestore.collection('foo');

      expect(
        () => FirebaseFirestore.instanceFor(
          app: app,
          settings: Settings().withEmulator('10.0.2.2', 8080),
        ),
        throwsAlreadyStarted,
      );
    });

    test('setSettings_repeatedSuccess', () async {
      final FirebaseApp app = newApp('setSettings_repeatedSuccess');
      final Settings settings = loopback();
      final FirebaseFirestore firestore = instanceFor(app, settings: settings);

      // This should 'start' Firestore
      await use(firestore);

      // Second settings set should pass because the settings are equal
      expect(
        FirebaseFirestore.instanceFor(app: app, settings: settings),
        same(firestore),
      );
      expect(
        FirebaseFirestore.instanceFor(app: app, settings: loopback()),
        same(firestore),
      );
    });

    test('setSettings_repeatedSuccess_withEmulator', () async {
      final FirebaseApp app = newApp(
        'setSettings_repeatedSuccess_withEmulator',
      );
      Settings settings() => Settings(
        cacheSettings: const MemoryCacheSettings(),
      ).withEmulator('127.0.0.1', 1);
      final FirebaseFirestore firestore = instanceFor(
        app,
        settings: settings(),
      );

      // This should 'start' Firestore
      await use(firestore);

      // Second settings set should pass because the settings are equal
      expect(
        FirebaseFirestore.instanceFor(app: app, settings: settings()),
        same(firestore),
      );
    });

    test('setSettings_repeatedFailure', () async {
      final FirebaseApp app = newApp('setSettings_repeatedFailure');
      final Settings settings = loopback();
      final Settings otherSettings = loopback(port: 2);
      final FirebaseFirestore firestore = instanceFor(app, settings: settings);

      // This should 'start' Firestore
      await use(firestore);

      expect(
        () => FirebaseFirestore.instanceFor(app: app, settings: otherSettings),
        throwsAlreadyStarted,
      );
      // The instance keeps the settings it was created with.
      expect(firestore.settings, settings);
    });
  });

  group('Firestore Provider', () {
    test('can provide setting', () {
      final FirebaseApp app = newApp('test-app-initializeFirestore');
      final FirebaseFirestore fs1 = instanceFor(app, settings: loopback());
      expect(fs1, isA<FirebaseFirestore>());
    });

    test('returns same default instance from named app', () {
      final FirebaseApp app = newApp('test-app-getFirestore');
      final FirebaseFirestore fs1 = instanceFor(app, settings: loopback());
      final FirebaseFirestore fs2 = FirebaseFirestore.instanceFor(app: app);
      final FirebaseFirestore fs3 = FirebaseFirestore.instanceFor(
        app: app,
        databaseId: '(default)',
      );
      expect(fs1, same(fs2));
      expect(fs1, same(fs3));
    });

    test('returns different instance from named app', () {
      final FirebaseApp app = newApp('test-app-getFirestore');
      final FirebaseFirestore fs1 = instanceFor(
        app,
        database: 'init1',
        settings: loopback(),
      );
      final FirebaseFirestore fs2 = instanceFor(
        app,
        database: 'init2',
        settings: loopback(),
      );
      final FirebaseFirestore fs3 = instanceFor(app, settings: loopback());

      expect(fs1.databaseId, 'init1');
      expect(fs2.databaseId, 'init2');
      expect(fs3.databaseId, '(default)');
      expect(fs1, isNot(same(fs2)));
      expect(fs1, isNot(same(fs3)));
      expect(fs2, isNot(same(fs3)));
    });

    test('returns different instance from different named app', () {
      final FirebaseFirestore fs1 = instanceFor(
        newApp('test-app-getFirestore-1'),
        settings: loopback(),
      );
      final FirebaseFirestore fs2 = instanceFor(
        newApp('test-app-getFirestore-2'),
        settings: loopback(),
      );
      expect(fs1, isNot(same(fs2)));
    });

    test('can call initializeFirestore() twice if settings are same', () {
      final FirebaseApp app = newApp('test-app-initializeFirestore-twice');
      final FirebaseFirestore fs1 = instanceFor(app, settings: loopback());
      final FirebaseFirestore fs2 = FirebaseFirestore.instanceFor(
        app: app,
        settings: loopback(),
      );
      expect(fs1, same(fs2));
    });

    // The JS SDK's message: "initializeFirestore() has already been called
    // with different options. ...".
    test('cannot call initializeFirestore() twice with different options', () {
      final FirebaseApp app = newApp('test-app-initializeFirestore-different');
      instanceFor(app, settings: loopback());
      expect(
        () => FirebaseFirestore.instanceFor(
          app: app,
          settings: loopback(port: 2),
        ),
        throwsAlreadyStarted,
      );
    });

    test(
      'a terminated instance can be created again with other settings',
      () async {
        final FirebaseApp app = newApp('test-app-terminated');
        final FirebaseFirestore fs1 = FirebaseFirestore.instanceFor(
          app: app,
          settings: loopback(),
        );
        await fs1.terminate();
        final FirebaseFirestore fs2 = instanceFor(
          app,
          settings: loopback(port: 2),
        );
        expect(fs2, isNot(same(fs1)));
        expect(fs2.settings.port, 2);
      },
    );
  });

  group('FirestoreSettings', () {
    test('disallows changing settings after use', () async {
      final FirebaseApp app = newApp('disallows-changing-settings');
      final FirebaseFirestore db = instanceFor(app, settings: loopback());
      await use(db);
      expect(
        () => FirebaseFirestore.instanceFor(
          app: app,
          settings: Settings().withEmulator('something-else.example.com', 8080),
        ),
        throwsAlreadyStarted,
      );
    });

    test('connectFirestoreEmulator() can set host and port', () {
      final FirebaseApp app = newApp('emulator-host-and-port');
      // Verify that this doesn't throw.
      instanceFor(app, settings: Settings().withEmulator('127.0.0.1', 9000));
    });

    test('connectFirestoreEmulator() can set mockUserToken object', () {
      final FirebaseApp app = newApp('emulator-mock-user-token');
      // Verify that this doesn't throw.
      instanceFor(
        app,
        settings: Settings().withEmulator(
          '127.0.0.1',
          9000,
          mockUserToken: <String, Object?>{'sub': 'foo'},
        ),
      );
    });

    test(
      'disallows calling connectFirestoreEmulator() for first time after use',
      () async {
        final FirebaseApp app = newApp('emulator-first-time-after-use');
        final FirebaseFirestore db = instanceFor(app, settings: loopback());
        await use(db);
        expect(
          () => FirebaseFirestore.instanceFor(
            app: app,
            settings: Settings().withEmulator('127.0.0.1', 9000),
          ),
          throwsAlreadyStarted,
        );
      },
    );

    test(
      'allows calling connectFirestoreEmulator() after use with same config',
      () async {
        final FirebaseApp app = newApp('emulator-same-config');
        final FirebaseFirestore db = instanceFor(
          app,
          settings: Settings().withEmulator('127.0.0.1', 1),
        );
        await use(db);
        expect(
          FirebaseFirestore.instanceFor(
            app: app,
            settings: Settings().withEmulator('127.0.0.1', 1),
          ),
          same(db),
        );
      },
    );

    test(
      'disallows calling connectFirestoreEmulator() after use with different '
      'config',
      () async {
        final FirebaseApp app = newApp('emulator-different-config');
        final FirebaseFirestore db = instanceFor(
          app,
          settings: Settings().withEmulator('127.0.0.1', 1),
        );
        await use(db);
        expect(
          () => FirebaseFirestore.instanceFor(
            app: app,
            settings: Settings().withEmulator('127.0.0.1', 2),
          ),
          throwsAlreadyStarted,
        );
      },
    );
  });
}
