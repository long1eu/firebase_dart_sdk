// How a SQLitePersistence handles its database file (review follow-ups L1 and L2):
//  * two persistences with different names that their openers map to the same file (two apps, or a custom
//    OpenDatabase) are serialized by the file, not only by the name: a transaction that one holds across an await
//    makes the other wait instead of blocking the isolate in SQLite's busy handler;
//  * a start that fails after the database was opened closes it again.

@TestOn('vm')
library;

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:firebase_app_dart/internal.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'mock/database_mock.dart';

final DatabaseId _databaseId = DatabaseId.forProject('projectId');

/// A database that fails the first query matching [failOn] and records whether it was closed.
class _FailingDatabase extends Database {
  _FailingDatabase(this._delegate, this.failOn);

  final Database _delegate;
  bool Function(String statement)? failOn;
  bool closed = false;

  void _check(String statement) {
    final bool Function(String statement)? fail = failOn;
    if (fail != null && fail(statement)) {
      failOn = null;
      throw StateError('injected failure: $statement');
    }
  }

  @override
  String get path => _delegate.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) {
    _check(statement);
    return _delegate.execute(statement, arguments);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) {
    _check(statement);
    return _delegate.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) {
    _check(statement);
    return _delegate.delete(statement, arguments);
  }

  @override
  void close() {
    closed = true;
    _delegate.close();
  }
}

/// An opener that opens the file [dbName] whatever name it is asked for; [wrap] may wrap the database.
OpenDatabase _openFile(String dbName, {Database Function(Database db)? wrap}) {
  return (
    String path, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    final DatabaseMock db = await DatabaseMock.create(
      dbName,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onDowngrade: onDowngrade,
      onOpen: onOpen,
    );
    db.renamePath = false;
    return wrap == null ? db : wrap(db);
  };
}

/// A database whose `PRAGMA journal_mode = WAL` fails [failures] times with [error] (forever when null).
class _SwitchFailingDatabase extends Database {
  _SwitchFailingDatabase(this._delegate, this.error, {this.failures});

  final DatabaseMock _delegate;
  final Object error;
  final int? failures;
  int attempts = 0;

  @override
  String get path => _delegate.path;

  @override
  Future<void> execute(String statement, [List<Object?>? arguments]) =>
      _delegate.execute(statement, arguments);

  @override
  Future<List<Map<String, dynamic>>> query(
    String statement, [
    List<Object?>? arguments,
  ]) {
    if (statement.toUpperCase() == 'PRAGMA JOURNAL_MODE = WAL') {
      attempts++;
      final int? limit = failures;
      if (limit == null || attempts <= limit) {
        throw error;
      }
    }
    return _delegate.query(statement, arguments);
  }

  @override
  Future<int> delete(String statement, [List<Object?>? arguments]) =>
      _delegate.delete(statement, arguments);

  @override
  void close() => _delegate.close();
}

/// An opener of a new file [dbName] that runs the callbacks on [wrap] of the database, so that the wrapper also sees
/// the statements of onConfigure.
OpenDatabase _openNewWrapped(
  String dbName,
  Database Function(DatabaseMock db) wrap,
) {
  return (
    String path, {
    int? version,
    OnConfigure? onConfigure,
    OnCreate? onCreate,
    OnVersionChange? onUpgrade,
    OnVersionChange? onDowngrade,
    OnOpen? onOpen,
  }) async {
    final DatabaseMock mock = await DatabaseMock.create(dbName)
      ..renamePath = false;
    mock.database.userVersion = 0;
    final Database db = wrap(mock);
    await onConfigure?.call(db);
    await onCreate?.call(db, version!);
    mock.database.userVersion = version!;
    await onOpen?.call(db);
    return db;
  };
}

/// Runs [body] with the log at [level] and returns what was printed.
Future<List<String>> _printed(
  InternalLogLevel level,
  Future<void> Function() body,
) async {
  final InternalLogLevel original = Log.level;
  final List<String> printed = <String>[];
  Log.level = level;
  try {
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
            printed.add(line),
      ),
    );
  } finally {
    Log.level = original;
  }
  return printed;
}

Future<SQLitePersistence> _create(String key, OpenDatabase opener) {
  return SQLitePersistence.create(
    key,
    _databaseId,
    LocalSerializer(RemoteSerializer(_databaseId)),
    opener,
    const LruGarbageCollectorParams(),
  );
}

