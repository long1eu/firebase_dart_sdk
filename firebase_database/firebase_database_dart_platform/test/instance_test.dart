// The instances of DartFirebaseDatabase and the settings they capture before
// their client exists.

import 'package:firebase_app_dart/firebase_app_dart.dart' as dart_app;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart' as fs;
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_platform/firebase_database_dart_platform.dart';
import 'package:firebase_database_dart_platform/src/firebase_database.dart';
import 'package:firebase_database_platform_interface/firebase_database_platform_interface.dart'
    show DatabasePlatform;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const int mebibyte = 1024 * 1024;

/// The lines of `debugPrint` during the current test.
final List<String> printed = <String>[];

/// The cache sizes the persistence factory of the current test was called
/// with.
final List<int> factoryCalls = <int>[];

/// What the persistence factory of the current test returns.
late fs.DatabasePersistence persistence;

fs.DatabasePersistence persistenceFor(int cacheSizeBytes) {
  factoryCalls.add(cacheSizeBytes);
  return persistence;
}

/// The instance behind `FirebaseDatabase.instanceFor(app: app)`.
DartFirebaseDatabase instanceOf(FirebaseApp app, {String? databaseURL}) =>
    DatabasePlatform.instanceFor(app: app, databaseURL: databaseURL)
        as DartFirebaseDatabase;

