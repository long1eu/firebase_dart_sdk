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
    'E-L1 a second open waits one lease period, then keeps data in memory',
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
      expect(
        fixture.clock.delays.single,
        lessThanOrEqualTo(SqliteLease.duration + SqliteLease.takeOverSlack),
      );
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
}