void main() {
  late String dbName;
  final List<SQLitePersistence> started = <SQLitePersistence>[];

  setUp(() {
    dbName = 'file-${const Uuid().v4()}.db';
  });

  tearDown(() async {
    for (final SQLitePersistence persistence in started) {
      if (persistence.started) {
        await persistence.shutdown();
      }
    }
    started.clear();
    DatabaseMock.deleteDatabaseFiles(dbName);
  });

  Future<SQLitePersistence> start(String key, {OpenDatabase? opener}) async {
    final SQLitePersistence persistence = await _create(
      key,
      opener ?? _openFile(dbName),
    );
    started.add(persistence);
    await persistence.start();
    return persistence;
  }

  /// Runs a transaction on [persistence] that writes a row and then waits for [release].
  Future<void> holdWrite(
    SQLitePersistence persistence,
    Completer<void> inside,
    Future<void> release,
  ) {
    return persistence.runTransaction('hold', () async {
      await persistence.execute('INSERT INTO probe (v) VALUES (1)');
      inside.complete();
      await release;
    });
  }

  group('two names on one file (L1)', () {
    test(
      'a transaction held across an await makes the other one wait',
      () async {
        final SQLitePersistence a = await start('app-a');
        final SQLitePersistence b = await start('app-b');
        expect(a.databaseName, isNot(b.databaseName));
        await a.execute('CREATE TABLE probe (v INTEGER)');

        final Completer<void> inside = Completer<void>();
        final Completer<void> release = Completer<void>();
        final Future<void> held = holdWrite(a, inside, release.future);
        await inside.future;

        final Stopwatch watch = Stopwatch()..start();
        bool bDone = false;
        final Future<void> other = b
            .runTransaction('other', () async {
              await b.execute('INSERT INTO probe (v) VALUES (2)');
            })
            .then((_) => bDone = true);
        // B waits for A without blocking the isolate: this timer fires on time.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(bDone, isFalse);
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

        release.complete();
        await held;
        await other.timeout(const Duration(seconds: 5));
        expect(
          (await b.query(
            'SELECT v FROM probe ORDER BY v',
          )).map((Map<String, dynamic> row) => row['v']),
          <int>[1, 2],
        );
      },
    );

    test('a client that starts while the other holds a transaction waits for '
        'it', () async {
      final SQLitePersistence a = await start('app-a');
      await a.execute('CREATE TABLE probe (v INTEGER)');

      final Completer<void> inside = Completer<void>();
      final Completer<void> release = Completer<void>();
      final Future<void> held = holdWrite(a, inside, release.future);
      await inside.future;

      final Future<SQLitePersistence> starting = start('app-b');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      release.complete();
      await held;
      final SQLitePersistence b = await starting.timeout(
        const Duration(seconds: 5),
      );
      expect(b.started, isTrue);
      expect(await b.query('SELECT v FROM probe'), hasLength(1));
    });
  });

  group('journal mode', () {
    test('a cache in the default rollback-journal mode is switched to '
        'write-ahead logging', () async {
      final SQLitePersistence a = await start('app-a');
      expect(await a.query('PRAGMA journal_mode'), <Object>[
        <String, Object?>{'journal_mode': 'wal'},
      ]);
      // A second client on the file finds it in WAL mode.
      final SQLitePersistence b = await start('app-b');
      expect(await b.query('PRAGMA journal_mode'), <Object>[
        <String, Object?>{'journal_mode': 'wal'},
      ]);
    });

    test('a journal mode that the opener chose is kept', () async {
      final OpenDatabase opener =
          (
            String path, {
            int? version,
            OnConfigure? onConfigure,
            OnCreate? onCreate,
            OnVersionChange? onUpgrade,
            OnVersionChange? onDowngrade,
            OnOpen? onOpen,
          }) async {
            final DatabaseMock db = await DatabaseMock.create(
              dbName,
              version: version,
              onConfigure: (Database db) async {
                await db.query('PRAGMA journal_mode = TRUNCATE');
                await onConfigure?.call(db);
              },
              onCreate: onCreate,
              onUpgrade: onUpgrade,
              onDowngrade: onDowngrade,
              onOpen: onOpen,
            );
            return db..renamePath = false;
          };
      final SQLitePersistence a = await start('app-a', opener: opener);
      expect(await a.query('PRAGMA journal_mode'), <Object>[
        <String, Object?>{'journal_mode': 'truncate'},
      ]);
    });

    // Another connection opening the file at the same moment makes the switch fail with SQLITE_BUSY.
    final Object busy = StateError(
      'SqliteException(5): while selecting from statement, database is locked',
    );

    test('a switch that finds the database busy is tried again', () async {
      late _SwitchFailingDatabase db;
      late SQLitePersistence a;
      final List<String> printed = await _printed(InternalLogLevel.d, () async {
        a = await start(
          'app-a',
          opener: _openNewWrapped(
            dbName,
            (DatabaseMock mock) =>
                db = _SwitchFailingDatabase(mock, busy, failures: 2),
          ),
        );
      });
      expect(db.attempts, 3);
      expect(await a.query('PRAGMA journal_mode'), <Object>[
        <String, Object?>{'journal_mode': 'wal'},
      ]);
      expect(printed.where((String line) => line.startsWith('W:')), isEmpty);
    });

    test('a database that stays busy keeps its mode, logged at debug level '
        'only', () async {
      late _SwitchFailingDatabase db;
      late SQLitePersistence a;
      final List<String> printed = await _printed(InternalLogLevel.d, () async {
        a = await start(
          'app-a',
          opener: _openNewWrapped(
            dbName,
            (DatabaseMock mock) => db = _SwitchFailingDatabase(mock, busy),
          ),
        );
      });
      expect(db.attempts, 6, reason: 'the first try and five retries');
      expect(a.started, isTrue);
      expect(await a.query('PRAGMA journal_mode'), <Object>[
        <String, Object?>{'journal_mode': 'delete'},
      ]);
      expect(printed.where((String line) => line.startsWith('W:')), isEmpty);
      expect(
        printed.where(
          (String line) =>
              line.startsWith('D:') &&
              line.contains('stays in its journal mode'),
        ),
        hasLength(1),
      );
    });

    test(
      'another failure of the switch is not retried and is a warning',
      () async {
        late _SwitchFailingDatabase db;
        final List<String> printed = await _printed(
          InternalLogLevel.w,
          () async {
            await start(
              'app-a',
              opener: _openNewWrapped(
                dbName,
                (DatabaseMock mock) => db = _SwitchFailingDatabase(
                  mock,
                  StateError('SqliteException(10): disk I/O error'),
                ),
              ),
            );
          },
        );
        expect(db.attempts, 1);
        expect(
          printed.where(
            (String line) =>
                line.startsWith('W:') && line.contains('write-ahead logging'),
          ),
          hasLength(1),
        );
      },
    );
  });

  group('a start that fails after the open (L2)', () {
    test('closes the database, and the file can be used again', () async {
      final List<_FailingDatabase> opened = <_FailingDatabase>[];
      final SQLitePersistence failing = await _create(
        'app-a',
        _openFile(
          dbName,
          wrap: (Database db) {
            final _FailingDatabase wrapped = _FailingDatabase(
              db,
              // Read by the query cache when it starts.
              (String statement) => statement.contains('target_globals'),
            );
            opened.add(wrapped);
            return wrapped;
          },
        ),
      );

      await expectLater(failing.start(), throwsStateError);
      expect(failing.started, isFalse);
      expect(opened.single.closed, isTrue);

      // Neither the lock of the name nor the lock of the file is left taken.
      final SQLitePersistence again = await start(
        'app-a',
      ).timeout(const Duration(seconds: 5));
      expect(again.started, isTrue);
      final SQLitePersistence other = await start(
        'app-b',
      ).timeout(const Duration(seconds: 5));
      await other.runTransaction('use', () async {});
    });

    test('a failure of the client metadata also closes it', () async {
      final List<_FailingDatabase> opened = <_FailingDatabase>[];
      final SQLitePersistence failing = await _create(
        'app-a',
        _openFile(
          dbName,
          wrap: (Database db) {
            final _FailingDatabase wrapped = _FailingDatabase(
              db,
              (String statement) => statement.contains('INTO clients'),
            );
            opened.add(wrapped);
            return wrapped;
          },
        ),
      );

      await expectLater(failing.start(), throwsStateError);
      expect(failing.started, isFalse);
      expect(opened.single.closed, isTrue);
      final SQLitePersistence again = await start(
        'app-a',
      ).timeout(const Duration(seconds: 5));
      expect(again.isPrimary, isTrue);
    });
  });
}
