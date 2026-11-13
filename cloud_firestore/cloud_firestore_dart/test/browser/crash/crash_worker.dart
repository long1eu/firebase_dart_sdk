// The worker of web_persistence_crash_test.dart: it opens a database with the
// opener of example/sqlite_database_web.dart (in IndexedDB, or in OPFS when
// the test passes `opfsWorker`) and writes transactions until the
// test terminates it, at a moment of the test's choosing. Terminating a
// worker ends its JavaScript and aborts its IndexedDB transactions wherever
// they are, like closing the tab does to a page.
//
// Compiled by hand, the test runner only compiles tests:
//
//   dart compile js -O1 -o test/browser/crash/crash_worker.js \
//       test/browser/crash/crash_worker.dart
//
// The messages it posts (strings):
//   open <userVersion>       the database is open
//   ack <id>                 the transaction that inserted <id> was committed,
//                            and its future (which waits for IndexedDB) ended
//   error <text>             anything that went wrong

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:web/web.dart' as web;

import '../../../example/sqlite_database_web.dart';

@JS('self')
external web.DedicatedWorkerGlobalScope get _self;

void _post(String message) => _self.postMessage(message.toJS);

/// The tables of schema version [version]: `log` and `totals` from the
/// start, and one table `v<n>` per later version, created by its migration.
Future<void> migrate(Database db, int from, int to) async {
  // Gives the test a chance to kill the worker between two statements.
  Future<void> pause() => migrationPause == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(migrationPause);
  if (from < 1) {
    await db.execute(
      'CREATE TABLE log (id INTEGER PRIMARY KEY, size INTEGER, payload BLOB)',
    );
    await pause();
    await db.execute('CREATE INDEX log_size ON log (size, id)');
    await pause();
    await db.execute('CREATE TABLE totals (count INTEGER, bytes INTEGER)');
    await db.execute('INSERT INTO totals VALUES (0, 0)');
  }
  for (int v = max(from, 1) + 1; v <= to; v++) {
    await db.execute('CREATE TABLE v$v (id INTEGER PRIMARY KEY, note TEXT)');
    await pause();
    // A data migration over a few statements.
    for (int i = 0; i < 20; i++) {
      await db.execute('INSERT INTO v$v (note) VALUES (?)', <Object?>[
        'migration $v row $i',
      ]);
      if (i % 5 == 0) {
        await pause();
      }
    }
  }
}

/// A pause between the statements of a migration (none by default).
Duration migrationPause = Duration.zero;

Future<void> run(Map<String, Object?> config) async {
  migrationPause = Duration(milliseconds: config['migrationPauseMs']! as int);
  final Random random = Random(config['seed']! as int);
  final int version = config['version']! as int;
  final int largeEvery = config['largeEvery']! as int;
  final int hugeEvery = config['hugeEvery']! as int;

  final Database db =
      await sqliteWebOpener(
        sqlite3Wasm: Uri.parse(config['wasm']! as String),
        // With it the database is in OPFS, in a worker this worker starts and
        // takes down with it when it is terminated.
        opfsWorker: config['opfsWorker'] == null
            ? null
            : Uri.parse(config['opfsWorker']! as String),
        storagePrefix: 'crash-test',
      )(
        config['name']! as String,
        version: version,
        onCreate: (Database db, int to) => migrate(db, 0, to),
        onUpgrade: migrate,
      );
  final int userVersion =
      (await db.query('PRAGMA user_version')).single.values.first as int;
  _post('open $userVersion');

  int next =
      ((await db.query('SELECT max(id) AS m FROM log')).single['m'] as int? ??
          0) +
      1;
  for (int n = 1; ; n++, next++) {
    // Mostly small transactions, some of many pages, a few about twice the
    // size of SQLite's page cache (2 MB by default).
    final int rows = hugeEvery > 0 && n % hugeEvery == 0
        ? 2600
        : largeEvery > 0 && n % largeEvery == 0
        ? 150
        : 1 + random.nextInt(3);
    await db.execute('BEGIN');
    if (((await db.query('SELECT count FROM totals')).single['count'] as int) >
        5000) {
      // Keeps the database small over hundreds of runs (and frees many pages
      // in one transaction).
      await db.delete('DELETE FROM log WHERE id < 0');
      await db.execute(
        'UPDATE totals SET count = (SELECT count(*) FROM log), '
        'bytes = (SELECT coalesce(sum(size), 0) FROM log)',
      );
    }
    int bytes = 0;
    for (int r = 0; r < rows; r++) {
      final int size = 200 + random.nextInt(2500);
      bytes += size;
      // The first row of the transaction has the id that is acknowledged;
      // the others are numbered below it.
      await db.execute(
        'INSERT INTO log (id, size, payload) VALUES (?, ?, ?)',
        <Object?>[
          r == 0 ? next : -(next * 10000 + r),
          size,
          Uint8List(size)..fillRange(0, size, next & 0xff),
        ],
      );
    }
    await db.execute(
      'UPDATE totals SET count = count + ?, bytes = bytes + ?',
      <Object?>[rows, bytes],
    );
    if (random.nextInt(4) == 0) {
      // Rewrites pages all over the file.
      await db.delete('DELETE FROM log WHERE id < 0 AND id % 3 = 0');
      final Map<String, dynamic> sums = (await db.query(
        'SELECT count(*) AS c, coalesce(sum(size), 0) AS b FROM log',
      )).single;
      await db.execute('UPDATE totals SET count = ?, bytes = ?', <Object?>[
        sums['c'],
        sums['b'],
      ]);
    }
    await db.execute('COMMIT');
    _post('ack $next');
  }
}

void main() {
  _self.onmessage = (web.MessageEvent event) {
    final Map<String, Object?> config =
        jsonDecode((event.data! as JSString).toDart) as Map<String, Object?>;
    unawaited(
      run(config).catchError((Object error, StackTrace stackTrace) {
        _post('error $error\n$stackTrace');
      }),
    );
  }.toJS;
  _post('ready');
}
