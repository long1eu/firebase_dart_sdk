// Crash safety of the offline cache in a browser: a worker writes
// transactions through the opener of example/sqlite_database_web.dart and is
// terminated at random moments, hundreds of times; after every kill the
// database is read back from IndexedDB and checked.
//
// Needs test/browser/sqlite3.wasm (see web_persistence_test.dart) and the
// compiled worker (tool/build_web_test_assets.sh, which tool/test_browser.sh
// runs); skips itself with a reason without them.

@TestOn('browser')
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../../example/sqlite_database_web.dart';

/// How many times the worker is started and killed.
const int crashIterations = 300;

final Uri sqlite3Wasm = Uri.base.resolve('sqlite3.wasm');
final Uri workerScript = Uri.base.resolve('crash/crash_worker.js');
final Uri opfsWorker = Uri.base.resolve('opfs/sqlite_opfs_worker.js');

/// A file with the seed of a run to repeat (the test cannot read the environment). The seed fixes when the workers
/// are killed and what they write, not how far they get.
final Uri seedFile = Uri.base.resolve('crash/seed.txt');

Future<int?> seedOverride() async {
  try {
    final web.Response response = await web.window
        .fetch(seedFile.toString().toJS)
        .toDart;
    return response.ok
        ? int.tryParse((await response.text().toDart).toDart.trim())
        : null;
  } catch (_) {
    return null;
  }
}

Future<bool> exists(Uri uri) async {
  try {
    return (await web.window.fetch(uri.toString().toJS).toDart).ok;
  } catch (_) {
    return false;
  }
}

/// What a database held when it was read back after a kill.
class Observed {
  late int userVersion;
  late List<String> tables;
  late String integrity;
  int? maxId;
  int? rows;

  @override
  String toString() =>
      'userVersion=$userVersion tables=$tables integrity=$integrity '
      'maxId=$maxId rows=$rows';
}

void main() {
  test(
    'the cache survives a tab that dies at any moment',
    () => crashTest(opfs: false),
  );
  test(
    'the cache in OPFS survives a tab that dies at any moment',
    () => crashTest(opfs: true),
  );
}

