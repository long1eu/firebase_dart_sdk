// SqliteFiles.moveAside on plain files (E-V2 and E-V3 of rtdb_storage_engine_design.md section
// 15, new). Plain files, not SQLite: an open SQLite connection replaces a stale log by itself,
// which hid the move of the log in the store-level test.
import 'dart:io';

import 'package:firebase_database_dart_sqlite/src/sqlite_files.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String path;
  final DateTime now = DateTime.utc(2026, 1, 2, 3, 4, 5);
  const String stamp = '20260102T030405';

  setUp(() {
    root = Directory.systemTemp.createTempSync('rtdb_sqlite_files_');
    path = SqliteFiles.join(root.path, 'rtdb-test.sqlite');
    File(path).writeAsStringSync('database');
    File('$path-wal').writeAsStringSync('old log');
    File('$path-journal').writeAsStringSync('old journal');
    File('$path-shm').writeAsStringSync('index');
  });
  tearDown(() => root.deleteSync(recursive: true));

  String target([String suffix = '']) =>
      '$path${SqliteFiles.badInfix}$stamp$suffix';

  test(
    'E-V2 the log and the journal move with the file; the index is deleted',
    () {
      expect(SqliteFiles.moveAside(path, now), isTrue);

      expect(File(target()).readAsStringSync(), 'database');
      expect(File(target('-wal')).readAsStringSync(), 'old log');
      expect(File(target('-journal')).readAsStringSync(), 'old journal');
      for (final String suffix in <String>['', '-wal', '-journal', '-shm']) {
        expect(
          File('$path$suffix').existsSync(),
          isFalse,
          reason: 'left: $suffix',
        );
      }
      expect(File(target('-shm')).existsSync(), isFalse);
    },
  );

  test(
    'E-V2 a log that can not be moved is deleted, never left next to the new file',
    () {
      // A non-empty directory where the moved log would go makes its rename fail.
      final Directory blocker = Directory(target('-wal'))..createSync();
      File(SqliteFiles.join(blocker.path, 'x')).writeAsStringSync('x');

      expect(SqliteFiles.moveAside(path, now), isTrue);

      expect(File('$path-wal').existsSync(), isFalse);
      expect(blocker.existsSync(), isTrue);
      expect(File(target()).readAsStringSync(), 'database');
      expect(File(target('-journal')).readAsStringSync(), 'old journal');
    },
  );

  test(
    'a file that can not be moved leaves everything in place and reports it',
    () {
      final Directory blocker = Directory(target())..createSync();
      File(SqliteFiles.join(blocker.path, 'x')).writeAsStringSync('x');

      expect(SqliteFiles.moveAside(path, now), isFalse);

      expect(File(path).readAsStringSync(), 'database');
      expect(File('$path-wal').readAsStringSync(), 'old log');
      expect(File('$path-journal').readAsStringSync(), 'old journal');
    },
  );

  test(
    'E-V3 earlier moved-aside copies are deleted before the new one is made',
    () {
      File(
        '$path${SqliteFiles.badInfix}20250101T000000',
      ).writeAsStringSync('older');
      File(
        '$path${SqliteFiles.badInfix}20250101T000000-wal',
      ).writeAsStringSync('older log');

      expect(SqliteFiles.moveAside(path, now), isTrue);

      expect(
        SqliteFiles.badCopies(path).map((File f) => f.path).toSet(),
        <String>{target(), target('-wal'), target('-journal')},
      );
    },
  );
}
