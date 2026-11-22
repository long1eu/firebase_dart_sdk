// E-P1 and E-P2 of rtdb_storage_engine_design.md section 15 (new). Windows has no POSIX modes.
@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_database_dart_sqlite/src/posix_file_mode.dart';
import 'package:firebase_database_dart_sqlite/src/sqlite_connection.dart';
import 'package:test/test.dart';

import 'support/store_fixture.dart';

void main() {
  late StoreFixture fixture;
  final PosixFileMode mode = PosixFileMode.forCurrentPlatform()!;

  setUp(() => fixture = StoreFixture());
  tearDown(() => fixture.dispose());

  test(
    'E-P1 a new store directory is 0700; the file and its log are 0600',
    () async {
      final SqliteConnection store = await fixture.open();
      addTearDown(store.close);
      store.begin();
      store.execute(
        'INSERT INTO user_writes (id, path, type, value) VALUES (1, ?, ?, ?)',
        <Object?>['/a/', 'o', Uint8List(1)],
      );
      store.commit();

      expect(PosixFileMode.permissionBits(fixture.directory), 0x1C0);
      expect(PosixFileMode.permissionBits(fixture.path), 0x180);
      final File log = File('${fixture.path}-wal');
      expect(log.existsSync(), isTrue);
      expect(
        PosixFileMode.permissionBits(log.path) &
            PosixFileMode.groupAndOtherBits,
        0,
      );
    },
  );

  test('E-P2 an existing file loses its group and other bits', () async {
    Directory(fixture.directory).createSync(recursive: true);
    File(fixture.path).createSync();
    expect(mode.setMode(fixture.path, 0x1A4), isTrue); // 0644

    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    expect(store.state, StoreState.durable);
    expect(PosixFileMode.permissionBits(fixture.path), 0x180);
  });

  test('an existing directory belongs to the app and keeps its mode', () async {
    Directory(fixture.directory).createSync(recursive: true);
    expect(mode.setMode(fixture.directory, 0x1ED), isTrue); // 0755

    final SqliteConnection store = await fixture.open();
    addTearDown(store.close);

    expect(PosixFileMode.permissionBits(fixture.directory), 0x1ED);
    expect(PosixFileMode.permissionBits(fixture.path), 0x180);
  });
}
