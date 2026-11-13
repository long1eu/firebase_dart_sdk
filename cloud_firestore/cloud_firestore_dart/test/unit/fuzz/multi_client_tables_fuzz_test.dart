// Fuzz: the multi-client tables of a SQLite cache (clients, primary_client,
// persistence_epoch) and the globals table hold rows that another process
// wrote: another version of the SDK, a damaged file, or something else than
// the SDK. The columns are typed by affinity only, and the other process may
// even have created the tables without their constraints.
//
// Between the operations of two clients, rows are replaced, added and removed
// with values of any SQLite type. Every operation must complete or fail with a
// FirestoreError or an error of the database, in bounded time; nothing may
// fail with a TypeError or a RangeError, also not in the warnings that a
// refresh logs instead of throwing.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:sqlite3/sqlite3.dart' as sql show Database;
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';

import '../../util/property.dart';
import '../../util/sqlite3_database.dart';
import '../../util/sqlite3_library.dart';

const Duration operationTimeout = Duration(seconds: 10);

/// How the operations of all cases ended, to show that the cases exercise the
/// clients rather than fail at once.
final Map<String, int> outcomes = <String, int>{};

int _counter = 0;

String newName() =>
    'fuzz/multi_client_${pid}_${DateTime.now().microsecondsSinceEpoch}_'
    '${_counter++}.db';

OpenDatabase opener(String name) {
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
      name,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onDowngrade: onDowngrade,
      onOpen: onOpen,
    );
    return db..renamePath = false;
  };
}

class FakeClock {
  int now = 1700000000000;

  int call() => now;
}

Future<SQLitePersistence> createClient(
  String name,
  String clientId,
  FakeClock clock,
) async {
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  return SQLitePersistence.createWithLease(
    '$name-$clientId',
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    opener(name),
    const LruGarbageCollectorParams(),
    clientId: clientId,
    clock: clock.call,
    leaseMode: PrimaryLeaseMode.multipleClients,
  );
}

/// Whether [error] is a clean failure of an operation on a damaged cache.
bool isCleanFailure(Object error) =>
    error is FirestoreError ||
    error is SqliteException ||
    error is TransientDatabaseException;

/// Text in a log line that shows a crash hidden behind a warning.
final RegExp crashInLog = RegExp(
  'TypeError|is not a subtype|RangeError|NoSuchMethodError|Null check|'
  'Stack Overflow|UnsupportedError',
);

extension on Gen {
  /// A value of any SQLite type.
  Object? sqlValue(FakeClock clock) {
    switch (below(9)) {
      case 0:
        return null;
      case 1:
        return integer();
      case 2:
        // A time around now, in the past or the future.
        return clock.now + between(-40 * 60 * 1000, 40 * 60 * 1000);
      case 3:
        return pick(const <int>[0, 1, -1, 2]);
      case 4:
        final double d = float();
        // SQLite stores NaN as NULL.
        return d.isNaN ? 0.5 : d;
      case 5:
        return string();
      case 6:
        return pick(<String>[
          'a', 'b', '', '1', '${clock.now}', '1.5', 'NaN', 'x' * 300, //
        ]);
      case 7:
        return Uint8List.fromList(<int>[
          for (int i = below(6); i > 0; i--) below(256),
        ]);
      default:
        return clock.now;
    }
  }
}

/// The statements that damage the tables, with their arguments.
typedef Damage = (String, List<Object?>);

List<Damage> damage(Gen gen, FakeClock clock, List<String> clientIds) {
  Object? v() => gen.sqlValue(clock);
  Object? id() => gen.chance(60) ? gen.pick(clientIds) : v();
  Object? zeroOrAny() => gen.chance(50) ? 0 : v();
  Object? nameOrAny() => gen.chance(70) ? 'sessionToken' : v();
  final List<Damage> statements = <Damage>[];
  for (int i = gen.between(1, 4); i > 0; i--) {
    switch (gen.below(12)) {
      case 0:
        statements.add((
          'INSERT OR REPLACE INTO clients VALUES (?, ?, ?, ?)',
          <Object?>[id(), v(), v(), v()],
        ));
        break;
      case 1:
        statements.add((
          'UPDATE clients SET update_time_ms = ?, network_enabled = ?, '
              'in_foreground = ?',
          <Object?>[v(), v(), v()],
        ));
        break;
      case 2:
        statements.add((
          'INSERT OR REPLACE INTO primary_client VALUES (0, ?, ?, ?)',
          <Object?>[id(), v(), v()],
        ));
        break;
      case 3:
        statements.add((
          'UPDATE primary_client SET owner_id = ?, allow_synchronization = ?, '
              'lease_timestamp_ms = ?',
          <Object?>[id(), v(), v()],
        ));
        break;
      case 4:
        statements.add((
          'UPDATE persistence_epoch SET epoch = ?',
          <Object?>[v()],
        ));
        break;
      case 5:
        statements.add((
          gen.pick(const <String>[
            'DELETE FROM clients',
            'DELETE FROM primary_client',
            'DELETE FROM persistence_epoch',
            'DELETE FROM globals',
          ]),
          <Object?>[],
        ));
        break;
      case 6:
        statements.add((
          'INSERT OR REPLACE INTO globals VALUES (?, ?)',
          <Object?>[nameOrAny(), v()],
        ));
        break;
      case 7:
        // The tables as another process may have created them: without
        // types or constraints, with rows that break them.
        final String table = gen.pick(const <String>[
          'clients',
          'primary_client',
          'persistence_epoch',
        ]);
        final String columns = switch (table) {
          'clients' =>
            'client_id, update_time_ms, network_enabled, in_foreground',
          'primary_client' =>
            'id, owner_id, allow_synchronization, lease_timestamp_ms',
          _ => 'id, epoch',
        };
        statements
          ..add(('DROP TABLE IF EXISTS fuzz_copy', <Object?>[]))
          ..add(('CREATE TABLE fuzz_copy ($columns)', <Object?>[]))
          ..add(('INSERT INTO fuzz_copy SELECT * FROM $table', <Object?>[]))
          ..add(('DROP TABLE $table', <Object?>[]))
          ..add(('ALTER TABLE fuzz_copy RENAME TO $table', <Object?>[]));
        break;
      case 8:
        // Only applies to tables without constraints.
        statements.add((
          gen.pick(const <String>[
            'INSERT INTO primary_client VALUES (?, ?, ?, ?)',
            'INSERT INTO clients VALUES (?, ?, ?, ?)',
          ]),
          <Object?>[zeroOrAny(), id(), v(), v()],
        ));
        break;
      case 9:
        statements.add((
          'INSERT INTO persistence_epoch VALUES (?, ?)',
          <Object?>[zeroOrAny(), v()],
        ));
        break;
      default:
        statements.add((
          'INSERT OR REPLACE INTO clients VALUES (?, ?, 1, 1)',
          <Object?>['other-${gen.below(3)}', v()],
        ));
    }
  }
  return statements;
}

