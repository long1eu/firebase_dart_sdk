// The factory and file naming (E-F1 and E-P3 of rtdb_storage_engine_design.md section 15).
// E-F1 replaces Android's SqlPersistenceStorageEngineTest testAllowedSessionIdCharacters: the
// name is a hash here, so any app name and URL are safe.
import 'dart:io';

import 'package:firebase_database_dart_sqlite/firebase_database_dart_sqlite.dart';
import 'package:firebase_database_dart_sqlite/src/engine_contract_placeholder.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;
  late SqlitePersistence persistence;
  final Uri url = Uri.parse('https://demo-test-default-rtdb.firebaseio.com');
  final PersistenceKey key = PersistenceKey(
    appName: '[DEFAULT]',
    databaseUrl: url,
  );

  setUp(() {
    fixture = StoreFixture();
    persistence = SqlitePersistence(
      fixture.directory,
      options: fixture.options(),
    );
  });
  tearDown(() => fixture.dispose());

  group('E-F1 file names', () {
    test('are rtdb-, 32 hex digits and .sqlite for any app name and URL', () {
      const String odd = r'.?!@$%^&*()\/-~{}π∞٩(-̮̮̃-̃)۶ ٩(●̮̮̃•̃)۶';
      for (final String app in <String>['[DEFAULT]', odd, '', '../..']) {
        expect(
          SqliteFiles.fileName(
            app,
            Uri.parse('https://x.firebaseio.com/?ns=$app'),
          ),
          matches(RegExp(r'^rtdb-[0-9a-f]{32}\.sqlite$')),
        );
      }
    });

    test('are stable and differ by app and by URL', () {
      final String base = SqliteFiles.fileName('[DEFAULT]', url);
      expect(SqliteFiles.fileName('[DEFAULT]', url), base);
      expect(SqliteFiles.fileName('other', url), isNot(base));
      expect(
        SqliteFiles.fileName(
          '[DEFAULT]',
          Uri.parse('https://other.firebaseio.com'),
        ),
        isNot(base),
      );
    });
  });

  group('sqlitePersistence', () {
    test('checks its arguments', () {
      expect(() => sqlitePersistence(''), throwsArgumentError);
      expect(
        () => sqlitePersistence(
          '/tmp/x',
          cacheSizeBytes: minimumCacheSizeBytes - 1,
        ),
        throwsRangeError,
      );
      expect(
        () => sqlitePersistence(
          '/tmp/x',
          cacheSizeBytes: maximumCacheSizeBytes + 1,
        ),
        throwsRangeError,
      );
      expect(sqlitePersistence('/tmp/x').cacheSizeBytes, defaultCacheSizeBytes);
      final PersistenceStorageEngineOpener opener = sqlitePersistence(
        '/tmp/x',
      ).opener;
      expect(opener, isNotNull);
    });

    test('opens a durable store in the directory', () async {
      final PersistenceStorageEngine engine = await persistence.open(key);
      addTearDown(engine.close);

      expect(engine.isDurable, isTrue);
      expect(File(persistence.pathOf(key)).existsSync(), isTrue);
    });

    test('a second open of the same database is memory-only at once', () async {
      final PersistenceStorageEngine first = await persistence.open(key);
      addTearDown(first.close);

      final PersistenceStorageEngine second = await persistence.open(key);

      expect(second.isDurable, isFalse);
      expect(fixture.clock.delays, isEmpty);
      expect(fixture.log.single, contains('another instance'));
    });

    test('after a close the database opens durably again', () async {
      (await persistence.open(key)).close();

      final PersistenceStorageEngine again = await persistence.open(key);
      addTearDown(again.close);

      expect(again.isDurable, isTrue);
      expect(fixture.clock.delays, isEmpty);
    });
  });

  group('E-P3 clear', () {
    test(
      'deletes the file, its side files and its moved-aside copies',
      () async {
        final String path = persistence.pathOf(key);
        (await persistence.open(key)).close();
        File('$path.bad-20260101T000000').writeAsStringSync('old');
        File('$path.bad-20260101T000000-wal').writeAsStringSync('old log');
        File('$path-journal').writeAsStringSync('journal');

        await persistence.clear(key);

        final List<String> left = <String>[
          for (final FileSystemEntity e in Directory(
            fixture.directory,
          ).listSync())
            e.path,
        ];
        expect(left, isEmpty);
      },
    );

    test('is refused while this persistence has the store open', () async {
      final PersistenceStorageEngine engine = await persistence.open(key);
      addTearDown(engine.close);

      await expectLater(persistence.clear(key), throwsStateError);
    });

    test('is refused while another process holds a live lease', () async {
      final SqlitePersistence other = SqlitePersistence(
        fixture.directory,
        options: fixture.options(),
      );
      final PersistenceStorageEngine engine = await other.open(key);
      addTearDown(engine.close);

      await expectLater(persistence.clear(key), throwsStateError);
      expect(File(persistence.pathOf(key)).existsSync(), isTrue);
    });

    test('of a database that never existed does nothing', () async {
      await persistence.clear(key);

      expect(Directory(fixture.directory).existsSync(), isFalse);
    });

    test('of a damaged file deletes it', () async {
      final String path = persistence.pathOf(key);
      Directory(fixture.directory).createSync(recursive: true);
      File(path).writeAsBytesSync(List<int>.filled(4096, 0x78));

      await persistence.clear(key);

      expect(File(path).existsSync(), isFalse);
      expect(SqliteFiles.badCopies(path), isEmpty);
    });
  });
}
