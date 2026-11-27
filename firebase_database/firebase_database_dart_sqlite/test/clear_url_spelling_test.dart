// clearSqlitePersistence deletes the cache a FirebaseDatabase opened, whatever spelling of the
// database URL it is given: both normalise through persistenceDatabaseUrl of the client.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:test/test.dart';

import 'support/store_fixture.dart';

int _apps = 0;

void main() {
  late StoreFixture fixture;
  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  /// Opens and closes a database of a new app whose `databaseURL` is [url]; returns the app name
  /// and the path of the cache file it wrote.
  Future<(String, String)> openAndClose(String url) async {
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
    return (app.name, path);
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
        final (String appName, String path) = await openAndClose(opened);

        await clearSqlitePersistence(
          fixture.directory,
          appName: appName,
          databaseUrl: Uri.parse(cleared),
        );

        expect(File(path).existsSync(), isFalse);
      },
    );
  }

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
