// Tests of the connection contract (E-T1 and E-D1 of rtdb_storage_engine_design.md section 15).
// E-T1 ports the transaction rule of Android's SqlPersistenceStorageEngineTest
// testConcurrentUsageFails at the connection level; E-D1 is new.
import 'dart:typed_data';

// switch to storage_engine.dart (DatabaseLogger: the main library if it is not there)
import 'package:firebase_database_dart/src/core/util/logger.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;

  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  const String insertWrite =
      'INSERT INTO user_writes (id, path, type, value) VALUES (?, ?, ?, ?)';

  group('E-T1 transactions', () {
    test('a write outside a transaction is a StateError', () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(
        () =>
            store.execute(insertWrite, <Object?>[1, '/a/', 'o', Uint8List(1)]),
        throwsStateError,
      );
      expect(store.commit, throwsStateError);
      expect(store.rollback, throwsStateError);
    });

    test('transactions do not nest', () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.begin(), isTrue);
      expect(store.begin, throwsStateError);
      store.rollback();
    });

    test('a rolled-back transaction leaves nothing behind', () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      store.begin();
      store.execute(insertWrite, <Object?>[1, '/a/', 'o', Uint8List(1)]);
      store.rollback();

      expect(store.select('SELECT id FROM user_writes'), isEmpty);
      expect(store.state, StoreState.durable);
    });

    test('reads outside a transaction are allowed', () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      store.begin();
      store.execute(insertWrite, <Object?>[3, '/a/', 'm', Uint8List(1)]);
      store.commit();

      final sqlite.Row row = store
          .select('SELECT id, type FROM user_writes')
          .single;

      expect(row['id'], 3);
      expect(row['type'], 'm');
      expect(store.changes, 1);
    });
  });

  group('memory-only connection', () {
    test('accepts the calls and stores nothing', () {
      final List<String> log = <String>[];
      final SqliteConnection store = SqliteConnection.memoryOnly(
        reason: 'why',
        log: (DatabaseLogLevel level, String message) => log.add(message),
      );

      expect(store.begin(), isFalse);
      store.execute(insertWrite, <Object?>[1, '/a/', 'o', Uint8List(1)]);
      expect(store.select('SELECT 1'), isEmpty);
      store.commit();
      store.close();
      store.close();

      expect(log, <String>['why']);
      expect(store.state, StoreState.closed);
      expect(store.changes, 0);
    });
  });

  group('E-D1 storage errors', () {
    test(
      'a full disk degrades the store to memory without throwing; rows are wiped',
      () async {
        final SqliteConnection store = await fixture.open();
        final sqlite.Database db = store.debugDatabase!;
        store.begin();
        store.execute(insertWrite, <Object?>[
          1,
          '/secret-marker/',
          'o',
          Uint8List(1),
        ]);
        store.commit();
        final int pages = StoreFixture.scalar(db, 'PRAGMA page_count') as int;
        db.select('PRAGMA max_page_count = ${pages + 1}');

        expect(store.begin(), isTrue);
        for (int i = 0; i < 64; i++) {
          store.execute(insertWrite, <Object?>[
            i + 2,
            '/secret-marker/$i/',
            'o',
            Uint8List(16384),
          ]);
        }
        store.commit();

        expect(store.state, StoreState.degraded);
        expect(store.isDurable, isFalse);
        expect(fixture.log.single, contains('result code 13'));
        expect(fixture.log.single, isNot(contains('secret-marker')));
        store.close();

        final sqlite.Database other = fixture.raw();
        expect(
          StoreFixture.scalar(other, 'SELECT count(*) FROM user_writes'),
          0,
        );
        expect(SqliteLease.read(other), isNull);
        StoreFixture.closeRaw(other);
      },
    );

    test(
      'after degrading, statements are no-ops and reads return nothing',
      () async {
        final SqliteConnection store = await fixture.open();
        final sqlite.Database db = store.debugDatabase!;
        final int pages = StoreFixture.scalar(db, 'PRAGMA page_count') as int;
        db.select('PRAGMA max_page_count = $pages');
        store.begin();
        for (int i = 0; i < 64; i++) {
          store.execute(insertWrite, <Object?>[
            i,
            '/k$i/',
            'o',
            Uint8List(16384),
          ]);
        }
        store.commit();
        expect(store.state, StoreState.degraded);

        expect(store.begin(), isFalse);
        store.execute(insertWrite, <Object?>[100, '/x/', 'o', Uint8List(1)]);
        expect(store.select('SELECT 1'), isEmpty);
        store.commit();
        store.close();
        expect(store.state, StoreState.closed);
      },
    );

    test('wrong SQL fails an assertion and degrades the store', () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      store.begin();

      expect(
        () => store.execute('INSERT INTO no_such_table VALUES (1)'),
        throwsA(isA<AssertionError>()),
      );

      store.commit();
      expect(store.state, StoreState.degraded);
    });
  });
}