void main() {
  registerForTests();

  final DebugPrintCallback originalDebugPrint = debugPrint;
  // The configuration of registerForTests (its token providers), restored
  // after each test that changes it.
  late DartDatabaseConfig registered;
  setUpAll(() => registered = DartFirebaseDatabase.config);
  setUp(() {
    printed.clear();
    factoryCalls.clear();
    persistence = fakePersistence();
    debugPrint = (String? message, {int? wrapWidth}) =>
        printed.add(message ?? '');
  });
  tearDown(() {
    debugPrint = originalDebugPrint;
    DartFirebaseDatabase.config = registered;
  });

  void usePersistenceFactory() {
    DartFirebaseDatabase.config = DartDatabaseConfig(
      tokenProviderFor: registered.tokenProviderFor,
      appCheckProviderFor: registered.appCheckProviderFor,
      persistenceFor: persistenceFor,
    );
  }

  group('instances', () {
    test('one instance per app and database URL', () async {
      final FirebaseApp app = await newApp();

      expect(instanceOf(app), same(instanceOf(app)));
      expect(
        instanceOf(app, databaseURL: 'https://other.firebaseio.com'),
        isNot(same(instanceOf(app))),
      );
      expect(instanceOf(app).app, app);
      expect(instanceOf(app).databaseURL, isNull);
    });

    test('the registered instance has no app and no client', () {
      final DatabasePlatform registered = DatabasePlatform.instance;

      expect(registered.app, isNull);
      expect(
        () => (registered as DartFirebaseDatabase).client,
        throwsStateError,
      );
    });

    test(
      'an app deleted and created again gets a new instance and client',
      () async {
        final FirebaseApp first = await newApp();
        final String name = first.name;
        final DartFirebaseDatabase before = instanceOf(first);
        await before.goOnline();
        await first.delete();

        final FirebaseApp again = await Firebase.initializeApp(
          name: name,
          options: options,
        );
        final DartFirebaseDatabase after = instanceOf(again);
        await after.goOnline();

        expect(after, isNot(same(before)));
        expect(after.client, isNot(same(before.client)));
        expect(createdClients, hasLength(2));
      },
    );

    test('clientFor is the client of the instance', () async {
      final FirebaseApp app = await newApp();

      expect(FirebaseDatabaseDart.clientFor(app), same(instanceOf(app).client));
    });
  });

  group('the client', () {
    test('ref creates no client', () async {
      final FirebaseApp app = await newApp();

      final DatabaseReference ref = FirebaseDatabase.instanceFor(
        app: app,
      ).ref('a/b');

      expect(ref.path, isNotEmpty);
      expect(instanceOf(app).started, isFalse);
      expect(createdClients, isEmpty);
    });

    test(
      'the first operation creates one client, the next ones reuse it',
      () async {
        final FirebaseApp app = await newApp();
        final FirebaseDatabase database = FirebaseDatabase.instanceFor(
          app: app,
        );

        await database.goOnline();
        await database.goOffline();
        await database.goOnline();

        expect(instanceOf(app).started, isTrue);
        expect(createdClients, hasLength(1));
        expect(DartFirebaseDatabase.anyStarted, isTrue);
      },
    );

    test('goOffline and goOnline reach the client', () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: app);

      await database.goOffline();
      await settle();
      final bool offline = FirebaseDatabaseDart.clientFor(app).isConnected;
      await database.goOnline();
      await settle();

      expect(offline, isFalse);
      expect(FirebaseDatabaseDart.clientFor(app).isConnected, isTrue);
    });

    test(
      'purgeOutstandingWrites fails pending writes with write-cancelled',
      () async {
        final FirebaseApp app = await newApp();
        final FirebaseDatabase database = FirebaseDatabase.instanceFor(
          app: app,
        );
        final Future<void> write = database.ref('a').set(1);
        await settle();

        await database.purgeOutstandingWrites();

        await expectLater(write, throwsDatabaseCode('write-cancelled'));
      },
    );

    test('the client gets the databaseURL of instanceFor, else none', () async {
      final FirebaseApp app = await newApp();

      await FirebaseDatabase.instanceFor(app: app).goOnline();
      await FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: 'https://other.firebaseio.com',
      ).goOnline();

      expect(
        createdClients.map((DatabaseClientSettings s) => s.databaseUrl),
        <String?>[null, 'https://other.firebaseio.com'],
      );
    });

    test('the client app carries the token provider of use', () async {
      final FirebaseApp app = await newApp();
      tokens[app.name] = 'token-1';

      final dart_app.FirebaseApp dartApp = FirebaseDatabaseDart.clientFor(
        app,
      ).app;

      expect(dartApp.name, app.name);
      expect(
        dartApp.authProvider,
        isA<FixedToken>().having((FixedToken t) => t.token, 'token', 'token-1'),
      );
    });

    test(
      'the connection authenticates with the token of tokenProviderFor',
      () async {
        final FirebaseApp signedIn = await newApp();
        final FirebaseApp anonymous = await newApp();
        tokens[signedIn.name] = 'token-2';

        await FirebaseDatabase.instanceFor(app: signedIn).goOnline();
        await settle();
        final List<String?> signedInTokens = List<String?>.of(
          server.receivedAuthTokens,
        );
        await FirebaseDatabase.instanceFor(app: anonymous).goOnline();
        await settle();

        expect(signedInTokens, <String?>['token-2']);
        expect(server.receivedAuthTokens, <String?>['token-2', null]);
      },
    );
  });

  group('useDatabaseEmulator', () {
    test('before the client: the client gets host:port', () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: app);

      database.useDatabaseEmulator('localhost', 9000);
      await database.goOnline();

      expect(createdClients.single.emulatorHost, 'localhost:9000');
    });

    test('an IPv6 host is put in brackets', () async {
      final FirebaseApp app = await newApp();

      instanceOf(app).useDatabaseEmulator('::1', 9000);
      await instanceOf(app).goOnline();

      expect(createdClients.single.emulatorHost, '[::1]:9000');
    });

    test('the last call before the client wins', () async {
      final FirebaseApp app = await newApp();

      instanceOf(app)
        ..useDatabaseEmulator('localhost', 9000)
        ..useDatabaseEmulator('127.0.0.1', 9001);
      await instanceOf(app).goOnline();

      expect(createdClients.single.emulatorHost, '127.0.0.1:9001');
    });

    test(
      'after the client: the same host is accepted, another throws',
      () async {
        final FirebaseApp app = await newApp();
        final FirebaseDatabase database = FirebaseDatabase.instanceFor(
          app: app,
        );
        database.useDatabaseEmulator('localhost', 9000);
        await database.goOnline();

        database.useDatabaseEmulator('localhost', 9000);

        expect(
          () => database.useDatabaseEmulator('localhost', 9001),
          throwsStateError,
        );
        expect(createdClients, hasLength(1));
      },
    );
  });

  group('persistence', () {
    test(
      'with a factory and no setting: on, with 10 MiB, called once',
      () async {
        usePersistenceFactory();
        final FirebaseApp app = await newApp();

        await instanceOf(app).goOnline();
        await instanceOf(app).goOffline();

        expect(factoryCalls, <int>[10 * mebibyte]);
        expect(createdClients.single.persistence, same(persistence));
      },
    );

    test('the cache size set before the client goes to the factory', () async {
      usePersistenceFactory();
      final FirebaseApp app = await newApp();
      final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: app);

      database.setPersistenceCacheSizeBytes(5 * mebibyte);
      await database.goOnline();

      expect(factoryCalls, <int>[5 * mebibyte]);
    });

    test('setPersistenceEnabled(false) keeps the client in memory', () async {
      usePersistenceFactory();
      final FirebaseApp app = await newApp();
      final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: app);

      database.setPersistenceEnabled(false);
      await database.goOnline();

      expect(factoryCalls, isEmpty);
      expect(createdClients.single.persistence, isNull);
    });

    test(
      'without a factory: memory, and setPersistenceEnabled(true) warns',
      () async {
        final FirebaseApp app = await newApp();
        final FirebaseDatabase database = FirebaseDatabase.instanceFor(
          app: app,
        );

        database.setPersistenceEnabled(true);
        await database.goOnline();

        expect(createdClients.single.persistence, isNull);
        expect(printed, hasLength(1));
        expect(printed.single, contains('persistenceFor'));
      },
    );

    test('a cache size outside 1 MiB to 100 MiB is an ArgumentError', () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: app);

      expect(
        () => database.setPersistenceCacheSizeBytes(mebibyte - 1),
        throwsArgumentError,
      );
      expect(
        () => database.setPersistenceCacheSizeBytes(100 * mebibyte + 1),
        throwsArgumentError,
      );
      database
        ..setPersistenceCacheSizeBytes(mebibyte)
        ..setPersistenceCacheSizeBytes(100 * mebibyte);
    });

    test(
      'after the client: settings are ignored with one line, never thrown',
      () async {
        usePersistenceFactory();
        final FirebaseApp app = await newApp();
        final FirebaseDatabase database = FirebaseDatabase.instanceFor(
          app: app,
        );
        await database.goOnline();

        database
          ..setPersistenceEnabled(true)
          ..setPersistenceCacheSizeBytes(10 * mebibyte)
          ..setPersistenceEnabled(false)
          ..setPersistenceCacheSizeBytes(mebibyte)
          ..setPersistenceCacheSizeBytes(100 * mebibyte);

        expect(printed, hasLength(3), reason: 'the same values print nothing');
        expect(factoryCalls, <int>[10 * mebibyte]);
        expect(createdClients, hasLength(1));
        expect(
          () => database.setPersistenceCacheSizeBytes(0),
          throwsArgumentError,
        );
      },
    );
  });

  group('setLoggingEnabled', () {
    test('the logger prints only while logging is on, at any time', () async {
      final FirebaseApp app = await newApp();
      final FirebaseDatabase database = FirebaseDatabase.instanceFor(app: app);
      await database.goOnline();
      final fs.DatabaseLogger logger = createdClients.single.logger;

      logger(fs.DatabaseLogLevel.info, 'off');
      database.setLoggingEnabled(true);
      logger(fs.DatabaseLogLevel.warning, 'on');
      database.setLoggingEnabled(false);
      logger(fs.DatabaseLogLevel.info, 'off again');

      expect(printed, <String>['[firebase_database] warning: on']);
    });
  });
}
