import 'dart:io';

import 'package:test/test.dart';

import '../../util/sqlite3_database.dart';

void main() {
  test('deleteDatabaseFiles removes the file DatabaseMock.create opened',
      () async {
    const String name = 'unit/sqlite3_database_test_0.db';
    DatabaseMock.deleteDatabaseFiles(name);

    final DatabaseMock db = await DatabaseMock.create(name);
    db.renamePath = false;
    await db.execute('CREATE TABLE t (a INTEGER)');
    db.close();

    final File file = DatabaseMock.pathForName(name);
    expect(file.existsSync(), isTrue);
    // The name is relative to build/test; nothing is nested below it again.
    expect(file.path, '${Directory.current.path}/build/test/$name');

    DatabaseMock.deleteDatabaseFiles(name);
    expect(file.existsSync(), isFalse);

    // A re-created database starts empty (onCreate is called again).
    bool created = false;
    final DatabaseMock again =
        await DatabaseMock.create(name, onCreate: (_, __) async {
      created = true;
    });
    expect(created, isTrue);
    again.renamePath = true;
    again.close();
    DatabaseMock.deleteDatabaseFiles(name);
  });
}
