// Tests E-L1 to E-L5 of rtdb_storage_engine_design.md section 15 (new; Android has no lease).
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;

  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  LeaseRow currentLease() {
    final sqlite.Database db = fixture.raw();
    try {
      return SqliteLease.read(db)!;
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  test('the first open owns the store without waiting', () async {
    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    expect(store.state, StoreState.durable);
    expect(fixture.clock.delays, isEmpty);
    final LeaseRow lease = currentLease();
    expect(lease.ownerId, 'owner-1');
    expect(lease.epoch, 1);
    expect(
      lease.expiresAtMs,
      fixture.clock.nowMs + SqliteLease.duration.inMilliseconds,
    );
  });

  test(
    'E-L1 a second open watches the lease one observation period, then keeps data in memory',
    () async {
      final SqliteConnection first = await fixture.open();
      addTearDown(first.close);
      // The live owner refreshes its lease while the second one waits.
      fixture.clock.onAdvance = first.refreshLease;

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.memoryOnly);
      expect(second.isDurable, isFalse);
      expect(fixture.clock.delays, hasLength(1));
      expect(fixture.clock.delays.single, SqliteLease.observation);
      expect(first.state, StoreState.durable);
      expect(
        fixture.log.single,
        contains('another process or isolate owns it'),
      );
    },
  );

  test(
    'E-L2 an owner that closes releases the lease; the next open does not wait',
    () async {
      final SqliteConnection first = await fixture.open();
      first.close();
      expect(first.state, StoreState.closed);

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.durable);
      expect(fixture.clock.delays, isEmpty);
      expect(currentLease().ownerId, 'owner-2');
    },
  );

  test(
    'E-L3 an owner that vanished is waited for, then replaced; the old one is fenced',
    () async {
      final SqliteConnection first = await fixture.open();
      addTearDown(first.close);
      // No refresh: the first owner is "gone" (a crash, a hot restart).

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.durable);
      expect(fixture.clock.delays, hasLength(1));
      final LeaseRow lease = currentLease();
      expect(lease.ownerId, 'owner-2');
      expect(lease.epoch, 2);

      expect(first.begin(), isFalse);
      first.rollback();
      expect(first.state, StoreState.fenced);
    },
  );

  test(
    'E-L4 a lease taken mid-session fences the next transaction; nothing is written',
    () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      final sqlite.Database other = fixture.raw();
      other.execute(
        "UPDATE lease SET owner_id = 'intruder', epoch = epoch + 1 WHERE id = 0",
      );

      expect(store.begin(), isFalse);
      store.execute(
        "INSERT INTO user_writes (id, path, type, value) VALUES (1, '/a/', 'o', x'00')",
      );
      store.commit();

      expect(store.state, StoreState.fenced);
      expect(StoreFixture.scalar(other, 'SELECT count(*) FROM user_writes'), 0);
      expect(SqliteLease.read(other)!.ownerId, 'intruder');
      expect(fixture.log.single, contains('took over'));
      StoreFixture.closeRaw(other);
    },
  );

  test('a transaction of the owner sees its lease and commits', () async {
    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    expect(store.begin(), isTrue);
    store.execute(
      "INSERT INTO user_writes (id, path, type, value) VALUES (1, '/a/', 'o', x'00')",
    );
    store.commit();

    final sqlite.Database other = fixture.raw();
    expect(StoreFixture.scalar(other, 'SELECT count(*) FROM user_writes'), 1);
    StoreFixture.closeRaw(other);
  });

  test(
    'E-L5 a refresh renews a lease that expired while nobody took it',
    () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      fixture.clock.advance(const Duration(seconds: 10));
      store.refreshLease();

      expect(store.state, StoreState.durable);
      expect(
        currentLease().expiresAtMs,
        fixture.clock.nowMs + SqliteLease.duration.inMilliseconds,
      );
    },
  );

  test(
    'a refresh after another owner took the lease fences the connection',
    () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      final sqlite.Database other = fixture.raw();
      other.execute(
        "UPDATE lease SET owner_id = 'intruder', epoch = epoch + 1 WHERE id = 0",
      );
      StoreFixture.closeRaw(other);

      store.refreshLease();

      expect(store.state, StoreState.fenced);
      expect(currentLease().ownerId, 'intruder');
    },
  );

  test(
    'closing a fenced connection leaves the new owner lease alone',
    () async {
      final SqliteConnection first = await fixture.open();
      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);
      first.refreshLease();
      expect(first.state, StoreState.fenced);

      first.close();

      expect(currentLease().ownerId, 'owner-2');
      expect(SqliteFiles.badCopies(fixture.path), isEmpty);
    },
  );

  // Review findings, 2026-11-22 (review-sqlite.md). Each comment names the lib line whose reversal
  // makes the test fail.

  test(
    'M1 an owner whose clock ran ahead and that vanished is taken over after one observation',
    () async {
      // Fails if tryAcquire compares clocks again instead of `current.sameAs(observed)`
      // (sqlite_lease.dart, the `free` condition of tryAcquire).
      final SqliteConnection first = await fixture.open();
      addTearDown(first.close);
      first.begin();
      first.execute(
        "INSERT INTO user_writes (id, path, type, value) VALUES (1, '/a/', 'o', x'00')",
      );
      first.commit();
      final sqlite.Database raw = fixture.raw();
      // The owner's clock was an hour ahead when it last refreshed; then it stopped.
      raw.execute(
        'UPDATE lease SET expires_at_ms = expires_at_ms + 3600000 WHERE id = 0',
      );
      StoreFixture.closeRaw(raw);

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.durable);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
      expect(second.select('SELECT id FROM user_writes').length, 1);
      expect(first.begin(), isFalse);
      first.rollback();
      expect(first.state, StoreState.fenced);
    },
  );

  test(
    'M2 an owner whose timer refresh comes 1.1 s late keeps its lease',
    () async {
      // Fails with the old observation of 5.25 s (sqlite_lease.dart `takeOverSlack`/`observation`).
      final SqliteConnection first = await fixture.open();
      addTearDown(first.close);
      final int start = fixture.clock.nowMs;
      final int lateRefreshAt =
          start + SqliteLease.refreshInterval.inMilliseconds + 1100;
      bool refreshed = false;
      fixture.clock
        ..delayStep = const Duration(milliseconds: 100)
        ..onAdvance = () {
          if (!refreshed && fixture.clock.nowMs >= lateRefreshAt) {
            refreshed = true;
            first.refreshLease();
          }
        };

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(refreshed, isTrue);
      expect(second.state, StoreState.memoryOnly);
      expect(first.state, StoreState.durable);
    },
  );

  test(
    'M2 an owner busy in storage transactions keeps its lease without its timer',
    () async {
      // Fails without `_lease!.extendIfDue(db)` in SqliteConnection.begin.
      final SqliteConnection first = await fixture.open();
      addTearDown(first.close);
      fixture.clock.onAdvance = () {
        first.begin();
        first.commit();
      };

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.memoryOnly);
      expect(first.state, StoreState.durable);
    },
  );

  test('M3 a file with a live clearing tombstone is never taken', () async {
    // Fails without the `LeaseCleared` branch of tryAcquire (sqlite_lease.dart).
    (await fixture.open()).close();
    final sqlite.Database raw = fixture.raw();
    raw.execute(
      'INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, ?, 7, ?)',
      <Object?>[
        SqliteLease.clearingOwnerId,
        fixture.clock.nowMs + SqliteLease.tombstoneDuration.inMilliseconds,
      ],
    );
    StoreFixture.closeRaw(raw);

    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    expect(store.state, StoreState.memoryOnly);
    expect(fixture.log.last, contains('being deleted'));
  });

  test(
    'M4 a lease row of other types fences the owner without an exception',
    () async {
      // Fails with the old casts in SqliteLease.read (`row['epoch'] as int`).
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      final sqlite.Database raw = fixture.raw();
      raw.execute("UPDATE lease SET epoch = 'x' WHERE id = 0");
      StoreFixture.closeRaw(raw);

      expect(store.begin(), isFalse);
      store.rollback();

      expect(store.state, StoreState.fenced);
      expect(store.inTransaction, isFalse);
    },
  );

  test(
    'M4 an unreadable lease row of a vanished owner is taken over after one observation',
    () async {
      (await fixture.open()).close();
      final sqlite.Database raw = fixture.raw();
      raw.execute(
        "INSERT INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, 'a', 'x', 0)",
      );
      StoreFixture.closeRaw(raw);

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(currentLease().epoch, 1);
    },
  );

  test('L4 a takeover from the same process is reported as such', () async {
    // Fails if tryAcquire stops comparing `processOf` (previousOwnerSameProcess); the opener then
    // runs quick_check after every hot restart (sqlite_open.dart, the LeaseAcquired case).
    (await fixture.open()).close();
    final sqlite.Database raw = fixture.raw();
    addTearDown(() => StoreFixture.closeRaw(raw));
    raw.execute(
      "INSERT INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, '4242:old', 3, 0)",
    );
    final LeaseRow observed = SqliteLease.read(raw)!;

    final LeaseAttempt same = SqliteLease(
      ownerId: '4242:new',
      nowMs: fixture.clock.now,
    ).tryAcquire(raw, observed: observed);
    expect(same, isA<LeaseAcquired>());
    expect((same as LeaseAcquired).previousOwnerSameProcess, isTrue);

    final LeaseRow now = SqliteLease.read(raw)!;
    final LeaseAttempt other = SqliteLease(
      ownerId: '17:new',
      nowMs: fixture.clock.now,
    ).tryAcquire(raw, observed: now);
    expect((other as LeaseAcquired).previousOwnerVanished, isTrue);
    expect(other.previousOwnerSameProcess, isFalse);
  });
}
