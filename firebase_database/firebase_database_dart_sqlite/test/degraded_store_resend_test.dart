// What a degraded store leaves for the next start, through the real client: FirebaseDatabase with
// its Repo over SqlitePersistence, connected to the client's fake server. Each instance makes at
// most one write before the probe of `restart`, so the fake server never answers a write while
// another one is pending.
@TestOn('vm')
library;

import 'dart:async';

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/firebase_database_dart.dart';
import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart/testing.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

int _apps = 0;

void main() {
  late StoreFixture fixture;
  late FirebaseApp app;
  setUp(() {
    fixture = StoreFixture();
    app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'test-key',
        appId: '1:1234567890:dart:test',
        projectId: 'demo-test',
      ),
      name: 'degraded-${_apps++}',
    );
  });
  tearDown(() => fixture.dispose());

  /// A new database instance of [app] over the store files of [fixture], as after a restart.
  FirebaseDatabase open(FakeDatabaseServer server, List<String> log) {
    return databaseWithFakeServer(
      app,
      server,
      persistence: databasePersistence(
        opener: SqlitePersistence(
          fixture.directory,
          options: fixture.options(),
        ).open,
      ),
      logger: (DatabaseLogLevel level, String message) => log.add(message),
    );
  }

  String storePath(FirebaseDatabase db) => SqlitePersistence(
    fixture.directory,
  ).pathOf(PersistenceKey(appName: app.name, databaseUrl: db.databaseUrl));

  /// The ids of the rows of `user_writes` in the file of [db].
  List<Object?> writesOnDisk(FirebaseDatabase db) {
    final sqlite.Database raw = sqlite.sqlite3.open(storePath(db));
    try {
      return <Object?>[
        for (final sqlite.Row row in raw.select(
          'SELECT id FROM user_writes ORDER BY id',
        ))
          row['id'],
      ];
    } finally {
      StoreFixture.closeRaw(raw);
    }
  }

  /// Runs [body] while another connection holds the write lock of the file of [db]: every storage
  /// transaction meanwhile is refused as busy after the store's busy timeout (1 s each).
  Future<void> whileLocked(
    FirebaseDatabase db,
    FutureOr<void> Function() body,
  ) async {
    final sqlite.Database other = sqlite.sqlite3.open(storePath(db));
    other.execute('BEGIN IMMEDIATE');
    try {
      await body();
    } finally {
      other.execute('ROLLBACK');
      StoreFixture.closeRaw(other);
    }
  }

  /// Degrades the open store of [db]: three lease refreshes in a row refused as busy.
  Future<void> degrade(FirebaseDatabase db) => whileLocked(db, () {
    for (int i = 0; i < 3; i++) {
      fixture.timers.last.fire();
    }
  });

  /// Starts a new instance on the same files and returns the requests its server received up to
  /// and including a probe write made after the start.
  Future<List<String>> restart() async {
    final FakeDatabaseServer server = FakeDatabaseServer();
    final List<String> log = <String>[];
    final FirebaseDatabase db = open(server, log);
    // Restored writes are sent before any write made after the start.
    unawaited(db.ref('probe').set(true).catchError((Object _) {}));
    for (int i = 0; i < 300 && !server.requests.contains('p /probe'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(server.requests, contains('p /probe'));
    expect(db.persistenceEnabled, isTrue, reason: log.join('\n'));
    final List<String> requests = server.requests;
    await db.close();
    return requests;
  }

  test(
    'a write acknowledged after the store degraded is not sent again at the next '
    'start',
    () async {
      final FakeDatabaseServer server = FakeDatabaseServer();
      final FirebaseDatabase db = open(server, <String>[]);
      final Future<void> write = db.ref('a').set(1);
      await pumpEventQueue();
      expect(server.requests, <String>['p /a']);
      expect(writesOnDisk(db), <Object?>[1]);

      await degrade(db);
      expect(db.persistenceEnabled, isFalse);
      server.ackLastWrite();
      await write;
      await db.close();

      expect(await restart(), <String>['p /probe']);
    },
  );

  test(
    'a write refused after the store degraded is not sent again at the next start',
    () async {
      final FakeDatabaseServer server = FakeDatabaseServer();
      final FirebaseDatabase db = open(server, <String>[]);
      final Future<void> write = db.ref('a').set(1);
      await pumpEventQueue();
      expect(writesOnDisk(db), <Object?>[1]);

      await degrade(db);
      server.failLastWrite('permission_denied');
      await expectLater(write, throwsA(isA<FirebaseDatabaseException>()));
      await db.close();

      expect(await restart(), <String>['p /probe']);
    },
  );

  test('a write whose save hit the storage error is not in the file', () async {
    final FakeDatabaseServer server = FakeDatabaseServer();
    final FirebaseDatabase db = open(server, <String>[]);
    await pumpEventQueue();
    late Future<void> write;
    await whileLocked(db, () async {
      // The save of the write is the first busy transaction; two refreshes make three.
      write = db.ref('a').set(1);
      await pumpEventQueue();
      fixture.timers.last
        ..fire()
        ..fire();
    });
    expect(db.persistenceEnabled, isFalse);
    expect(server.requests, <String>['p /a']);
    server.ackLastWrite();
    await write;
    await db.close();

    expect(writesOnDisk(db), isEmpty);
    expect(await restart(), <String>['p /probe']);
  });

  test(
    'a write not answered when the store degraded is sent again at the next start',
    () async {
      final FakeDatabaseServer server = FakeDatabaseServer();
      final FirebaseDatabase db = open(server, <String>[]);
      final Future<void> write = db.ref('a').set(1);
      await pumpEventQueue();

      await degrade(db);
      final Future<void> failed = expectLater(
        write,
        throwsA(isA<FirebaseDatabaseException>()),
      );
      await db.close();
      await failed;

      expect(await restart(), <String>['p /a', 'p /probe']);
    },
  );

  test(
    'a write acknowledged while the file was busy is removed by the next transaction',
    () async {
      final FakeDatabaseServer server = FakeDatabaseServer();
      final FirebaseDatabase db = open(server, <String>[]);
      final Future<void> first = db.ref('a').set(1);
      await pumpEventQueue();
      expect(writesOnDisk(db), <Object?>[1]);

      // The transaction of the acknowledgement is refused once as busy; the store stays durable.
      await whileLocked(db, () async {
        server.ackLastWrite();
        await first;
      });
      expect(db.persistenceEnabled, isTrue);
      expect(writesOnDisk(db), <Object?>[1]);

      final Future<void> second = db.ref('b').set(2);
      await pumpEventQueue();
      expect(writesOnDisk(db), <Object?>[2]);
      final Future<void> closed = expectLater(
        second,
        throwsA(isA<FirebaseDatabaseException>()),
      );
      await db.close();
      await closed;
    },
  );

  test('a lost lease: the connection that took the file sends the pending write too (not '
      'fixed: documents the behaviour)', () async {
    final FakeDatabaseServer server1 = FakeDatabaseServer();
    final FirebaseDatabase db1 = open(server1, <String>[]);
    final Future<void> write = db1.ref('a').set(1);
    await pumpEventQueue();
    expect(writesOnDisk(db1), <Object?>[1]);

    // db1 stalls (its refresh timer does not fire): another instance takes the file over after one
    // observation period, loads write 1 and sends it.
    final FakeDatabaseServer server2 = FakeDatabaseServer();
    final List<String> log2 = <String>[];
    final FirebaseDatabase db2 = open(server2, log2);
    unawaited(db2.ref('probe').set(true).catchError((Object _) {}));
    for (int i = 0; i < 300 && !server2.requests.contains('p /probe'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(db2.persistenceEnabled, isTrue, reason: log2.join('\n'));
    expect(server2.requests, <String>['p /a', 'p /probe']);

    // db1's server answers write 1: db1 finds the lease lost and writes nothing more.
    server1.ackLastWrite();
    await write;
    expect(db1.persistenceEnabled, isFalse);
    await db1.close();
    await db2.close();
  });
}