/// Kills a worker that writes through the opener [crashIterations] times.
/// With [opfs] the opener keeps the database in OPFS, in a worker of its own
/// that the browser ends with the worker that started it.
Future<void> crashTest({required bool opfs}) async {
  if (!opfs && const bool.fromEnvironment('dart.tool.dart2wasm')) {
    // The checks after each kill read the database with the file system of
    // sqlite3 2.9.4 directly, without the read fix of the opener
    // (`_ReadCopyFileSystem` in example/sqlite_database_web.dart): compiled
    // with dart2wasm every read then costs a copy of the whole file, and
    // checking the 3 MB database takes a minute instead of 2 ms.
    markTestSkipped(
      'Run with -c dart2js: under dart2wasm the checks after '
      'each kill take about a minute instead of milliseconds',
    );
    return;
  }
  if (!await exists(sqlite3Wasm)) {
    markTestSkipped(
      'test/browser/sqlite3.wasm is missing: see '
      'web_persistence_test.dart',
    );
    return;
  }
  if (!await exists(workerScript)) {
    markTestSkipped(
      'test/browser/crash/crash_worker.js is missing: compile '
      'it as described in test/browser/crash/crash_worker.dart',
    );
    return;
  }
  if (opfs) {
    if (!await exists(opfsWorker)) {
      markTestSkipped(
        'test/browser/opfs/sqlite_opfs_worker.js is missing: '
        'run tool/build_web_test_assets.sh',
      );
      return;
    }
    final SqliteOpfsDatabase? probe = await inspectOpfsDatabase(
      opfsWorker: opfsWorker,
      sqlite3Wasm: sqlite3Wasm,
      storageName: 'crash-test/probe',
    );
    if (probe == null) {
      markTestSkipped(
        'this browser has no synchronous OPFS access in '
        'workers',
      );
      return;
    }
    await probe.clearStorage();
  }

  final int seed =
      await seedOverride() ?? DateTime.now().millisecondsSinceEpoch % 1000000;
  // ignore: avoid_print
  print('crash test: seed=$seed iterations=$crashIterations');
  final Random random = Random(seed);
  final String name = 'crash-${DateTime.now().microsecondsSinceEpoch}';
  final String storageName = 'crash-test/$name';
  final sqlite.WasmSqlite3 sqlite3 = await sqlite.WasmSqlite3.loadFromUrl(
    sqlite3Wasm,
  );
  // deleteDatabase gives up after one second (VfsException(1)) while a
  // connection is still open: the killed workers' connections are closed by
  // the browser some time later. Seen once on Chromium on Linux under load.
  // The OPFS directory cannot be removed while the killed worker's worker
  // still holds its files, which it also releases a moment later.
  addTearDown(() async {
    for (int attempt = 1; ; attempt++) {
      try {
        if (opfs) {
          await sqlite.SimpleOpfsFileSystem.deleteFromStorage(storageName);
        } else {
          await sqlite.IndexedDbFileSystem.deleteDatabase(storageName);
        }
        return;
      } catch (_) {
        if (attempt == 5) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  });

  int verifiedMaxId = 0;
  int acknowledged = 0;
  int version = 1;
  int verifiedVersion = 0;
  int vfs = 0;
  final Map<String, int> stats = <String, int>{
    // Before the worker reported the database as open: with the schema
    // already there, or not yet (the kill fell before or into the creation
    // of the schema or a migration).
    'killed before open': 0,
    'killed during the open (schema or migration)': 0,
    'killed with a transaction not acknowledged but stored': 0,
    // Acknowledgements the worker had posted when it was killed and that the
    // page had not handled yet.
    'kills with acknowledgements in flight': 0,
    'most acknowledgements in flight at a kill': 0,
    // What the bound was checked against before the acknowledgements had a
    // port of their own.
    'most stored transactions the page did not know of at the kill': 0,
    'hot journal found': 0,
    // OPFS: how long the files of the killed worker's worker stayed busy.
    'files still held after 2 s': 0,
    'longest wait for the files (ms)': 0,
    'transactions acknowledged': 0,
  };

  /// Reads the database back with a new SQLite, the way the next page load
  /// does: from IndexedDB, or from OPFS through a new worker. Checks it.
  Future<Observed> verify(String context) async {
    final Observed seen = Observed();
    final Future<List<Map<String, Object?>>> Function(String sql) select;
    final Future<void> Function() done;
    if (opfs) {
      // The worker of the killed worker is ended by the browser a moment
      // later, and only then releases the files: the open waits for them
      // (up to ten seconds; the stats say how long it took).
      final Stopwatch busy = Stopwatch()..start();
      SqliteOpfsDatabase? opened;
      for (int attempt = 1; opened == null; attempt++) {
        try {
          opened = (await inspectOpfsDatabase(
            opfsWorker: opfsWorker,
            sqlite3Wasm: sqlite3Wasm,
            storageName: storageName,
          ))!;
        } on SqliteOpfsException catch (e) {
          if (!e.message.contains('NoModificationAllowedError') ||
              attempt == 3) {
            rethrow;
          }
        }
      }
      if (busy.elapsedMilliseconds > 2000) {
        stats['files still held after 2 s'] =
            stats['files still held after 2 s']! + 1;
      }
      stats['longest wait for the files (ms)'] = max(
        stats['longest wait for the files (ms)']!,
        busy.elapsedMilliseconds,
      );
      final SqliteOpfsDatabase db = opened;
      select = db.query;
      done = () async {
        db.close();
        await db.whenClosed;
      };
    } else {
      final sqlite.IndexedDbFileSystem fileSystem =
          await sqlite.IndexedDbFileSystem.open(
            dbName: storageName,
            vfsName: 'verify-${vfs++}',
          );
      sqlite3.registerVirtualFileSystem(fileSystem);
      if (fileSystem.xAccess('/database-journal', 0) != 0) {
        stats['hot journal found'] = stats['hot journal found']! + 1;
      }
      // Opening rolls a hot journal back.
      final sqlite.CommonDatabase db = sqlite3.open(
        '/database',
        vfs: fileSystem.name,
      );
      select = (String sql) async => <Map<String, Object?>>[
        for (final sqlite.Row row in db.select(sql))
          Map<String, Object?>.of(row),
      ];
      done = () async {
        db.dispose();
        await fileSystem.flush();
        sqlite3.unregisterVirtualFileSystem(fileSystem);
        await fileSystem.close();
      };
    }
    try {
      seen.integrity = (await select(
        'PRAGMA integrity_check',
      )).map((Map<String, Object?> row) => row.values.first).join('; ');
      expect(seen.integrity, 'ok', reason: context);
      seen.userVersion =
          (await select('PRAGMA user_version')).single.values.first! as int;
      seen.tables = <String>[
        for (final Map<String, Object?> row in await select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          'ORDER BY name',
        ))
          row['name']! as String,
      ];

      // The schema is the one of the stored version, entirely.
      expect(
        seen.userVersion,
        greaterThanOrEqualTo(verifiedVersion),
        reason: 'the schema version went back. $context',
      );
      final List<String> expectedTables = <String>[
        if (seen.userVersion > 0) ...<String>['log', 'totals'],
        for (int v = 2; v <= seen.userVersion; v++) 'v$v',
      ]..sort();
      expect(
        seen.tables,
        expectedTables,
        reason: 'tables of version ${seen.userVersion}. $context',
      );
      for (int v = 2; v <= seen.userVersion; v++) {
        expect(
          (await select('SELECT count(*) AS c FROM v$v')).single['c'],
          20,
          reason: 'the data migration $v is complete. $context',
        );
      }

      if (seen.userVersion > 0) {
        final Map<String, Object?> sums = (await select(
          'SELECT count(*) AS c, coalesce(sum(size), 0) AS b, '
          'coalesce(max(id), 0) AS m, '
          '(SELECT count(*) FROM log WHERE id > 0) AS positive, '
          '(SELECT count(*) FROM log WHERE length(payload) != size) AS bad '
          'FROM log',
        )).single;
        final Map<String, Object?> totals = (await select(
          'SELECT count, bytes FROM totals',
        )).single;
        // Each transaction is there entirely or not at all.
        expect(totals['count'], sums['c'], reason: 'row count. $context');
        expect(totals['bytes'], sums['b'], reason: 'byte sum. $context');
        expect(sums['bad'], 0, reason: 'payloads. $context');
        seen.maxId = sums['m']! as int;
        seen.rows = sums['c']! as int;
        expect(
          sums['positive'],
          seen.maxId,
          reason: 'no transaction is missing in between. $context',
        );
      }
      // What was acknowledged is stored.
      expect(
        seen.maxId ?? 0,
        greaterThanOrEqualTo(acknowledged),
        reason: 'an acknowledged transaction is missing. $context',
      );
      // And at most one transaction that was not acknowledged yet: the one
      // the worker was committing. The acknowledgements count that were on
      // their way to the page when the worker was killed (see the kill
      // below): a busy page is several acknowledgements behind the worker
      // (five on a CI runner, 1593 stored against a bound of 1590 locally).
      expect(
        seen.maxId ?? 0,
        lessThanOrEqualTo(max(acknowledged, verifiedMaxId) + 1),
        reason: context,
      );
      expect(
        seen.maxId ?? 0,
        greaterThanOrEqualTo(verifiedMaxId),
        reason: 'a stored transaction disappeared. $context',
      );
    } finally {
      await done();
    }
    return seen;
  }

  for (int i = 0; i < crashIterations; i++) {
    // A new schema version now and then: its migration can be hit too.
    if (i > 0 && i % 20 == 0) {
      version++;
    }
    final int workerSeed = random.nextInt(0x7fffffff);
    // Kill by the clock (also during the open), or right after an
    // acknowledgement, or in the middle of what follows it.
    // Mode 3 aims at the open itself: creating the schema, a migration.
    final int mode = random.nextInt(4);
    final int killAfterMs = random.nextInt(
      mode == 0 ? 250 : (mode == 3 ? 60 : 40),
    );
    final int killAtAck = 1 + random.nextInt(12);

    final web.Worker worker = web.Worker(workerScript.toString().toJS);
    // The acknowledgements come through a port of their own: terminating a
    // worker drops the messages it posted to the page that the page has not
    // handled yet, and the transactions of those were committed. What was
    // posted on this port still arrives after the kill.
    final web.MessageChannel ackChannel = web.MessageChannel();
    final Completer<void> kill = Completer<void>();
    bool opened = false;
    bool killed = false;
    int acks = 0;
    int acksInFlight = 0;
    String? error;
    void killSoon(int ms) {
      Timer(Duration(milliseconds: ms), () {
        if (!kill.isCompleted) {
          kill.complete();
        }
      });
    }

    worker.onmessage = (web.MessageEvent event) {
      final String message = (event.data! as JSString).toDart;
      if (message == 'ready') {
        worker.postMessage(
          jsonEncode(<String, Object?>{
            'name': name,
            'wasm': sqlite3Wasm.toString(),
            'opfsWorker': opfs ? opfsWorker.toString() : null,
            'seed': workerSeed,
            'version': version,
            'largeEvery': 7,
            'hugeEvery': 23,
            // Slow migrations, so that kills fall between their statements.
            'migrationPauseMs': 4,
          }).toJS,
          <JSObject>[ackChannel.port2].toJS,
        );
        if (mode == 0 || mode == 3) {
          killSoon(killAfterMs);
        }
      } else if (message.startsWith('open ')) {
        opened = true;
      } else if (message.startsWith('error ')) {
        error = message;
        if (!kill.isCompleted) {
          kill.complete();
        }
      }
    }.toJS;
    ackChannel.port1.onmessage = (web.MessageEvent event) {
      final String message = (event.data! as JSString).toDart;
      acknowledged = int.parse(message.substring('ack '.length));
      if (killed) {
        acksInFlight++;
        return;
      }
      acks++;
      if ((mode == 1 || mode == 2) && acks == killAtAck) {
        mode == 1 ? kill.complete() : killSoon(killAfterMs);
      }
    }.toJS;
    worker.onerror = (web.Event event) {
      error = 'worker error: ${(event as web.ErrorEvent).message}';
      if (!kill.isCompleted) {
        kill.complete();
      }
    }.toJS;

    await kill.future.timeout(const Duration(seconds: 60));
    worker.terminate();
    killed = true;
    final int knownAtKill = acknowledged;
    expect(error, isNull, reason: 'iteration $i');
    // The acknowledgements that were on their way: wait until none arrived
    // for a moment (with a page that is busy three quarters of the time up
    // to 15 of them were, and all arrived within this wait).
    for (int quiet = 0, seen = acksInFlight; quiet < 2;) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (acksInFlight == seen) {
        quiet++;
      } else {
        quiet = 0;
        seen = acksInFlight;
      }
    }
    ackChannel.port1.close();
    if (acksInFlight > 0) {
      stats['kills with acknowledgements in flight'] =
          stats['kills with acknowledgements in flight']! + 1;
      stats['most acknowledgements in flight at a kill'] = max(
        stats['most acknowledgements in flight at a kill']!,
        acksInFlight,
      );
    }

    final String context =
        'iteration $i (seed $seed): mode $mode, killed after $acks '
        'acknowledgements (and $acksInFlight in flight)'
        '${opened ? '' : ', before the open finished'}; '
        'acknowledged up to $acknowledged, stored before $verifiedMaxId';
    final Observed seen = await verify(context);
    if (!opened) {
      // Before the open finished: when the stored schema is not the one the
      // worker was asked for, the kill fell before or into its migration.
      final String key = seen.userVersion == version
          ? 'killed before open'
          : 'killed during the open (schema or migration)';
      stats[key] = stats[key]! + 1;
    }
    if ((seen.maxId ?? 0) > acknowledged) {
      stats['killed with a transaction not acknowledged but stored'] =
          stats['killed with a transaction not acknowledged but stored']! + 1;
    }
    stats['most stored transactions the page did not know of at the kill'] = max(
      stats['most stored transactions the page did not know of at the kill']!,
      (seen.maxId ?? 0) - knownAtKill,
    );
    verifiedMaxId = seen.maxId ?? 0;
    // A transaction that is stored will be there next time, acknowledged
    // or not.
    acknowledged = max(acknowledged, verifiedMaxId);
    verifiedVersion = seen.userVersion;
  }

  stats['transactions acknowledged'] = acknowledged;
  // ignore: avoid_print
  print(
    'crash test${opfs ? ' (OPFS)' : ''}: $crashIterations kills, final schema version '
    '$verifiedVersion of $version, $stats',
  );
  expect(verifiedMaxId, greaterThan(0), reason: 'nothing was ever written');
}
