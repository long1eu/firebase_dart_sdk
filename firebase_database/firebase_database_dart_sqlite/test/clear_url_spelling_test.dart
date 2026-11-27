// clearSqlitePersistence deletes the cache a FirebaseDatabase opened, whatever spelling of the
// database URL it is given: both normalise through persistenceDatabaseUrl of the client.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart/src/realtime/database_url.dart'
    show emulatorDatabase, parseEmulatorHost, persistenceUrlOf;
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:test/test.dart';

import 'support/store_fixture.dart';

int _apps = 0;

void main() {
  late StoreFixture fixture;
  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  /// Opens and closes a database of a new app whose `databaseURL` is [url]; returns the app name,
  /// the path of the cache file it wrote and its key (`FirebaseDatabase.databaseUrl`).
  Future<(String, String, Uri)> openAndClose(String url) async {
    final FirebaseApp app = FirebaseApp.withOptions(
      FirebaseOptions(
        apiKey: 'test-key',
        appId: '1:1234567890:dart:test',
        projectId: 'demo-test',
        databaseURL: url,
      ),
      name: 'spelling-${_apps++}',
    );
    final FirebaseDatabase db = databaseWithFakeServer(
      app,
      FakeDatabaseServer(),
      persistence: sqlitePersistence(fixture.directory),
    );
    // A write waits for the store to open.
    final Future<void> write = db.ref('a').set(1);
    await pumpEventQueue();
    expect(db.persistenceEnabled, isTrue);
    final String path = SqlitePersistence(
      fixture.directory,
    ).pathOf(PersistenceKey(appName: app.name, databaseUrl: db.databaseUrl));
    final Future<void> closed = expectLater(
      write,
      throwsA(isA<FirebaseDatabaseException>()),
    );
    await db.close();
    await closed;
    expect(File(path).existsSync(), isTrue);
    return (app.name, path, db.databaseUrl);
  }

  const String canonical = 'https://demo-test-default-rtdb.firebaseio.com';
  for (final (String opened, String cleared) in <(String, String)>[
    (canonical, '$canonical/'),
    (canonical, 'wss://demo-test-default-rtdb.firebaseio.com'),
    (canonical, 'https://DEMO-TEST-default-rtdb.FirebaseIO.com'),
    (canonical, '$canonical/?ns=demo-test-default-rtdb'),
    (canonical, '$canonical:443'),
    (
      'https://db.example.com?ns=demo-other',
      'https://DB.example.com/?ns=Demo-Other',
    ),
  ]) {
    test(
      'a cache opened with $opened is deleted by a clear with $cleared',
      () async {
        final (String appName, String path, _) = await openAndClose(opened);

        await clearSqlitePersistence(
          fixture.directory,
          appName: appName,
          databaseUrl: Uri.parse(cleared),
        );

        expect(File(path).existsSync(), isFalse);
      },
    );
  }

  // The keys and file names (for app `[DEFAULT]`) of 4e0554ce, computed with its `_Target` code:
  // they must not change, or existing caches are orphaned. Each key also normalises to itself.
  const List<(String, String, String)> productionKeys =
      <(String, String, String)>[
        (
          'https://demo-test-default-rtdb.firebaseio.com',
          'https://demo-test-default-rtdb.firebaseio.com',
          'rtdb-d9d603a0c8607b917ac7303e34923581.sqlite',
        ),
        (
          'https://demo-test-default-rtdb.firebaseio.com?ns=other',
          'https://demo-test-default-rtdb.firebaseio.com?ns=other',
          'rtdb-0d597a1ade97c9feea03408a77009364.sqlite',
        ),
        (
          'https://x.europe-west1.firebasedatabase.app',
          'https://x.europe-west1.firebasedatabase.app',
          'rtdb-23577627767de1d30c1f07ce7b71975b.sqlite',
        ),
        (
          'https://db.example.com?ns=demo-other',
          'https://db.example.com?ns=demo-other',
          'rtdb-58f601a81bfa76eb086f1778584c0822.sqlite',
        ),
        (
          'https://chat.example.com?ns=chat',
          'https://chat.example.com',
          'rtdb-e7d6fb75ac035e9284578a3ff5650094.sqlite',
        ),
        (
          'https://localhost?ns=localhost',
          'https://localhost',
          'rtdb-eace36a8223c169bd3efdb7fb53617ca.sqlite',
        ),
        (
          'https://localhost:8443?ns=abc',
          'https://localhost:8443?ns=abc',
          'rtdb-0a58ff7b0f539315c3281c3dc629ecb8.sqlite',
        ),
        (
          'https://[::1]:8443?ns=abc',
          'https://[::1]:8443?ns=abc',
          'rtdb-0e5b524bf044bf71d0d47678fdd09b37.sqlite',
        ),
        (
          'https://demo.cloudworkstations.dev?ns=demo',
          'https://demo.cloudworkstations.dev',
          'rtdb-9807d62c60525cec211da8981fdfbc6c.sqlite',
        ),
        (
          'https://foo.cloudworkstations.dev?ns=bar',
          'https://foo.cloudworkstations.dev?ns=bar',
          'rtdb-e628e49ac8b0a3b05e69ae92c72ed6db.sqlite',
        ),
      ];
  const List<(String, String, String, String)> emulatorKeys =
      <(String, String, String, String)>[
        (
          '127.0.0.1:9000',
          'demo-test-default-rtdb',
          'http://127.0.0.1:9000?ns=demo-test-default-rtdb',
          'rtdb-25e84970ea0447da3f5f732df46b8e34.sqlite',
        ),
        (
          '[::1]:9000',
          'demo',
          'http://[::1]:9000?ns=demo',
          'rtdb-96ab436562ac7d3980fefe9b0244367e.sqlite',
        ),
        (
          'localhost:80',
          'demo',
          'http://localhost?ns=demo',
          'rtdb-4ba8392bb427b07bffc3175a2b8e16ee.sqlite',
        ),
        (
          '9000-x.cloudworkstations.dev:443',
          'demo',
          'https://9000-x.cloudworkstations.dev?ns=demo',
          'rtdb-b64c33113f545b18c526bc71fed74d84.sqlite',
        ),
        (
          '9000-x.cloudworkstations.dev:9000',
          'demo',
          'https://9000-x.cloudworkstations.dev:9000?ns=demo',
          'rtdb-cf79ae55633fbd8c8311221b60eef6af.sqlite',
        ),
        (
          'demo.cloudworkstations.dev:443',
          'demo',
          'https://demo.cloudworkstations.dev?ns=demo',
          'rtdb-5bd588babbcefc414118b26832370a52.sqlite',
        ),
      ];

  for (final (String url, String key, String file) in productionKeys) {
    test(
      '$url keeps key $key, and a clear with that key deletes its file',
      () async {
        final (String appName, String path, Uri opened) = await openAndClose(
          url,
        );
        expect(opened.toString(), key);
        expect(SqliteFiles.fileName('[DEFAULT]', opened), file);
        expect(persistenceDatabaseUrl(opened).toString(), key);

        await clearSqlitePersistence(
          fixture.directory,
          appName: appName,
          databaseUrl: opened,
        );

        expect(File(path).existsSync(), isFalse);
      },
    );
  }

  test('emulator keys are those of 4e0554ce and normalise to themselves', () {
    for (final (String hostPort, String namespace, String key, String file)
        in emulatorKeys) {
      final ({String host, int port}) address = parseEmulatorHost(hostPort);
      final Uri opened = persistenceUrlOf(
        emulatorDatabase(address.host, address.port, namespace: namespace),
      );
      expect(opened.toString(), key, reason: hostPort);
      expect(SqliteFiles.fileName('[DEFAULT]', opened), file, reason: hostPort);
      expect(persistenceDatabaseUrl(opened).toString(), key, reason: hostPort);
    }
    expect(
      persistenceDatabaseUrl(Uri.parse('ws://localhost?ns=demo')).toString(),
      'http://localhost?ns=demo',
    );
  });

  test('the emulator key is kept as it is', () {
    for (final String key in <String>[
      'http://127.0.0.1:9000?ns=demo-test-default-rtdb',
      'http://[::1]:9000?ns=demo-test-default-rtdb',
      'https://9000-x.cloudworkstations.dev?ns=demo-test-default-rtdb',
    ]) {
      expect(
        persistenceDatabaseUrl(Uri.parse(key)),
        Uri.parse(key),
        reason: key,
      );
    }
    expect(
      persistenceDatabaseUrl(Uri.parse('ws://LOCALHOST:9000/?ns=demo')),
      Uri.parse('http://localhost:9000?ns=demo'),
    );
  });

  test('a URL that is not a database URL is an ArgumentError', () async {
    await expectLater(
      clearSqlitePersistence(
        fixture.directory,
        appName: '[DEFAULT]',
        databaseUrl: Uri.parse(
          'https://demo-test-default-rtdb.firebaseio.com/a/b',
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      clearSqlitePersistence(
        fixture.directory,
        appName: '[DEFAULT]',
        databaseUrl: Uri.parse('http://127.0.0.1:9000'),
      ),
      throwsArgumentError,
    );
  });
}
