// The offline cache in a browser: SQLite compiled to WebAssembly with its
// database in IndexedDB, through example/sqlite_database_web.dart.
//
// The tests need test/browser/sqlite3.wasm, the WebAssembly build of SQLite
// for the sqlite3 package version in pubspec.lock. It is not in the
// repository: download `sqlite3.wasm` from
// https://github.com/simolus3/sqlite3.dart/releases (tag `sqlite3-<version>`).
// Without it the tests skip themselves with that reason. Run them against a
// private emulator, one file at a time:
//
//   dart test -j 1 -p chrome -c dart2wasm test/browser/web_persistence_test.dart

@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../../example/sqlite_database_web.dart';
import 'browser_test_util.dart';

typedef Json = Map<String, Object?>;

final Uri sqlite3Wasm = Uri.base.resolve('sqlite3.wasm');
const String storagePrefix = 'cloud_firestore_dart';

OpenDatabase opener() => sqliteWebOpener(sqlite3Wasm: sqlite3Wasm);

int _names = 0;
String newAppName() =>
    'persist-${DateTime.now().microsecondsSinceEpoch}-${_names++}';

/// The names of the IndexedDB databases of this origin that belong to [app].
Future<List<String>> storedDatabases(String app) async =>
    (await sqlite.IndexedDbFileSystem.databases() ?? <String>[])
        .where((String name) => name.contains(app))
        .toList();

