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

  LeaseRow? leaseOrNull() {
    final sqlite.Database db = fixture.raw();
    try {
      return SqliteLease.read(db);
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  LeaseRow currentLease() => leaseOrNull()!;

  /// Writes the lease row of the store file through a raw connection, as another process would.
  void writeLease(
    String ownerId, {
    required int epoch,
    required int expiresAtMs,
  }) {
    final sqlite.Database db = fixture.raw();
    try {
      db.execute(
        'INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, ?, ?, ?)',
        <Object?>[ownerId, epoch, expiresAtMs],
      );
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
    // The lease duration of the review rulings (2026-11-22): 15 s.
    expect(lease.expiresAtMs, fixture.clock.nowMs + 15000);
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
    'E-L5 a clock that steps back never moves the expiry back; the owner stays live',
    () async {
      // m19. Fails without `if (expires <= _lastWrittenExpiresMs)` in SqliteLease.extend
      // (sqlite_lease.dart:258): the refresh writes an expiry an hour earlier.
      final FakeClock ownerClock = FakeClock(fixture.clock.nowMs);
      final SqliteConnection owner = await fixture.open(clock: ownerClock);
      addTearDown(owner.close);
      final int before = currentLease().expiresAtMs;

      ownerClock.nowMs -= const Duration(hours: 1).inMilliseconds;
      owner.refreshLease();
      final int afterStep = currentLease().expiresAtMs;
      expect(afterStep, greaterThan(before));

      fixture.clock.onAdvance = owner.refreshLease;
      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.memoryOnly);
      expect(owner.state, StoreState.durable);
      expect(currentLease().expiresAtMs, greaterThan(afterStep));
    },
  );

  test(
    'a lease refreshed by an owner whose clock stands still stays live',
    () async {
      // m19. Fails without the monotonic step of SqliteLease.extend (sqlite_lease.dart:258-260):
      // the refresh writes the same row, and the observer takes a live owner's file.
      final FakeClock frozen = FakeClock(fixture.clock.nowMs);
      final SqliteConnection owner = await fixture.open(clock: frozen);
      addTearDown(owner.close);
      fixture.clock.onAdvance = owner.refreshLease;

      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);

      expect(second.state, StoreState.memoryOnly);
      expect(owner.state, StoreState.durable);
      expect(currentLease().ownerId, 'owner-1');
    },
  );

  test(
    'a transaction rewrites the row from half a refresh interval on, and after the clock went back',
    () async {
      // Fails if SqliteLease.extendIfDue (sqlite_lease.dart:275) uses `>` for `>=`, or drops the
      // `sinceLast < 0` case.
      (await fixture.open()).close();
      final sqlite.Database raw = fixture.raw();
      addTearDown(() => StoreFixture.closeRaw(raw));
      final FakeClock clock = fixture.clock;
      final SqliteLease lease = SqliteLease(ownerId: '17:a', nowMs: clock.now);
      expect(lease.tryAcquire(raw), isA<LeaseAcquired>());
      bool rewritten() {
        raw.execute('BEGIN IMMEDIATE');
        try {
          return lease.extendIfDue(raw);
        } finally {
          raw.execute('COMMIT');
        }
      }

      final int half = SqliteLease.refreshInterval.inMilliseconds ~/ 2;
      clock.nowMs += half - 1;
      expect(rewritten(), isFalse);
      clock.nowMs += 1;
      expect(rewritten(), isTrue);
      clock.nowMs -= 1000;
      expect(rewritten(), isTrue);
    },
  );

  test(
    'a timer refresh rewrites the row once, also right after a transaction rewrote it',
    () async {
      // Fails if refreshLease leaves the rewrite to extendIfDue alone (sqlite_connection.dart,
      // refreshLease): the gap between two writes could then reach 7.5 s, the whole observation.
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      fixture.clock.advance(const Duration(seconds: 3));
      store.begin();
      store.commit();
      final int afterTransaction = currentLease().expiresAtMs;

      fixture.clock.advance(const Duration(seconds: 2));
      store.refreshLease();

      expect(currentLease().expiresAtMs, greaterThan(afterTransaction));
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
    // Fails if tryAcquire stops comparing `processOf` (previousOwnerSameProcess). What the opener
    // does with the flag is pinned in sqlite_open_test.dart, "quick check after a vanished owner".
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

  test(
    'an owner that lost its lease without noticing does not release the new owner on close',
    () async {
      // m20. Fails if SqliteLease.release deletes the row without `owner_id = ? AND epoch = ?`
      // (sqlite_lease.dart:287): the new owner's row is gone and its next transaction is fenced.
      final SqliteConnection first = await fixture.open();
      // No refresh: the second open takes the file over. The first has run no transaction since,
      // so it still counts itself durable.
      final SqliteConnection second = await fixture.open();
      addTearDown(second.close);
      expect(first.state, StoreState.durable);

      first.close();

      final LeaseRow? lease = leaseOrNull();
      expect(lease?.ownerId, 'owner-2');
      expect(lease?.epoch, 2);
      expect(second.begin(), isTrue);
      second.commit();
      expect(second.state, StoreState.durable);
    },
  );

  test(
    'an expired tombstone no longer keeps the file: it is taken over after one observation',
    () async {
      // m21. Fails if SqliteLease._isLiveTombstone ignores the time (sqlite_lease.dart:330): the
      // open sees a file being deleted and keeps data in memory.
      (await fixture.open()).close();
      writeLease(
        SqliteLease.clearingOwnerId,
        epoch: 4,
        expiresAtMs: fixture.clock.nowMs - 1,
      );

      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);

      expect(store.state, StoreState.durable);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
      expect(currentLease().ownerId, 'owner-2');
      expect(currentLease().epoch, 5);
    },
  );

  group('refresh timer', () {
    test('the opener arms one timer of 5 s; a tick rewrites the row', () async {
      // Fails without `connection.startLeaseRefresh()` in the opener (sqlite_open.dart:250), or
      // with another period in SqliteConnection.startLeaseRefresh.
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      final FakePeriodicTimer timer = fixture.timers.single;
      expect(timer.period, const Duration(seconds: 5));
      final int before = currentLease().expiresAtMs;

      fixture.clock.advance(const Duration(seconds: 5));
      timer.fire();

      expect(currentLease().expiresAtMs, greaterThan(before));
      expect(timer.isActive, isTrue);
      expect(store.state, StoreState.durable);
    });

    test('close cancels the timer', () async {
      // Fails without `_refreshTimer?.cancel()` in SqliteConnection.close.
      final SqliteConnection store = await fixture.open();
      final FakePeriodicTimer timer = fixture.timers.single;

      store.close();

      expect(timer.isActive, isFalse);
    });

    test(
      'a tick after another owner took the lease fences and cancels',
      () async {
        // Fails without `_refreshTimer?.cancel()` in SqliteConnection._stopWriting.
        final SqliteConnection store = await fixture.open();
        addTearDown(store.close);
        final FakePeriodicTimer timer = fixture.timers.single;
        writeLease('intruder', epoch: 9, expiresAtMs: 0);

        timer.fire();

        expect(store.state, StoreState.fenced);
        expect(timer.isActive, isFalse);
        expect(currentLease().ownerId, 'intruder');
      },
    );

    test(
      'three ticks on a busy file degrade the store and cancel the timer',
      () async {
        // Fails without `_refreshTimer?.cancel()` in SqliteConnection._stopWriting, or if a busy
        // refresh is not counted toward maxConsecutiveBusy.
        final SqliteConnection store = await fixture.open();
        addTearDown(store.close);
        final FakePeriodicTimer timer = fixture.timers.single;
        final sqlite.Database other = fixture.raw();
        addTearDown(() => StoreFixture.closeRaw(other));
        other.execute('BEGIN IMMEDIATE');

        timer.fire();
        timer.fire();
        expect(store.state, StoreState.durable);
        timer.fire();
        other.execute('ROLLBACK');

        expect(store.state, StoreState.degraded);
        expect(timer.isActive, isFalse);
      },
    );
  });
}
