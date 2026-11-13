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

/// How many times the worker is started and killed.
const int crashIterations = 300;

final Uri sqlite3Wasm = Uri.base.resolve('sqlite3.wasm');
final Uri workerScript = Uri.base.resolve('crash/crash_worker.js');

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
  test('the cache survives a tab that dies at any moment', () async {
    if (const bool.fromEnvironment('dart.tool.dart2wasm')) {
      // The checks after each kill read the database with the file system of
      // sqlite3 2.9.4 directly, without the read fix of the opener
      // (`_ReadCopyFileSystem` in example/sqlite_database_web.dart): compiled
      // with dart2wasm every read then costs a copy of the whole file, and
      // checking the 3 MB database takes a minute instead of 2 ms.
      markTestSkipped('Run with -c dart2js: under dart2wasm the checks after '
          'each kill take about a minute instead of milliseconds');
      return;
    }
    if (!await exists(sqlite3Wasm)) {
      markTestSkipped('test/browser/sqlite3.wasm is missing: see '
          'web_persistence_test.dart');
      return;
    }
    if (!await exists(workerScript)) {
      markTestSkipped('test/browser/crash/crash_worker.js is missing: compile '
          'it as described in test/browser/crash/crash_worker.dart');
      return;
    }

    final int seed = DateTime.now().millisecondsSinceEpoch % 1000000;
    // ignore: avoid_print
    print('crash test: seed=$seed iterations=$crashIterations');
    final Random random = Random(seed);
    final String name = 'crash-${DateTime.now().microsecondsSinceEpoch}';
    final String storageName = 'crash-test/$name';
    final sqlite.WasmSqlite3 sqlite3 =
        await sqlite.WasmSqlite3.loadFromUrl(sqlite3Wasm);
    // deleteDatabase gives up after one second (VfsException(1)) while a connection is still open: the killed
    // workers' connections are closed by the browser some time later. Seen once on Chromium on Linux under load.
    addTearDown(() async {
      for (int attempt = 1; ; attempt++) {
        try {
          await sqlite.IndexedDbFileSystem.deleteDatabase(storageName);
          return;
        } on sqlite.VfsException {
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
      'hot journal found': 0,
      'transactions acknowledged': 0,
    };

    /// Reads the database back from IndexedDB with a new SQLite, the way the
    /// next page load does, and checks it.
    Future<Observed> verify(String context) async {
      final sqlite.IndexedDbFileSystem fileSystem =
          await sqlite.IndexedDbFileSystem.open(
        dbName: storageName,
        vfsName: 'verify-${vfs++}',
      );
      sqlite3.registerVirtualFileSystem(fileSystem);
      final Observed seen = Observed();
      try {
        if (fileSystem.xAccess('/database-journal', 0) != 0) {
          stats['hot journal found'] = stats['hot journal found']! + 1;
        }
        final sqlite.CommonDatabase db =
            sqlite3.open('/database', vfs: fileSystem.name);
        try {
          // Opening rolls a hot journal back.
          seen.integrity = db
              .select('PRAGMA integrity_check')
              .map((sqlite.Row row) => row.values.first)
              .join('; ');
          expect(seen.integrity, 'ok', reason: context);
          seen.userVersion = db.userVersion;
          seen.tables = <String>[
            for (final sqlite.Row row in db.select(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              'ORDER BY name',
            ))
              row['name'] as String,
          ];

          // The schema is the one of the stored version, entirely.
          expect(seen.userVersion, greaterThanOrEqualTo(verifiedVersion),
              reason: 'the schema version went back. $context');
          final List<String> expectedTables = <String>[
            if (seen.userVersion > 0) ...<String>['log', 'totals'],
            for (int v = 2; v <= seen.userVersion; v++) 'v$v',
          ]..sort();
          expect(seen.tables, expectedTables,
              reason: 'tables of version ${seen.userVersion}. $context');
          for (int v = 2; v <= seen.userVersion; v++) {
            expect(db.select('SELECT count(*) AS c FROM v$v').single['c'], 20,
                reason: 'the data migration $v is complete. $context');
          }

          if (seen.userVersion > 0) {
            final sqlite.Row sums = db.select(
              'SELECT count(*) AS c, coalesce(sum(size), 0) AS b, '
              'coalesce(max(id), 0) AS m, '
              '(SELECT count(*) FROM log WHERE id > 0) AS positive, '
              '(SELECT count(*) FROM log WHERE length(payload) != size) AS bad '
              'FROM log',
            ).single;
            final sqlite.Row totals =
                db.select('SELECT count, bytes FROM totals').single;
            // Each transaction is there entirely or not at all.
            expect(totals['count'], sums['c'], reason: 'row count. $context');
            expect(totals['bytes'], sums['b'], reason: 'byte sum. $context');
            expect(sums['bad'], 0, reason: 'payloads. $context');
            seen.maxId = sums['m'] as int;
            seen.rows = sums['c'] as int;
            expect(sums['positive'], seen.maxId,
                reason: 'no transaction is missing in between. $context');
          }
          // What was acknowledged is stored.
          expect(seen.maxId ?? 0, greaterThanOrEqualTo(acknowledged),
              reason: 'an acknowledged transaction is missing. $context');
          // And at most one transaction that was not acknowledged yet.
          expect(seen.maxId ?? 0,
              lessThanOrEqualTo(max(acknowledged, verifiedMaxId) + 1),
              reason: context);
          expect(seen.maxId ?? 0, greaterThanOrEqualTo(verifiedMaxId),
              reason: 'a stored transaction disappeared. $context');
        } finally {
          db.dispose();
        }
        await fileSystem.flush();
      } finally {
        sqlite3.unregisterVirtualFileSystem(fileSystem);
        await fileSystem.close();
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
      final int killAfterMs =
          random.nextInt(mode == 0 ? 250 : (mode == 3 ? 60 : 40));
      final int killAtAck = 1 + random.nextInt(12);

      final web.Worker worker = web.Worker(workerScript.toString().toJS);
      final Completer<void> kill = Completer<void>();
      bool opened = false;
      int acks = 0;
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
          worker.postMessage(jsonEncode(<String, Object?>{
            'name': name,
            'wasm': sqlite3Wasm.toString(),
            'seed': workerSeed,
            'version': version,
            'largeEvery': 7,
            'hugeEvery': 23,
            // Slow migrations, so that kills fall between their statements.
            'migrationPauseMs': 4,
          }).toJS);
          if (mode == 0 || mode == 3) {
            killSoon(killAfterMs);
          }
        } else if (message.startsWith('open ')) {
          opened = true;
        } else if (message.startsWith('ack ')) {
          acks++;
          acknowledged = int.parse(message.substring(4));
          if ((mode == 1 || mode == 2) && acks == killAtAck) {
            mode == 1 ? kill.complete() : killSoon(killAfterMs);
          }
        } else if (message.startsWith('error ')) {
          error = message;
          if (!kill.isCompleted) {
            kill.complete();
          }
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
      expect(error, isNull, reason: 'iteration $i');

      final String context =
          'iteration $i (seed $seed): mode $mode, killed after $acks '
          'acknowledgements${opened ? '' : ', before the open finished'}; '
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
      verifiedMaxId = seen.maxId ?? 0;
      // A transaction that is stored will be there next time, acknowledged
      // or not.
      acknowledged = max(acknowledged, verifiedMaxId);
      verifiedVersion = seen.userVersion;
    }

    stats['transactions acknowledged'] = acknowledged;
    // ignore: avoid_print
    print('crash test: $crashIterations kills, final schema version '
        '$verifiedVersion of $version, $stats');
    expect(verifiedMaxId, greaterThan(0), reason: 'nothing was ever written');
  });
}
