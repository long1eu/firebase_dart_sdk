// The close of a degraded store changes the file only while it is provably still its own: never
// another instance's pending writes, never a file a clear deleted.
@TestOn('vm')
library;

import 'dart:io';

import 'package:firebase_database_dart/storage_engine.dart';
import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:firebase_database_dart_sqlite/src/posix_file_mode.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;
  final PersistenceKey key = PersistenceKey(
    appName: '[DEFAULT]',
    databaseUrl: Uri.parse('https://demo-test-default-rtdb.firebaseio.com'),
  );
  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  SqlitePersistence persistence() =>
      SqlitePersistence(fixture.directory, options: fixture.options());

  void run(PersistenceStorageEngine engine, void Function() body) {
    engine.beginTransaction();
    try {
      body();
      engine.setTransactionSuccessful();
    } finally {
      engine.endTransaction();
    }
  }

  void save(PersistenceStorageEngine engine, int id) => run(
    engine,
    () => engine.saveUserOverwrite(Path('w$id'), nodeFromJson(id), id),
  );

  List<Object?> idsOnDisk(String path) {
    final sqlite.Database raw = sqlite.sqlite3.open(path);
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

  /// Opens store A, saves write 1 and degrades it: three lease refreshes refused as busy.
  Future<PersistenceStorageEngine> degradedWithWrite1(String path) async {
    final PersistenceStorageEngine a = await persistence().open(key);
    save(a, 1);
    final sqlite.Database other = sqlite.sqlite3.open(path);
    other.execute('BEGIN IMMEDIATE');
    try {
      for (int i = 0; i < 3; i++) {
        fixture.timers.first.fire();
      }
    } finally {
      other.execute('ROLLBACK');
      StoreFixture.closeRaw(other);
    }
    expect(a.isDurable, isFalse);
    return a;
  }

  test(
    'the close keeps the pending write of an instance that took the file over',
    () async {
      final String path = persistence().pathOf(key);
      final PersistenceStorageEngine a = await degradedWithWrite1(path);
      // Write 2 is made after the error (memory only); the server answers 1 and 2.
      save(a, 2);
      run(a, () => a.removeUserWrite(1));
      run(a, () => a.removeUserWrite(2));

      // B takes the file over (after one observation), loads write 1 and makes its own write 2.
      final PersistenceStorageEngine b = await persistence().open(key);
      expect(b.isDurable, isTrue);
      expect(b.loadUserWrites().map((UserWriteRecord w) => w.writeId), <int>[
        1,
      ]);
      save(b, 2);
      b.close();

      a.close();

      expect(idsOnDisk(path), <Object?>[1, 2]);
      expect(fixture.log.last, contains('taken over or cleared'));
    },
  );

  test(
    'a purge after the error does not delete the writes of a later owner',
    () async {
      final String path = persistence().pathOf(key);
      final PersistenceStorageEngine a = await degradedWithWrite1(path);
      run(a, a.removeAllUserWrites);

      final PersistenceStorageEngine b = await persistence().open(key);
      expect(b.isDurable, isTrue);
      save(b, 5);
      save(b, 6);
      b.close();
      a.close();

      expect(idsOnDisk(path), <Object?>[1, 5, 6]);
    },
  );

  test('after a clear, the write of a fresh store is kept', () async {
    final String path = persistence().pathOf(key);
    final PersistenceStorageEngine a = await degradedWithWrite1(path);
    run(a, () => a.removeUserWrite(1));
    await persistence().clear(key);
    expect(File(path).existsSync(), isFalse);

    final PersistenceStorageEngine c = await persistence().open(key);
    save(c, 1);
    c.close();
    a.close();

    expect(idsOnDisk(path), <Object?>[1]);
  });

  test('the close does not re-create a cleared file', () async {
    final String path = persistence().pathOf(key);
    final PersistenceStorageEngine a = await degradedWithWrite1(path);
    run(a, () => a.removeUserWrite(1));
    await persistence().clear(key);

    a.close();

    expect(Directory(fixture.directory).listSync(), isEmpty);
  });

  test(
    'with nobody else on the file, the close removes the answered write, releases the lease '
    'and keeps mode 0600',
    () async {
      final String path = persistence().pathOf(key);
      final PersistenceStorageEngine a = await degradedWithWrite1(path);
      save(a, 2);
      run(a, () => a.removeUserWrite(1));
      run(a, () => a.removeUserWrite(2));

      a.close();

      expect(idsOnDisk(path), isEmpty);
      expect(fixture.log.last, contains('1 write(s)'));
      final sqlite.Database raw = sqlite.sqlite3.open(path);
      expect(raw.select('SELECT * FROM lease'), isEmpty);
      StoreFixture.closeRaw(raw);
      if (PosixFileMode.forCurrentPlatform() != null) {
        for (final FileSystemEntity file in Directory(
          fixture.directory,
        ).listSync()) {
          expect(
            PosixFileMode.permissionBits(file.path),
            PosixFileMode.privateFile,
            reason: file.path,
          );
        }
      }
    },
  );
}