class Case {
  Case(this.seed);

  final int seed;

  @override
  String toString() => 'seed $seed';
}

Future<void> runCase(int seed) async {
  final Gen gen = Gen(seed);
  final FakeClock clock = FakeClock();
  final String name = newName();
  final List<String> ids = <String>['client-a', 'client-b'];
  final List<SQLitePersistence?> clients = <SQLitePersistence?>[null, null];
  final List<String> log = <String>[];

  Future<void> guarded(String what, Future<void> Function() body) async {
    try {
      await body().timeout(operationTimeout);
      outcomes['completed'] = (outcomes['completed'] ?? 0) + 1;
    } on TimeoutException {
      fail('$what hangs');
    } catch (error, stackTrace) {
      outcomes['${error.runtimeType}'] =
          (outcomes['${error.runtimeType}'] ?? 0) + 1;
      if (!isCleanFailure(error)) {
        fail(
          '$what failed with ${error.runtimeType}: $error\n'
          '${stackTrace.toString().split('\n').take(8).join('\n')}',
        );
      }
    }
  }

  try {
    await runZoned(
      () async {
        for (int i = 0; i < 2; i++) {
          final SQLitePersistence client = await createClient(
            name,
            ids[i],
            clock,
          );
          await client.start();
          clients[i] = client;
        }
        for (int round = 0; round < 6; round++) {
          // Another process writes the rows.
          final sql.Database other = nativeSqlite3.open(
            DatabaseMock.pathForName(name).path,
          );
          try {
            other.execute('PRAGMA busy_timeout = 5000');
            for (final Damage statement in damage(gen, clock, ids)) {
              try {
                other.execute(statement.$1, statement.$2);
              } on SqliteException {
                // A constraint of the table refused the row.
              }
            }
          } finally {
            other.dispose();
          }
          clock.now += gen.pick(const <int>[
            0,
            1000,
            4000,
            6000,
            31 * 60 * 1000,
          ]);
          for (int op = gen.between(1, 4); op > 0; op--) {
            final int index = gen.below(2);
            final SQLitePersistence? client = clients[index];
            if (client == null || !client.started) {
              await guarded('start of ${ids[index]}', () async {
                final SQLitePersistence started = await createClient(
                  name,
                  ids[index],
                  clock,
                );
                await started.start();
                clients[index] = started;
              });
              continue;
            }
            final SQLitePersistence c = client;
            switch (gen.below(7)) {
              case 0:
                await guarded('refresh', c.refreshClientMetadata);
                break;
              case 1:
                await guarded('active clients', c.getActiveClients);
                break;
              case 2:
                await guarded(
                  'primary transaction',
                  () => c.runPrimaryTransaction<void>('op', () async {}),
                );
                break;
              case 3:
                await guarded(
                  'transaction',
                  () => c.runTransaction('op', () async {}),
                );
                break;
              case 4:
                await guarded(
                  'network',
                  () => c.setNetworkEnabled(gen.chance(50)),
                );
                break;
              case 5:
                await guarded(
                  'session token',
                  () => c.runTransaction(
                    'token',
                    () => c.globalsCache.getSessionToken(),
                  ),
                );
                break;
              default:
                await guarded('shutdown', c.shutdown);
            }
          }
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          log.add(line);
        },
      ),
    );
    final Iterable<String> crashes = log.where(crashInLog.hasMatch);
    if (crashes.isNotEmpty) {
      fail('A warning shows a crash: ${crashes.first}');
    }
  } finally {
    for (final SQLitePersistence? client in clients) {
      if (client != null && client.started) {
        try {
          await client.shutdown();
        } catch (_) {
          // The cache may be damaged beyond a clean shutdown.
        }
      }
    }
    DatabaseMock.deleteDatabaseFiles(name);
  }
}

void main() {
  test('clients survive malformed multi-client rows', () async {
    await forAllAsync<Case>(
      'malformed multi-client rows',
      count: cases(300),
      generate: (Gen gen) => Case(gen.seed),
      check: (Case c) => runCase(c.seed),
    );
    // Most operations complete: the damage does not stop the clients.
    expect(
      outcomes['completed'] ?? 0,
      greaterThan(outcomes.values.fold<int>(0, (int a, int b) => a + b) ~/ 2),
      reason: '$outcomes',
    );
    print('outcomes: $outcomes');
  });
}
