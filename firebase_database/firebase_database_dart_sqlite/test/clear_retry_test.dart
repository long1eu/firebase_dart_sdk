// A clear whose deletion failed removes its tombstone, so the file can be opened and the clear
// retried at once; a clear refused by a live tombstone says why and when a retry works.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_lease.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;
  late SqlitePersistence persistence;
  final PersistenceKey key = PersistenceKey(
    appName: '[DEFAULT]',
    databaseUrl: Uri.parse('https://demo-test-default-rtdb.firebaseio.com'),
  );

  setUp(() {
    fixture = StoreFixture();
    persistence = SqlitePersistence(
      fixture.directory,
      options: fixture.options(),
    );
  });
  tearDown(() => fixture.dispose());

  LeaseRow? readLease(String path) {
    final sqlite.Database db = sqlite.sqlite3.open(path);
    try {
      return SqliteLease.read(db);
    } finally {
      StoreFixture.closeRaw(db);
    }
  }

  /// A directory where the rollback journal of [path] would be: it can not be deleted as a file.
  Directory blockJournal(String path) {
    final Directory blocker = Directory('$path-journal')..createSync();
    File(SqliteFiles.join(blocker.path, 'x')).writeAsStringSync('x');
    return blocker;
  }

  /// A clear of [path] that fails on the journal path; the blocker is gone afterwards. The file
  /// has the lease row of a crashed owner, so the clear watches it for one observation period;
  /// the journal directory appears meanwhile, after the tombstone check read the file. It also
  /// makes the file unreadable, so the clear can not remove its tombstone at that moment.
  Future<void> failedClear(String path) async {
    (await persistence.open(key)).close();
    final sqlite.Database raw = sqlite.sqlite3.open(path);
    raw.execute(
      "INSERT OR REPLACE INTO lease (id, owner_id, epoch, expires_at_ms) VALUES (0, '17:crashed', "
      '3, 0)',
    );
    StoreFixture.closeRaw(raw);
    Directory? blocker;
    fixture.clock.onAdvance = () => blocker ??= blockJournal(path);
    await expectLater(
      persistence.clear(key),
      throwsA(isA<ClearPersistenceException>()),
    );
    fixture.clock.onAdvance = null;
    blocker!.deleteSync(recursive: true);
    expect(File(path).existsSync(), isTrue);
    expect(readLease(path)?.ownerId, SqliteLease.clearingOwnerId);
    expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
  }

  test('a clear retried after a failed one deletes the file at once', () async {
    final String path = persistence.pathOf(key);
    await failedClear(path);

    // A new object, as every call of clearSqlitePersistence makes.
    await SqlitePersistence(
      fixture.directory,
      options: fixture.options(),
    ).clear(key);

    expect(File(path).existsSync(), isFalse);
    expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
  });

  test(
    'an open after a failed clear removes its tombstone and is durable',
    () async {
      final String path = persistence.pathOf(key);
      await failedClear(path);

      final PersistenceStorageEngine engine = await SqlitePersistence(
        fixture.directory,
        options: fixture.options(),
      ).open(key);

      expect(engine.isDurable, isTrue);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
      engine.close();
      expect(readLease(path), isNull);
    },
  );

  test(
    'a clear refused by a live tombstone says so and when a retry works',
    () async {
      final String path = persistence.pathOf(key);
      (await persistence.open(key)).close();
      // The tombstone of another clear that is running (or that failed and could not remove it).
      final sqlite.Database other = sqlite.sqlite3.open(path);
      expect(
        SqliteLease.writeTombstone(
          other,
          observed: null,
          nowMs: fixture.clock.nowMs,
        ),
        isTrue,
      );
      StoreFixture.closeRaw(other);
      fixture.clock.advance(const Duration(seconds: 15));

      await expectLater(
        persistence.clear(key),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(
              contains('Another clear'),
              contains('could not remove its mark'),
              contains('retry in about 45 s'),
            ),
          ),
        ),
      );
      expect(File(path).existsSync(), isTrue);
    },
  );

  test(
    'a mark of another isolate refuses a second clear until it expires, then the clear runs '
    'after one observation',
    () async {
      final String path = persistence.pathOf(key);
      (await persistence.open(key)).close();
      // Another isolate's clear failed and could not remove its mark: this isolate does not know it.
      final sqlite.Database other = sqlite.sqlite3.open(path);
      expect(
        SqliteLease.writeTombstone(
          other,
          observed: null,
          nowMs: fixture.clock.nowMs,
        ),
        isTrue,
      );
      StoreFixture.closeRaw(other);

      await expectLater(persistence.clear(key), throwsStateError);
      expect(File(path).existsSync(), isTrue);

      fixture.clock.advance(
        SqliteLease.tombstoneDuration + const Duration(milliseconds: 1),
      );
      await persistence.clear(key);

      expect(File(path).existsSync(), isFalse);
      expect(fixture.clock.delays, <Duration>[SqliteLease.observation]);
    },
  );
}
