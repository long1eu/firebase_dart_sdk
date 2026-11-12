import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'mock/database_mock.dart';

/// Creates (but does not start) a persistence on the file [name], without renaming the file on close.
Future<SQLitePersistence> open(String name) {
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  return SQLitePersistence.create(
    name,
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    (String path,
        {int? version,
        OnConfigure? onConfigure,
        OnCreate? onCreate,
        OnVersionChange? onUpgrade,
        OnVersionChange? onDowngrade,
        OnOpen? onOpen}) async {
      final DatabaseMock db = await DatabaseMock.create(
          SQLitePersistence.sDatabaseName(name, databaseId),
          version: version,
          onConfigure: onConfigure,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
          onDowngrade: onDowngrade,
          onOpen: onOpen);
      db.renamePath = false;
      return db;
    },
    const LruGarbageCollectorParams(),
  );
}

void main() {
  // Issue #1: a hot restart leaves the old handle open and the new isolate opens the same file again. The database is
  // never opened in exclusive locking mode, so that has to work and must not corrupt the file.
  test('two persistences can be open on the same database file', () async {
    final String name = 'shared-${const Uuid().v4()}';
    final String dbName = SQLitePersistence.sDatabaseName(
        name, DatabaseId.forProject('projectId'));
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));

    final SQLitePersistence first = await open(name);
    await first.start();
    final SQLitePersistence second = await open(name);
    await second.start();

    for (final SQLitePersistence p in <SQLitePersistence>[first, second]) {
      final List<Map<String, dynamic>> mode =
          await p.query('PRAGMA locking_mode');
      expect(mode.single.values.single, 'normal');
    }

    await first.execute('CREATE TABLE IF NOT EXISTS probe (v INTEGER)');
    await first.runTransaction('write', () async {
      await first.execute('INSERT INTO probe (v) VALUES (?)', <Object?>[42]);
    });
    final List<Map<String, dynamic>> rows =
        await second.query('SELECT v FROM probe');
    expect(rows.single['v'], 42);

    // The old handle going away (hot restart) leaves the other one usable.
    await first.shutdown();
    await second.runTransaction('write', () async {
      await second.execute('INSERT INTO probe (v) VALUES (?)', <Object?>[43]);
    });
    final List<Map<String, dynamic>> check =
        await second.query('PRAGMA integrity_check');
    expect(check.single.values.single, 'ok');
    expect((await second.query('SELECT v FROM probe')).length, 2);
    await second.shutdown();
  });

  // Issue #2: persistence work of one Firestore instance must not wait for another one.
  test('a long transaction on one database does not block another database',
      () async {
    final SQLitePersistence a = await open('iso-a-${const Uuid().v4()}');
    final SQLitePersistence b = await open('iso-b-${const Uuid().v4()}');
    await a.start();
    await b.start();
    addTearDown(() async {
      await a.shutdown();
      await b.shutdown();
    });

    final Completer<void> release = Completer<void>();
    final Completer<void> inside = Completer<void>();
    final Future<void> held = a.runTransaction('hold', () async {
      inside.complete();
      await release.future;
    });
    await inside.future;

    var ran = false;
    await b.runTransaction('other', () async {
      ran = true;
    }).timeout(const Duration(seconds: 5));
    expect(ran, isTrue);

    release.complete();
    await held;
  });
}
