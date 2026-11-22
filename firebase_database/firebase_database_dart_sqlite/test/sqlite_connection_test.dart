// Tests of the connection contract (E-T1 and E-D1 of rtdb_storage_engine_design.md section 15).
// E-T1 ports the transaction rule of Android's SqlPersistenceStorageEngineTest
// testConcurrentUsageFails at the connection level; E-D1 is new.
import 'dart:typed_data';

import 'package:firebase_database_dart/firebase_database_dart.dart'
    show DatabaseLogLevel;
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
      'H1 a full disk degrades the store without throwing; the committed write survives a reopen',
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
        expect(SqliteLease.read(other), isNull);
        StoreFixture.closeRaw(other);

        // Revised after review, 2026-11-22: a storage error deletes nothing. The write committed
        // before the error is still there after a reopen; the failed transaction left nothing.
        final SqliteConnection reopened = await fixture.open();
        addTearDown(reopened.close);
        expect(reopened.isDurable, isTrue);
        expect(
          reopened
              .select('SELECT id FROM user_writes ORDER BY id')
              .map((sqlite.Row row) => row['id'])
              .toList(),
          <Object?>[1],
        );
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

  group('review findings, 2026-11-22', () {
    test(
      'M5 a busy file skips one transaction and the store stays durable',
      () async {
        // Fails if `_isBusy` is not checked in SqliteConnection._onStorageError (every busy
        // degrades).
        final SqliteConnection store = await fixture.open();
        addTearDown(store.close);
        final sqlite.Database other = fixture.raw();
        addTearDown(() => StoreFixture.closeRaw(other));
        other.execute('BEGIN IMMEDIATE');

        expect(store.begin(), isFalse);
        store.execute(insertWrite, <Object?>[1, '/a/', 'o', Uint8List(1)]);
        store.rollback();
        expect(store.state, StoreState.durable);

        other.execute('ROLLBACK');
        expect(store.begin(), isTrue);
        store.execute(insertWrite, <Object?>[2, '/b/', 'o', Uint8List(1)]);
        store.commit();
        expect(store.select('SELECT id FROM user_writes').single['id'], 2);
      },
    );

    test(
      'M5 three busy transactions in a row degrade the store; a success resets the count',
      () async {
        // Fails if `maxConsecutiveBusy` is not compared in _onStorageError, or the count is not
        // reset after a commit (SqliteConnection.commit).
        final SqliteConnection store = await fixture.open();
        addTearDown(store.close);
        final sqlite.Database other = fixture.raw();
        addTearDown(() => StoreFixture.closeRaw(other));

        void busyTransaction() {
          other.execute('BEGIN IMMEDIATE');
          expect(store.begin(), isFalse);
          store.rollback();
          other.execute('ROLLBACK');
        }

        busyTransaction();
        busyTransaction();
        expect(store.begin(), isTrue);
        store.commit();
        busyTransaction();
        busyTransaction();
        expect(store.state, StoreState.durable);

        busyTransaction();
        expect(store.state, StoreState.degraded);
      },
    );

    test('M5 normal work waits 1 s for a lock', () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(
        StoreFixture.scalar(store.debugDatabase!, 'PRAGMA busy_timeout'),
        busyTimeoutMs,
      );
      expect(busyTimeoutMs, 1000);
    });

    test(
      'L9 a close inside a transaction leaves the end of the transaction harmless',
      () async {
        // Fails without the `StoreState.closed` early return in SqliteConnection.commit/rollback.
        final SqliteConnection store = await fixture.open();
        store.begin();
        store.close();

        store.commit();
        store.rollback();
        expect(store.state, StoreState.closed);
      },
    );
  });
}
