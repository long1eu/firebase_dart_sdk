// The opener on the Dart VM, through the public API, against a Firestore
// emulator:
//
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8090 dart test test/native_opener_test.dart
//
// Without FIRESTORE_EMULATOR_HOST the tests that need the emulator skip
// themselves.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/cloud_firestore_dart_sqlite.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

typedef Json = Map<String, Object?>;

final String? emulator = Platform.environment['FIRESTORE_EMULATOR_HOST'];
final String? skipWithoutEmulator = emulator == null
    ? 'FIRESTORE_EMULATOR_HOST is not set'
    : null;

int _apps = 0;

/// A new app and client on the cache in [directory]. [appName] picks the cache:
/// the same name opens the same file again.
FirebaseFirestore client(String directory, String appName) {
  final List<String> hostPort = emulator!.split(':');
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:dart:sqlite',
      projectId: 'demo-test',
    ),
    name: appName,
  );
  return FirebaseFirestore.instanceFor(
    app: app,
    openDatabase: sqliteOpener(directory: directory),
    settings: Settings(
      cacheSettings: PersistentCacheSettings(),
    ).withEmulator(hostPort[0], int.parse(hostPort[1])),
  );
}

Future<void> shutDown(FirebaseFirestore firestore) async {
  await firestore.terminate();
  await firestore.app.delete();
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fds_sqlite_test_');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('without a directory the VM opener is an ArgumentError', () {
    expect(() => sqliteOpener(), throwsArgumentError);
  });

  test(
    'acknowledged and pending writes are read back from disk after a restart',
    () async {
      final String appName =
          'sqlite-$pid-${DateTime.now().microsecondsSinceEpoch}-${_apps++}';
      final String collection = 'sqlite_package_${_apps++}_$pid';

      FirebaseFirestore firestore = client(directory.path, appName);
      await firestore.collection(collection).doc('synced').set(
        <String, Object?>{'n': 1},
      );
      // Written offline: only in the mutation queue.
      await firestore.disableNetwork();
      unawaited(
        firestore.collection(collection).doc('pending').set(<String, Object?>{
          'n': 2,
        }),
      );
      expect(
        (await firestore
                .collection(collection)
                .doc('pending')
                .get(const GetOptions(source: Source.cache)))
            .data(),
        <String, Object?>{'n': 2},
      );
      await shutDown(firestore);

      final List<String> files = directory
          .listSync()
          .map((FileSystemEntity e) => e.uri.pathSegments.last)
          .where((String name) => name.endsWith('.db'))
          .toList();
      expect(files, hasLength(1));

      // The same app name opens the same file. Offline: nothing can come from
      // the backend.
      firestore = client(directory.path, appName);
      await firestore.disableNetwork();
      final QuerySnapshot<Json> cached = await firestore
          .collection(collection)
          .orderBy('n')
          .get(const GetOptions(source: Source.cache));
      expect(cached.metadata.isFromCache, isTrue);
      expect(
        cached.docs.map((QueryDocumentSnapshot<Json> d) => d.data()).toList(),
        <Json>[
          <String, Object?>{'n': 1},
          <String, Object?>{'n': 2},
        ],
      );
      final DocumentSnapshot<Json> pending = await firestore
          .collection(collection)
          .doc('pending')
          .get(const GetOptions(source: Source.cache));
      expect(pending.metadata.hasPendingWrites, isTrue);

      // Back online, the pending write is sent.
      await firestore.enableNetwork();
      await firestore.waitForPendingWrites();
      await shutDown(firestore);

      // clearPersistence deletes the file of the terminated instance.
      firestore = client(directory.path, appName);
      // Any read waits until the cache is open.
      await firestore
          .collection(collection)
          .doc('synced')
          .get(const GetOptions(source: Source.cache));
      await firestore.terminate();
      await firestore.clearPersistence();
      await firestore.app.delete();
      expect(
        directory.listSync().where(
          (FileSystemEntity e) => e.path.endsWith('.db'),
        ),
        isEmpty,
      );
    },
    skip: skipWithoutEmulator,
  );

  test('pageCacheMb sets the page cache of the connection', () async {
    final Database db = await sqliteOpener(
      directory: directory.path,
      pageCacheMb: 16,
    )('sized', version: 1);
    addTearDown(db.close);
    expect(await db.query('PRAGMA cache_size'), <Json>[
      <String, Object?>{'cache_size': -16 * 1024},
    ]);
  });

  test('the schema callbacks run in order and the version is stored', () async {
    final List<String> calls = <String>[];
    final OpenDatabase open = sqliteOpener(directory: directory.path);
    Database db = await open(
      'versions',
      version: 2,
      onConfigure: (_) async => calls.add('configure'),
      onCreate: (_, int v) async => calls.add('create $v'),
      onOpen: (_) async => calls.add('open'),
    );
    db.close();
    db = await open(
      'versions',
      version: 3,
      onUpgrade: (_, int from, int to) async => calls.add('upgrade $from $to'),
    );
    expect(await db.query('PRAGMA user_version'), <Json>[
      <String, Object?>{'user_version': 3},
    ]);
    db.close();
    expect(calls, <String>['configure', 'create 2', 'open', 'upgrade 2 3']);
  });

  test('a database locked by another connection is transient', () async {
    final Database db = await sqliteOpener(directory: directory.path)(
      'locked',
      version: 1,
    );
    addTearDown(db.close);
    await db.execute('CREATE TABLE t (a INTEGER)');
    final sqlite.Database other = sqlite.sqlite3.open(
      '${directory.path}/locked.db',
    );
    // ignore: deprecated_member_use
    addTearDown(other.dispose);
    other.execute('BEGIN IMMEDIATE');
    other.execute('INSERT INTO t VALUES (1)');

    await expectLater(
      db.execute('BEGIN IMMEDIATE'),
      throwsA(isA<TransientDatabaseException>()),
    );

    other.execute('COMMIT');
    await db.execute('BEGIN IMMEDIATE');
    await db.execute('COMMIT');
    expect(await db.query('SELECT a FROM t'), hasLength(1));
  });

  test(
    'statements with arguments run again, also after a schema change',
    () async {
      final Database db = await sqliteOpener(directory: directory.path)(
        'cached',
        version: 1,
      );
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (a INTEGER PRIMARY KEY, b TEXT)');
      const String insert = 'INSERT INTO t (a, b) VALUES (?, ?)';
      await db.execute(insert, <Object?>[1, 'x']);
      await db.execute(insert, <Object?>[2, 'x']);
      await db.execute(insert, <Object?>[3, 'y']);
      await expectLater(
        db.execute(insert, <Object?>[1, 'duplicate']),
        throwsA(isA<sqlite.SqliteException>()),
      );

      await db.execute('ALTER TABLE t ADD COLUMN c INTEGER DEFAULT 7');
      await db.execute(insert, <Object?>[4, 'x']);
      expect(
        await db.query('SELECT a, c FROM t WHERE b = ? ORDER BY a', <Object?>[
          'x',
        ]),
        <Json>[
          <String, Object?>{'a': 1, 'c': 7},
          <String, Object?>{'a': 2, 'c': 7},
          <String, Object?>{'a': 4, 'c': 7},
        ],
      );

      const String delete = 'DELETE FROM t WHERE b = ?';
      expect(await db.delete(delete, <Object?>['x']), 3);
      expect(await db.delete(delete, <Object?>['x']), 0);
      expect(await db.delete('DELETE FROM t'), 1);
    },
  );

  test('other SQLite errors are not transient', () async {
    final Database db = await sqliteOpener(directory: directory.path)(
      'syntax',
      version: 1,
    );
    addTearDown(db.close);
    await expectLater(
      db.execute('NOT SQL'),
      throwsA(isA<sqlite.SqliteException>()),
    );
  });
}
