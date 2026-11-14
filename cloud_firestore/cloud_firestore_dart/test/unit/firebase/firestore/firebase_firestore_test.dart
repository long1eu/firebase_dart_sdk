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
import 'package:cloud_firestore_dart/src/firebase/firestore/firestore.dart'
    show FirestoreInternal;
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';

import '../../../util/test_hygiene.dart';

const String _alreadyStarted =
    'Firestore.instanceFor() has already been called with different settings '
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
FirestoreSettings loopback({int port = 1}) =>
    FirestoreSettings(host: '127.0.0.1', port: port, sslEnabled: false);

void main() {
  checkTestsLeaveNothingBehind();

  FirebaseApp newApp(String name) {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'fake-api-key',
        applicationId: '1:1234567890:dart:test',
        projectId: 'test-project',
      ),
      dependencies: null,
      name: name,
    );
    addTearDown(app.delete);
    return app;
  }

  Firestore instanceFor(
    FirebaseApp app, {
    String database = '(default)',
    FirestoreSettings? settings,
  }) {
    final Firestore firestore = Firestore.instanceFor(
      app: app,
      database: database,
      settings: settings,
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  /// Uses [firestore] without a backend, like the first call that starts an
  /// instance upstream.
  Future<void> use(Firestore firestore) async {
    await firestore.collection('foo').get(Source.cache);
  }

  group('FirebaseFirestoreTest', () {
    test('getInstance_withEmulator', () {
      final FirebaseApp app = newApp('getInstance_withEmulator');

      final Firestore firestore = instanceFor(
        app,
        settings: FirestoreSettings().withEmulator('10.0.2.2', 8080),
      );
      final FirestoreSettings settings = firestore.settings;

      expect('${settings.host}:${settings.port}', '10.0.2.2:8080');
      expect(settings.sslEnabled, isFalse);
    });

    // Android merges the emulator host into settings set later; here both
    // are one value.
    test('getInstance_withEmulator_mergeSettingsSuccess', () {
      final FirebaseApp app = newApp(
        'getInstance_withEmulator_mergeSettingsSuccess',
      );

      final Firestore firestore = instanceFor(
        app,
        settings: FirestoreSettings(
          cacheSettings: const MemoryCacheSettings(),
        ).withEmulator('10.0.2.2', 8080),
      );
      final FirestoreSettings settings = firestore.settings;

      expect('${settings.host}:${settings.port}', '10.0.2.2:8080');
      expect(settings.sslEnabled, isFalse);
      expect(settings.persistenceEnabled, isFalse);
    });

    test('getInstance_withEmulator_lateFailure', () {
      final FirebaseApp app = newApp('getInstance_withEmulator_lateFailure');

      final Firestore firestore = instanceFor(app, settings: loopback());
      firestore.collection('foo');

      expect(
        () => Firestore.instanceFor(
          app: app,
          settings: FirestoreSettings().withEmulator('10.0.2.2', 8080),
        ),
        throwsAlreadyStarted,
      );
    });

    test('setSettings_repeatedSuccess', () async {
      final FirebaseApp app = newApp('setSettings_repeatedSuccess');
      final FirestoreSettings settings = loopback();
      final Firestore firestore = instanceFor(app, settings: settings);

      // This should 'start' Firestore
      await use(firestore);

      // Second settings set should pass because the settings are equal
      expect(
        Firestore.instanceFor(app: app, settings: settings),
        same(firestore),
      );
      expect(
        Firestore.instanceFor(app: app, settings: loopback()),
        same(firestore),
      );
    });

    test('setSettings_repeatedSuccess_withEmulator', () async {
      final FirebaseApp app = newApp(
        'setSettings_repeatedSuccess_withEmulator',
      );
      FirestoreSettings settings() => FirestoreSettings(
        cacheSettings: const MemoryCacheSettings(),
      ).withEmulator('127.0.0.1', 1);
      final Firestore firestore = instanceFor(app, settings: settings());

      // This should 'start' Firestore
      await use(firestore);

      // Second settings set should pass because the settings are equal
      expect(
        Firestore.instanceFor(app: app, settings: settings()),
        same(firestore),
      );
    });

    test('setSettings_repeatedFailure', () async {
      final FirebaseApp app = newApp('setSettings_repeatedFailure');
      final FirestoreSettings settings = loopback();
      final FirestoreSettings otherSettings = loopback(port: 2);
      final Firestore firestore = instanceFor(app, settings: settings);

      // This should 'start' Firestore
      await use(firestore);

      expect(
        () => Firestore.instanceFor(app: app, settings: otherSettings),
        throwsAlreadyStarted,
      );
      // The instance keeps the settings it was created with.
      expect(firestore.settings, settings);
    });
  });

  group('Firestore Provider', () {
    test('can provide setting', () {
      final FirebaseApp app = newApp('test-app-initializeFirestore');
      final Firestore fs1 = instanceFor(app, settings: loopback());
      expect(fs1, isA<Firestore>());
    });

    test('returns same default instance from named app', () {
      final FirebaseApp app = newApp('test-app-getFirestore');
      final Firestore fs1 = instanceFor(app, settings: loopback());
      final Firestore fs2 = Firestore.instanceFor(app: app);
      final Firestore fs3 = Firestore.instanceFor(
        app: app,
        database: '(default)',
      );
      expect(fs1, same(fs2));
      expect(fs1, same(fs3));
    });

    test('returns different instance from named app', () {
      final FirebaseApp app = newApp('test-app-getFirestore');
      final Firestore fs1 = instanceFor(
        app,
        database: 'init1',
        settings: loopback(),
      );
      final Firestore fs2 = instanceFor(
        app,
        database: 'init2',
        settings: loopback(),
      );
      final Firestore fs3 = instanceFor(app, settings: loopback());

      expect(fs1.databaseId, 'init1');
      expect(fs2.databaseId, 'init2');
      expect(fs3.databaseId, '(default)');
      expect(fs1, isNot(same(fs2)));
      expect(fs1, isNot(same(fs3)));
      expect(fs2, isNot(same(fs3)));
    });

    test('returns different instance from different named app', () {
      final Firestore fs1 = instanceFor(
        newApp('test-app-getFirestore-1'),
        settings: loopback(),
      );
      final Firestore fs2 = instanceFor(
        newApp('test-app-getFirestore-2'),
        settings: loopback(),
      );
      expect(fs1, isNot(same(fs2)));
    });

    test('can call initializeFirestore() twice if settings are same', () {
      final FirebaseApp app = newApp('test-app-initializeFirestore-twice');
      final Firestore fs1 = instanceFor(app, settings: loopback());
      final Firestore fs2 = Firestore.instanceFor(
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
        () => Firestore.instanceFor(app: app, settings: loopback(port: 2)),
        throwsAlreadyStarted,
      );
    });

    test(
      'a terminated instance can be created again with other settings',
      () async {
        final FirebaseApp app = newApp('test-app-terminated');
        final Firestore fs1 = Firestore.instanceFor(
          app: app,
          settings: loopback(),
        );
        await fs1.terminate();
        final Firestore fs2 = instanceFor(app, settings: loopback(port: 2));
        expect(fs2, isNot(same(fs1)));
        expect(fs2.settings.port, 2);
      },
    );
  });

  group('FirestoreSettings', () {
    test('disallows changing settings after use', () async {
      final FirebaseApp app = newApp('disallows-changing-settings');
      final Firestore db = instanceFor(app, settings: loopback());
      await use(db);
      expect(
        () => Firestore.instanceFor(
          app: app,
          settings: FirestoreSettings().withEmulator(
            'something-else.example.com',
            8080,
          ),
        ),
        throwsAlreadyStarted,
      );
    });

    test('connectFirestoreEmulator() can set host and port', () {
      final FirebaseApp app = newApp('emulator-host-and-port');
      // Verify that this doesn't throw.
      instanceFor(
        app,
        settings: FirestoreSettings().withEmulator('127.0.0.1', 9000),
      );
    });

    test('connectFirestoreEmulator() can set mockUserToken object', () {
      final FirebaseApp app = newApp('emulator-mock-user-token');
      // Verify that this doesn't throw.
      instanceFor(
        app,
        settings: FirestoreSettings().withEmulator(
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
        final Firestore db = instanceFor(app, settings: loopback());
        await use(db);
        expect(
          () => Firestore.instanceFor(
            app: app,
            settings: FirestoreSettings().withEmulator('127.0.0.1', 9000),
          ),
          throwsAlreadyStarted,
        );
      },
    );

    test(
      'allows calling connectFirestoreEmulator() after use with same config',
      () async {
        final FirebaseApp app = newApp('emulator-same-config');
        final Firestore db = instanceFor(
          app,
          settings: FirestoreSettings().withEmulator('127.0.0.1', 1),
        );
        await use(db);
        expect(
          Firestore.instanceFor(
            app: app,
            settings: FirestoreSettings().withEmulator('127.0.0.1', 1),
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
        final Firestore db = instanceFor(
          app,
          settings: FirestoreSettings().withEmulator('127.0.0.1', 1),
        );
        await use(db);
        expect(
          () => Firestore.instanceFor(
            app: app,
            settings: FirestoreSettings().withEmulator('127.0.0.1', 2),
          ),
          throwsAlreadyStarted,
        );
      },
    );
  });
}
