// Many isolates open the same new SQLite cache at the same moment, round after round: every open succeeds and the
// cache is migrated once. A stress version of "clients in several isolates open a new cache at the same time"
// (sqlite_shared_clients_test.dart), which once failed with `database is locked` on `BEGIN EXCLUSIVE` under load.
//
// The size comes from the environment, for load runs:
//   OPEN_STRESS_ISOLATES (default 8), OPEN_STRESS_ROUNDS (default 5).

@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:test/test.dart';

import '../../../../util/sqlite3_database.dart';
import 'sqlite_shared_clients_test.dart' show newName, openPersistence;

int _env(String key, int fallback) =>
    int.tryParse(Platform.environment[key] ?? '') ?? fallback;

/// Opens [name] at [openAt] in a new isolate, runs one transaction and shuts down. Returns null, or the error and
/// how long after [openAt] it happened.
Future<String?> _openOnce(String name, DateTime openAt) {
  return Isolate.run(() async {
    final Duration wait = openAt.difference(DateTime.now());
    if (!wait.isNegative) {
      await Future<void>.delayed(wait);
    }
    final Stopwatch watch = Stopwatch()..start();
    try {
      final SQLitePersistence persistence = await openPersistence(name);
      await persistence.runTransaction('use', () async {});
      await persistence.shutdown();
      return null;
    } catch (e) {
      return 'after ${watch.elapsedMilliseconds} ms: $e';
    }
  });
}

void main() {
  final int isolates = _env('OPEN_STRESS_ISOLATES', 8);
  final int rounds = _env('OPEN_STRESS_ROUNDS', 5);

  test(
    '$isolates isolates open a new cache at the same moment, $rounds rounds',
    () async {
      final List<String> failures = <String>[];
      for (int round = 0; round < rounds; round++) {
        final String name = newName('open-stress');
        try {
          final DateTime openAt = DateTime.now().add(
            const Duration(milliseconds: 500),
          );
          final List<String?> results = await Future.wait(<Future<String?>>[
            for (int i = 0; i < isolates; i++) _openOnce(name, openAt),
          ]);
          for (final String? result in results) {
            if (result != null) {
              failures.add('round $round: $result');
            }
          }
          final SQLitePersistence check = await openPersistence(name);
          expect(
            (await check.query('PRAGMA user_version')).single.values.single,
            SQLiteSchema.version,
          );
          expect(await check.query('PRAGMA integrity_check'), <Object>[
            <String, Object?>{'integrity_check': 'ok'},
          ]);
          await check.shutdown();
        } finally {
          DatabaseMock.deleteDatabaseFiles(name);
        }
      }
      expect(failures, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