void main() {
  String? skip;

  setUpAll(() async {
    try {
      final web.Response response =
          await web.window.fetch(sqlite3Wasm.toString().toJS).toDart;
      if (!response.ok) {
        skip =
            'test/browser/sqlite3.wasm is missing (HTTP ${response.status}): '
            'download it from the releases of the sqlite3 package';
      }
    } catch (e) {
      skip = 'test/browser/sqlite3.wasm cannot be fetched: $e';
    }
  });

  /// Registers the test, skipped at run time when sqlite3.wasm is missing.
  void persistenceTest(String name, Future<void> Function() body) {
    test(name, () async {
      if (skip != null) {
        markTestSkipped(skip!);
        return;
      }
      await body();
    });
  }

  persistenceTest('the cache is persistent and holds what was read and written',
      () async {
    final Firestore firestore = await newClient(openDatabase: opener());
    expect(firestore.client.persistence, isA<SQLitePersistence>());
    final DocumentReference<Json> doc =
        firestore.collection(newCollectionName()).doc('a');
    await doc.set(<String, Object?>{'a': 1, 'text': 'héllo \u{1F600}'});

    final DocumentSnapshot<Json> cached = await doc.get(Source.cache);
    expect(cached.data, <String, Object?>{'a': 1, 'text': 'héllo \u{1F600}'});
    expect(cached.metadata.hasPendingWrites, isFalse);
  });

  persistenceTest('acknowledged data is there again after the client is reopened',
      () async {
    final String app = newAppName();
    final String collection = newCollectionName();
    Firestore firestore = await newClient(openDatabase: opener(), appName: app);
    for (int i = 0; i < 3; i++) {
      await firestore.collection(collection).doc('d$i').set(<String, Object?>{
        'n': i,
      });
    }
    // Read through a listener too, so that the query has a cached target.
    await firestore.collection(collection).get(Source.server);
    await shutDown(firestore);
    expect(await storedDatabases(app), hasLength(1));

    // A new SQLite instance that reads its pages back from IndexedDB, as
    // after a page load. Offline, so that nothing can come from the backend.
    firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.disableNetwork();
    final QuerySnapshot<Json> cached =
        await firestore.collection(collection).orderBy('n').get(Source.cache);
    expect(cached.metadata.isFromCache, isTrue);
    expect(
        cached.docs.map((QueryDocumentSnapshot<Json> d) => d.data).toList(),
        <Json>[
          <String, Object?>{'n': 0},
          <String, Object?>{'n': 1},
          <String, Object?>{'n': 2},
        ]);
  });

  persistenceTest('pending writes survive and are sent after the client is reopened',
      () async {
    final String app = newAppName();
    final String collection = newCollectionName();
    Firestore firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.collection(collection).doc('synced').set(<String, Object?>{
      'v': 1,
    });

    // Written offline: they only exist in the mutation queue.
    await firestore.disableNetwork();
    unawaited(firestore.collection(collection).doc('pending').set(
      <String, Object?>{'v': 2},
    ));
    unawaited(firestore.collection(collection).doc('synced').update(
      <String, Object?>{'v': FieldValue.increment(10)},
    ));
    // The writes are in the cache once a cache read sees them.
    expect(
        (await firestore.collection(collection).doc('pending').get(Source.cache))
            .metadata
            .hasPendingWrites,
        isTrue);
    await shutDown(firestore);

    firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.disableNetwork();
    final DocumentSnapshot<Json> pending =
        await firestore.collection(collection).doc('pending').get(Source.cache);
    expect(pending.data, <String, Object?>{'v': 2});
    expect(pending.metadata.hasPendingWrites, isTrue);
    final DocumentSnapshot<Json> synced =
        await firestore.collection(collection).doc('synced').get(Source.cache);
    expect(synced.data, <String, Object?>{'v': 11});
    expect(synced.metadata.hasPendingWrites, isTrue);

    // Back online the queue is sent, once.
    await firestore.enableNetwork();
    await firestore.waitForPendingWrites().timeout(const Duration(seconds: 20));
    final Firestore other = await newClient();
    final QuerySnapshot<Json> server =
        await other.collection(collection).get(Source.server);
    expect(<String, Object?>{
      for (final QueryDocumentSnapshot<Json> d in server.docs) d.id: d.data,
    }, <String, Object?>{
      'pending': <String, Object?>{'v': 2},
      'synced': <String, Object?>{'v': 11},
    });
  });

  persistenceTest('a cache that is open cannot be opened a second time',
      () async {
    final String name = 'guard-${newAppName()}';
    final Database first = await opener()(name, version: 1);

    // What a second tab runs into: the same origin, the same lock.
    await expectLater(
        opener()(name, version: 1),
        throwsA(isA<FirestoreError>()
            .having((FirestoreError e) => e.code, 'code',
                FirestoreErrorCode.failedPrecondition)
            .having((FirestoreError e) => e.message, 'message',
                contains('another tab'))));

    // Another database is not affected.
    final Database other = await opener()('$name-other', version: 1);
    other.close();

    first.close();
    // Closing stores what is left and then releases the lock.
    Database? again;
    for (int i = 0; i < 50 && again == null; i++) {
      try {
        again = await opener()(name, version: 1);
      } on FirestoreError {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    expect(again, isNotNull, reason: 'the lock is released by close()');
    again!.close();
  });

  persistenceTest('a cache held by another browsing context is refused',
      () async {
    // A frame of the same origin is another context for the Web Locks API,
    // like a second tab: it takes the lock of the cache the client will ask
    // for.
    final String app = newAppName();
    final String collection = newCollectionName();
    Firestore firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.collection(collection).doc('a').set(<String, Object?>{'a': 1});
    final String storageName = (await storedDatabases(app)).single;
    await shutDown(firestore);

    final web.HTMLIFrameElement frame =
        web.document.createElement('iframe') as web.HTMLIFrameElement;
    web.document.body!.appendChild(frame);
    addTearDown(() => frame.remove());
    final web.LockManager frameLocks = (frame.contentWindow! as JSObject)
        .getProperty<JSObject>('navigator'.toJS)
        .getProperty<web.LockManager>('locks'.toJS);
    final Completer<void> held = Completer<void>();
    final Completer<void> release = Completer<void>();
    JSPromise<JSAny?> hold(web.Lock? lock) {
      held.complete();
      return release.future.then<JSAny?>((_) => null).toJS;
    }

    unawaited(frameLocks.request(storageName, hold.toJS).toDart);
    await held.future.timeout(const Duration(seconds: 5));

    await expectLater(
        newClient(openDatabase: opener(), appName: app),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.failedPrecondition)));

    // The other "tab" goes away: the cache can be opened again, with its data.
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.disableNetwork();
    expect((await firestore.collection(collection).doc('a').get(Source.cache)).data,
        <String, Object?>{'a': 1});
  });

  persistenceTest('clearPersistence deletes the stored cache', () async {
    final String app = newAppName();
    final String collection = newCollectionName();
    Firestore firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.collection(collection).doc('a').set(<String, Object?>{'a': 1});

    // Refused while the client runs, as everywhere.
    await expectLater(
        firestore.clearPersistence(),
        throwsA(isA<FirestoreError>().having((FirestoreError e) => e.code,
            'code', FirestoreErrorCode.failedPrecondition)));

    await firestore.terminate();
    expect(await storedDatabases(app), hasLength(1));
    await firestore.clearPersistence();
    expect(await storedDatabases(app), isEmpty);
    await shutDown(firestore);

    // A new client starts with an empty cache.
    firestore = await newClient(openDatabase: opener(), appName: app);
    await firestore.disableNetwork();
    final QuerySnapshot<Json> cached =
        await firestore.collection(collection).get(Source.cache);
    expect(cached.docs, isEmpty);
  });

  persistenceTest('the index engine works on it (automatic index creation)',
      () async {
    final Firestore firestore = await newClient(openDatabase: opener());
    final LocalStore localStore = firestore.client.localStore;
    final PersistentCacheIndexManager indexes =
        firestore.persistentCacheIndexManager!;
    await indexes.enableIndexAutoCreation();

    final CollectionReference<Json> cities =
        firestore.collection(newCollectionName());
    final WriteBatch batch = firestore.batch();
    for (int i = 0; i < 150; i++) {
      batch.set(cities.doc('city$i'), <String, Object?>{
        'country': i < 5 ? 'RO' : 'other',
        'population': 1000 * i,
      });
    }
    await batch.commit();
    await cities.get(Source.server);

    final Query<Json> romanian =
        cities.whereEqualTo('country', 'RO').orderBy('population');
    IndexType indexType() => localStore.indexManagerForCurrentUser
        .getIndexType(romanian.query.toTarget());
    final List<String> expected = <String>[
      for (int i = 0; i < 5; i++) 'city$i',
    ];
    List<String> ids(QuerySnapshot<Json> snapshot) => <String>[
          for (final QueryDocumentSnapshot<Json> doc in snapshot.docs) doc.id,
        ];

    expect(localStore.getFieldIndexes(), isEmpty);
    expect(indexType(), IndexType.none);

    // The first run scans, and creates the index.
    expect(ids(await romanian.get(Source.cache)), expected);
    expect(localStore.getFieldIndexes(), hasLength(1));
    expect(indexType(), IndexType.full);

    // Before the backfill, halfway, and when the index is complete.
    expect(await firestore.client.backfillIndexes(), 50);
    expect(ids(await romanian.get(Source.cache)), expected);
    int filled = 50;
    for (int n = await firestore.client.backfillIndexes();
        n > 0;
        n = await firestore.client.backfillIndexes()) {
      filled += n;
    }
    expect(filled, 150);
    expect(ids(await romanian.get(Source.cache)), expected);

    await indexes.deleteAllIndexes();
    expect(localStore.getFieldIndexes(), isEmpty);
    expect(ids(await romanian.get(Source.cache)), expected);
  });

  persistenceTest(
      'every schema migration runs on it, one version at a time and at once',
      () async {
    Future<List<String>> schemaOf(Database db) async => <String>[
          for (final Map<String, dynamic> row in await db.query(
            'SELECT type, name, sql FROM sqlite_master '
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
          ))
            '${row['type']} ${row['name']}: ${row['sql']}',
        ];
    Future<int> userVersion(Database db) async =>
        (await db.query('PRAGMA user_version')).single.values.first as int;

    // One version at a time, closing and reopening the database in between,
    // the way a cache that has existed since version 1 was upgraded.
    final String stepwise = 'schema-steps-${newAppName()}';
    final List<String> ran = <String>[];
    for (int version = 1; version <= SQLiteSchema.version; version++) {
      final Database db = await opener()(
        stepwise,
        version: version,
        onCreate: (Database db, int to) async {
          ran.add('create $to');
          await SQLiteSchema(db).runMigrations(0, to);
        },
        onUpgrade: (Database db, int from, int to) async {
          ran.add('$from->$to');
          await SQLiteSchema(db).runMigrations(from, to);
        },
      );
      expect(await userVersion(db), version);
      db.close();
    }
    expect(ran, <String>[
      'create 1',
      for (int v = 1; v < SQLiteSchema.version; v++) '$v->${v + 1}',
    ]);
    expect(SQLiteSchema.version, 17,
        reason: 'a new migration: check that it runs in the browser too');

    // All at once, as for a new cache.
    final String direct = 'schema-direct-${newAppName()}';
    final Database fresh = await opener()(
      direct,
      version: SQLiteSchema.version,
      onCreate: (Database db, int to) => SQLiteSchema(db).runMigrations(0, to),
    );
    final Database upgraded =
        await opener()(stepwise, version: SQLiteSchema.version);
    final List<String> freshSchema = await schemaOf(fresh);
    expect(freshSchema, isNotEmpty);
    expect(await schemaOf(upgraded), freshSchema);
    for (final String table in <String>[
      'mutation_queues',
      'mutations',
      'document_mutations',
      'targets',
      'target_globals',
      'target_documents',
      'remote_documents',
      'collection_parents',
      'document_overlays',
      'bundles',
      'named_queries',
      'data_migrations',
      'index_configuration',
      'index_entries',
      'index_state',
    ]) {
      expect(freshSchema.any((String s) => s.startsWith('table $table:')),
          isTrue, reason: 'table $table');
    }

    for (final Database db in <Database>[fresh, upgraded]) {
      await (db as ClearableDatabase).clearStorage();
    }
    expect(await storedDatabases('schema-'), isEmpty);
  });

  persistenceTest(
      'an upgrade that fails halfway leaves the previous schema and version',
      () async {
    final String name = 'atomic-${newAppName()}';
    Future<List<String>> tables(Database db) async => <String>[
          for (final Map<String, dynamic> row in await db.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
          ))
            row['name'] as String,
        ];
    Future<int> userVersion(Database db) async =>
        (await db.query('PRAGMA user_version')).single.values.first as int;

    Database db = await opener()(
      name,
      version: 1,
      onCreate: (Database db, int to) => db.execute('CREATE TABLE one (a)'),
    );
    db.close();

    // The second statement of the upgrade fails: the first one must not stay.
    await expectLater(
        opener()(
          name,
          version: 2,
          onUpgrade: (Database db, int from, int to) async {
            await db.execute('CREATE TABLE two (a)');
            await db.execute('INSERT INTO one VALUES (1)');
            throw StateError('the tab would die here');
          },
        ),
        throwsStateError);

    // The next open finds version 1 and runs the whole upgrade again.
    final List<String> upgrades = <String>[];
    db = await opener()(
      name,
      version: 2,
      onCreate: (Database db, int to) async => fail('not a new database'),
      onUpgrade: (Database db, int from, int to) async {
        upgrades.add('$from->$to');
        expect(await tables(db), <String>['one']);
        expect(await db.query('SELECT * FROM one'), isEmpty);
        await db.execute('CREATE TABLE two (a)');
      },
    );
    expect(upgrades, <String>['1->2']);
    expect(await tables(db), <String>['one', 'two']);
    expect(await userVersion(db), 2);
    await (db as ClearableDatabase).clearStorage();

    // The same for a new cache whose creation fails: it stays new.
    final String fresh = 'atomic-new-${newAppName()}';
    await expectLater(
        opener()(
          fresh,
          version: 3,
          onCreate: (Database db, int to) async {
            await db.execute('CREATE TABLE one (a)');
            throw StateError('the tab would die here');
          },
        ),
        throwsStateError);
    bool created = false;
    db = await opener()(
      fresh,
      version: 3,
      onCreate: (Database db, int to) async {
        created = true;
        expect(await tables(db), isEmpty);
        await db.execute('CREATE TABLE one (a)');
      },
      onUpgrade: (Database db, int from, int to) async =>
          fail('still a new database'),
    );
    expect(created, isTrue);
    expect(await userVersion(db), 3);
    await (db as ClearableDatabase).clearStorage();
  });
}
