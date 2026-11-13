// The client metadata and the primary lease of a SQLite cache (stage 1 of the multi-client plan): with a fake clock,
// several clients on one file in this isolate, and clients in several isolates driven step by step.
//
// "Exactly one primary" is checked after every client has run a transaction since the last change: a client learns
// that it lost the lease at its next transaction (or refresh), not at the moment another client takes it.

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/remote/remote_serializer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/database.dart';
import 'package:test/test.dart';

import '../../../../util/sqlite3_database.dart';

const int validity = SQLiteClientMetadata.maxPrimaryEligibleAgeMs;
const int refresh = 4000;
const int clientAge = SQLiteClientMetadata.maxClientAgeMs;

int _counter = 0;

String newName() =>
    'firebase/firestore/local/primary_lease_${pid}_'
    '${DateTime.now().microsecondsSinceEpoch}_${_counter++}.db';

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

/// A clock the test moves.
class FakeClock {
  int now = 1700000000000;

  int call() => now;

  void advance(int ms) => now += ms;
}

Future<SQLitePersistence> createClient(
  String name,
  String clientId,
  int Function() clock, {
  PrimaryLeaseMode mode = PrimaryLeaseMode.multipleClients,
}) {
  final DatabaseId databaseId = DatabaseId.forProject('projectId');
  return SQLitePersistence.createWithLease(
    // A key per client: two persistences with the same name wait for each other in this isolate.
    '$name-$clientId',
    databaseId,
    LocalSerializer(RemoteSerializer(databaseId)),
    opener(name),
    const LruGarbageCollectorParams(),
    clientId: clientId,
    clock: clock,
    leaseMode: mode,
  );
}

/// Runs [body] and returns what it printed.
Future<List<String>> capturePrints(Future<void> Function() body) async {
  final List<String> lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
          lines.add(line),
    ),
  );
  return lines;
}

void main() {
  late String name;
  late FakeClock clock;
  final List<SQLitePersistence> clients = <SQLitePersistence>[];

  setUp(() {
    name = newName();
    clock = FakeClock();
  });

  tearDown(() async {
    for (final SQLitePersistence client in clients) {
      if (client.started) {
        await client.shutdown();
      }
    }
    clients.clear();
    DatabaseMock.deleteDatabaseFiles(name);
  });

  Future<SQLitePersistence> start(
    String clientId, {
    PrimaryLeaseMode mode = PrimaryLeaseMode.multipleClients,
  }) async {
    final SQLitePersistence client = await createClient(
      name,
      clientId,
      clock.call,
      mode: mode,
    );
    clients.add(client);
    await client.start();
    return client;
  }

  Future<Map<String, dynamic>?> lease(SQLitePersistence via) async {
    final List<Map<String, dynamic>> rows = await via.query(
      'SELECT * FROM primary_client',
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, int>> clientRows(SQLitePersistence via) async {
    return <String, int>{
      for (final Map<String, dynamic> row in await via.query(
        'SELECT client_id, update_time_ms FROM clients',
      ))
        row['client_id'] as String: row['update_time_ms'] as int,
    };
  }

  /// Every running client runs a transaction, so that it has seen the latest lease; then exactly one of them is
  /// primary, and it is the owner of the lease row.
  Future<SQLitePersistence> expectExactlyOnePrimary() async {
    final List<SQLitePersistence> running = <SQLitePersistence>[
      for (final SQLitePersistence client in clients)
        if (client.started) client,
    ];
    for (final SQLitePersistence client in running) {
      await client.runTransaction('look', () async {});
    }
    final List<SQLitePersistence> primaries = <SQLitePersistence>[
      for (final SQLitePersistence client in running)
        if (client.isPrimary) client,
    ];
    expect(
      primaries.map((SQLitePersistence c) => c.clientMetadata.clientId),
      hasLength(1),
      reason:
          'primaries: ${primaries.map((SQLitePersistence c) => c.clientMetadata.clientId)}',
    );
    expect(
      (await lease(running.first))?['owner_id'],
      primaries.single.clientMetadata.clientId,
    );
    return primaries.single;
  }

  group('one client', () {
    test('takes the lease when it starts and writes its metadata', () async {
      final SQLitePersistence a = await start('A');
      expect(a.isPrimary, isTrue);
      expect(await lease(a), <String, Object?>{
        'id': 0,
        'owner_id': 'A',
        'allow_synchronization': 1,
        'lease_timestamp_ms': clock.now,
      });
      expect(await clientRows(a), <String, int>{'A': clock.now});
      expect(await a.getActiveClients(), <String>['A']);
    });

    test('refreshes the lease and its metadata', () async {
      final SQLitePersistence a = await start('A');
      clock.advance(refresh);
      await a.refreshClientMetadata();
      expect((await lease(a))!['lease_timestamp_ms'], clock.now);
      expect(await clientRows(a), <String, int>{'A': clock.now});
      expect(a.isPrimary, isTrue);
    });

    test('takes back its own lease after it expired', () async {
      final SQLitePersistence a = await start('A');
      clock.advance(validity * 10);
      await a.refreshClientMetadata();
      expect(a.isPrimary, isTrue);
      expect((await lease(a))!['lease_timestamp_ms'], clock.now);
    });

    test('releases the lease and removes its row when it terminates', () async {
      final SQLitePersistence a = await start('A');
      await a.shutdown();
      expect(a.isPrimary, isFalse);

      final SQLitePersistence b = await start('B');
      expect(b.isPrimary, isTrue);
      expect(await clientRows(b), <String, int>{'B': clock.now});
    });

    test('the refresh uses no listen sequence number', () async {
      final SQLitePersistence a = await start('A');
      await a.runTransaction('one', () async {});
      final int before = a.referenceDelegate.listenSequence.next;
      for (int i = 0; i < 3; i++) {
        clock.advance(refresh);
        await a.refreshClientMetadata();
      }
      expect(a.referenceDelegate.listenSequence.next, before + 1);
    });

    test('reports changes of its primary state', () async {
      final SQLitePersistence a = await start('A');
      final List<bool> states = <bool>[];
      a.clientMetadata.primaryStateListener = states.add;
      final SQLitePersistence b = await start('B');
      clock.advance(validity + 1);
      await b.refreshClientMetadata();
      await a.refreshClientMetadata();
      expect(states, <bool>[false]);
      await b.shutdown();
      await a.refreshClientMetadata();
      expect(states, <bool>[false, true]);
    });
  });

  group('several clients, multiple-client mode', () {
    test('a second client respects a valid lease', () async {
      final SQLitePersistence a = await start('A');
      final SQLitePersistence b = await start('B');
      expect(b.isPrimary, isFalse);
      expect(await expectExactlyOnePrimary(), same(a));
      expect(await a.getActiveClients(), <String>['A', 'B']);

      // The primary keeps it while it refreshes.
      for (int i = 0; i < 5; i++) {
        clock.advance(refresh);
        await b.refreshClientMetadata();
        await a.refreshClientMetadata();
        expect(await expectExactlyOnePrimary(), same(a));
      }
    });

    test(
      'takes over when the primary stops refreshing and the lease expires',
      () async {
        final SQLitePersistence a = await start('A');
        final SQLitePersistence b = await start('B');

        // A stops refreshing (it crashed, or its isolate is blocked). Within the validity B waits.
        clock.advance(validity);
        await b.refreshClientMetadata();
        expect(b.isPrimary, isFalse);
        expect(await expectExactlyOnePrimary(), same(a));

        clock.advance(1);
        await b.refreshClientMetadata();
        expect(b.isPrimary, isTrue);
        // A learns it at its next transaction.
        expect(await expectExactlyOnePrimary(), same(b));
        expect(a.isPrimary, isFalse);

        // A comes back: the lease of B is valid, A stays secondary.
        await a.refreshClientMetadata();
        expect(await expectExactlyOnePrimary(), same(b));
      },
    );

    test('takes over at once when the primary terminates', () async {
      await start('A');
      final SQLitePersistence b = await start('B');
      final SQLitePersistence c = await start('C');
      await clients.first.shutdown();
      expect(await lease(b), isNull);

      // No waiting for the lease to expire: the next refresh of a client takes it.
      await c.refreshClientMetadata();
      await b.refreshClientMetadata();
      expect(await expectExactlyOnePrimary(), same(c));
      expect(await c.getActiveClients(), <String>['B', 'C']);
    });

    test(
      'a primary without network gives the lease to a client with network',
      () async {
        final SQLitePersistence a = await start('A');
        final SQLitePersistence b = await start('B');

        await a.setNetworkEnabled(false);
        expect(a.isPrimary, isFalse);
        expect(await lease(a), isNull);
        await b.refreshClientMetadata();
        expect(await expectExactlyOnePrimary(), same(b));

        // Without a better client a client without network keeps the lease.
        await b.setNetworkEnabled(false);
        expect(b.isPrimary, isTrue);
        expect(await expectExactlyOnePrimary(), same(b));
      },
    );

    test('a lease from the future is not valid', () async {
      final SQLitePersistence a = await start('A');
      await a.execute(
        'UPDATE primary_client SET owner_id = ?, lease_timestamp_ms = ?',
        <Object?>['Z', clock.now + 60000],
      );
      final SQLitePersistence b = await start('B');
      expect(b.isPrimary, isTrue);
      expect(await expectExactlyOnePrimary(), same(b));
    });
  });

  group('several clients, forced ownership (the default)', () {
    test(
      'a new client takes the lease with a warning; the old one yields',
      () async {
        final SQLitePersistence a = await start(
          'A',
          mode: PrimaryLeaseMode.forceOwnership,
        );
        expect((await lease(a))!['allow_synchronization'], 0);

        late SQLitePersistence b;
        final List<String> printed = await capturePrints(() async {
          b = await start('B', mode: PrimaryLeaseMode.forceOwnership);
        });
        expect(b.isPrimary, isTrue);
        expect(
          printed.where((String line) => line.startsWith('W:PrimaryLease')),
          hasLength(1),
        );
        expect(
          printed.single,
          allOf(contains('Another client (A)'), contains('takes over')),
        );
        expect(await expectExactlyOnePrimary(), same(b));

        // A does not take it back while B refreshes.
        for (int i = 0; i < 3; i++) {
          clock.advance(refresh);
          await a.refreshClientMetadata();
          await b.refreshClientMetadata();
          expect(await expectExactlyOnePrimary(), same(b));
        }

        // And takes over when B is gone.
        await b.shutdown();
        await a.refreshClientMetadata();
        expect(await expectExactlyOnePrimary(), same(a));
      },
    );

    test('no warning when the lease is free or expired', () async {
      final List<String> printed = await capturePrints(() async {
        final SQLitePersistence a = await start(
          'A',
          mode: PrimaryLeaseMode.forceOwnership,
        );
        await a.shutdown();
        await start('B', mode: PrimaryLeaseMode.forceOwnership);
        clock.advance(validity + 1);
        await start('C', mode: PrimaryLeaseMode.forceOwnership);
      });
      expect(printed, isEmpty);
    });

    test('the second client keeps working as before', () async {
      final SQLitePersistence a = await start(
        'A',
        mode: PrimaryLeaseMode.forceOwnership,
      );
      final SQLitePersistence b = await start(
        'B',
        mode: PrimaryLeaseMode.forceOwnership,
      );
      await a.runTransaction('write', () async {
        await a.execute(
          'INSERT INTO bundles (bundle_id, create_time_seconds, create_time_nanos, schema_version, '
          'total_documents, total_bytes) VALUES (?, 0, 0, 1, 0, 0)',
          <Object?>['from A'],
        );
      });
      expect(a.isPrimary, isFalse);
      expect(await b.query('SELECT bundle_id FROM bundles'), hasLength(1));
    });
  });

  group('primary-only transactions', () {
    final Matcher leaseLost = throwsA(
      isA<FirestoreError>().having(isPrimaryLeaseLoss, 'is lease loss', isTrue),
    );

    test('the primary runs them and extends its lease', () async {
      final SQLitePersistence a = await start('A');
      clock.advance(1000);
      expect(await a.runPrimaryTransaction('op', () async => 42), 42);
      expect((await lease(a))!['lease_timestamp_ms'], clock.now);
      expect(a.isPrimary, isTrue);
    });

    test('a lone client keeps its own expired lease', () async {
      final SQLitePersistence a = await start('A');
      // Its isolate was paused (a breakpoint): nobody took the lease in between.
      clock.advance(validity * 10);
      expect(await a.runPrimaryTransaction('op', () async => true), isTrue);
      expect((await lease(a))!['lease_timestamp_ms'], clock.now);
    });

    test(
      'a client that is not primary fails them, runs nothing and tells its listener',
      () async {
        final SQLitePersistence a = await start('A');
        final SQLitePersistence b = await start('B');
        final List<bool> states = <bool>[];
        b.setPrimaryStateListener(states.add);
        expect(states, <bool>[false], reason: 'called with the current state');

        bool ran = false;
        await expectLater(
          b.runPrimaryTransaction('op', () async => ran = true),
          leaseLost,
        );
        expect(ran, isFalse);
        expect(b.isPrimary, isFalse);
        expect((await lease(a))!['owner_id'], 'A');
        // Ordinary transactions keep working.
        await b.runTransaction('op', () async {});
      },
    );

    test('the client that was taken over fails them', () async {
      final SQLitePersistence a = await start(
        'A',
        mode: PrimaryLeaseMode.forceOwnership,
      );
      final List<bool> states = <bool>[];
      a.setPrimaryStateListener(states.add);
      await start('B', mode: PrimaryLeaseMode.forceOwnership);

      await expectLater(
        a.runPrimaryTransaction('Apply remote event', () async {}),
        leaseLost,
      );
      expect(states, <bool>[true, false]);
    });

    test('a client takes the lease in one when it may', () async {
      final SQLitePersistence a = await start('A');
      final SQLitePersistence b = await start('B');
      final List<bool> states = <bool>[];
      b.setPrimaryStateListener(states.add);

      // A stopped refreshing and its lease expired.
      clock.advance(validity + 1);
      await b.runPrimaryTransaction('op', () async {});
      expect(b.isPrimary, isTrue);
      expect(states, <bool>[false, true]);
      expect((await lease(b))!['owner_id'], 'B');

      await expectLater(a.runPrimaryTransaction('op', () async {}), leaseLost);
      expect(await expectExactlyOnePrimary(), same(b));
    });

    test('the listener is not called once the client is shut down', () async {
      final SQLitePersistence a = await start('A');
      final List<bool> states = <bool>[];
      a.setPrimaryStateListener(states.add);
      await a.shutdown();
      expect(states, <bool>[true]);
    });
  });

  group('clients that are gone', () {
    test(
      'the primary removes them after 30 minutes, at most every 30 minutes',
      () async {
        final SQLitePersistence a = await start('A');
        final SQLitePersistence b = await start('B');
        await b.execute(
          'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, 1, 1)',
          <Object?>['crashed long ago', clock.now - clientAge - 1],
        );
        expect(await a.getActiveClients(), <String>['A', 'B']);

        // The first refresh of the primary collects.
        await a.refreshClientMetadata();
        expect((await clientRows(a)).keys, unorderedEquals(<String>['A', 'B']));

        // B stops refreshing. Only the primary collects, and only once per 30 minutes.
        await a.execute(
          'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, 1, 1)',
          <Object?>['crashed', clock.now - clientAge - 1],
        );
        await b.refreshClientMetadata();
        await a.refreshClientMetadata();
        expect(
          (await clientRows(a)).keys,
          unorderedEquals(<String>['A', 'B', 'crashed']),
        );

        for (int elapsed = 0; elapsed <= clientAge; elapsed += 60000) {
          clock.advance(60000);
          await a.refreshClientMetadata();
        }
        expect((await clientRows(a)).keys, <String>['A']);
        expect(await a.getActiveClients(), <String>['A']);
      },
    );

    test('a client from the future is removed', () async {
      final SQLitePersistence a = await start('A');
      await a.execute(
        'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, 1, 1)',
        <Object?>['clock ahead', clock.now + clientAge],
      );
      await a.refreshClientMetadata();
      expect((await clientRows(a)).keys, <String>['A']);
    });
  });

  group('clearPersistence with other clients alive', () {
    test('empties the cache in place and the others notice', () async {
      final SQLitePersistence a = await start('A');
      final SQLitePersistence b = await start('B');
      int cleared = 0;
      b.databaseClearedListener = () => cleared++;
      await a.runTransaction('write', () async {
        await a.execute(
          'INSERT INTO bundles (bundle_id, create_time_seconds, create_time_nanos, schema_version, '
          'total_documents, total_bytes) VALUES (?, 0, 0, 1, 0, 0)',
          <Object?>['b'],
        );
        await a.queryCache.setLastRemoteSnapshotVersion(
          a.queryCache.lastRemoteSnapshotVersion,
        );
      });
      await a.shutdown();
      await a.clearPersistence();

      // The file is still there, emptied, with a new epoch.
      expect(DatabaseMock.pathForName(name).existsSync(), isTrue);
      expect(await b.query('SELECT * FROM bundles'), isEmpty);
      expect(
        (await b.query('SELECT epoch FROM persistence_epoch')).single['epoch'],
        1,
      );
      expect(await b.query('SELECT * FROM target_globals'), hasLength(1));

      final Matcher clearedError = throwsA(
        isA<FirestoreError>()
            .having(
              (FirestoreError e) => e.code,
              'code',
              FirestoreErrorCode.failedPrecondition,
            )
            .having(
              (FirestoreError e) => e.message,
              'message',
              contains('cleared by another client'),
            ),
      );
      await expectLater(b.runTransaction('after', () async {}), clearedError);
      await expectLater(b.refreshClientMetadata(), clearedError);
      await pumpEventQueue();
      expect(cleared, 1);

      // A new client starts on the emptied cache.
      await b.shutdown();
      final SQLitePersistence c = await start('C');
      expect(c.isPrimary, isTrue);
      expect(c.queryCache.highestTargetId, 0);
      expect(c.queryCache.targetCount, 0);
    });

    test('a table name from the file is not run as SQL', () async {
      // Another process that can write the file names a table so that the
      // statement which empties it would attach (create) another file.
      final Directory temp = Directory.systemTemp.createTempSync('lease');
      addTearDown(() => temp.deleteSync(recursive: true));
      final String attached = '${temp.path}/attached.db';
      final SQLitePersistence a = await start('A');
      final SQLitePersistence b = await start('B');
      final String table =
          'x"; ATTACH DATABASE \'$attached\' AS other; '
          'CREATE TABLE other.t (a); --';
      await b.execute('CREATE TABLE x (a)');
      await b.execute('CREATE TABLE "${table.replaceAll('"', '""')}" (a)');
      await b.execute(
        'INSERT INTO "${table.replaceAll('"', '""')}" (a) VALUES (1)',
      );
      await a.shutdown();
      await a.clearPersistence();

      expect(File(attached).existsSync(), isFalse);
      expect(
        await b.query('SELECT * FROM "${table.replaceAll('"', '""')}"'),
        isEmpty,
      );
    });

    test('leaves nothing of the deleted rows in the file', () async {
      const String marker = 'secret-document-marker-0123456789';
      final SQLitePersistence a = await start('A');
      final SQLitePersistence b = await start('B');
      await a.runTransaction('write', () async {
        for (int i = 0; i < 50; i++) {
          await a.execute(
            'INSERT INTO bundles (bundle_id, create_time_seconds, create_time_nanos, schema_version, '
            'total_documents, total_bytes) VALUES (?, 0, 0, 1, 0, 0)',
            <Object?>['$marker-$i'],
          );
        }
      });
      await a.shutdown();
      await a.clearPersistence();

      expect(await b.query('SELECT * FROM bundles'), isEmpty);
      final String path = DatabaseMock.pathForName(name).path;
      for (final String file in <String>[path, '$path-wal']) {
        if (File(file).existsSync()) {
          expect(
            String.fromCharCodes(File(file).readAsBytesSync()),
            isNot(contains(marker)),
            reason: file,
          );
        }
      }
    });

    test('deletes the file when the other clients are gone', () async {
      final SQLitePersistence a = await start('A');
      await a.execute(
        'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, 1, 1)',
        <Object?>['gone', clock.now - clientAge - 1],
      );
      await a.shutdown();
      await a.clearPersistence();
      expect(DatabaseMock.pathForName(name).existsSync(), isFalse);
    });
  });

  group('rows that this SDK did not write (S16, S17)', () {
    test('a malformed lease counts as no lease', () async {
      final SQLitePersistence a = await start('A');
      for (final List<Object?> row in <List<Object?>>[
        <Object?>['A', 1, 1.5],
        <Object?>[42, 1, clock.now],
        <Object?>['A', 'yes', clock.now],
      ]) {
        await a.execute(
          'UPDATE primary_client SET owner_id = ?, allow_synchronization = ?, lease_timestamp_ms = ?',
          row,
        );
        // A new client starts and takes the lease, which is well-formed again.
        final SQLitePersistence b = await start('B-${row.join()}');
        expect(b.isPrimary, isTrue, reason: '$row');
        expect((await lease(b))!['lease_timestamp_ms'], clock.now);
        // A running client refreshes without failing.
        await a.refreshClientMetadata();
        await b.shutdown();
      }
    });

    test('malformed client rows take no part in the election', () async {
      final SQLitePersistence a = await start('A');
      await a.execute(
        'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, ?, ?)',
        <Object?>['odd', 'now', 1, 1],
      );
      await a.execute(
        'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, ?, ?)',
        <Object?>['odd too', clock.now, 'yes', 1],
      );
      await a.execute(
        'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, ?, ?)',
        <Object?>[7, clock.now, 0, 1],
      );
      // Well-formed rows of clients with network would take the lease from A now.
      await a.setNetworkEnabled(false);
      expect(a.isPrimary, isTrue);
      // The client id column has TEXT affinity: 7 is stored as '7'.
      expect(await a.getActiveClients(), <String>['7', 'A', 'odd too']);
    });

    test(
      'a missing epoch row: running clients stop, new clients start',
      () async {
        final SQLitePersistence a = await start('A');
        final SQLitePersistence b = await start('B');
        await b.execute('DELETE FROM persistence_epoch');
        // The deletion is a commit of another connection for A: as after a clear.
        await expectLater(
          a.runTransaction('after', () async {}),
          throwsA(isA<FirestoreError>()),
        );

        final SQLitePersistence c = await start('C');
        expect(c.started, isTrue);
        expect(
          (await c.query(
            'SELECT epoch FROM persistence_epoch',
          )).single['epoch'],
          0,
        );
      },
    );

    test(
      'an epoch that is not an integer is repaired by a new client',
      () async {
        final SQLitePersistence a = await start('A');
        // An epoch past 2^63 is stored as a REAL.
        await a.execute('UPDATE persistence_epoch SET epoch = 9.3e18');
        await a.shutdown();
        final SQLitePersistence b = await start('B');
        expect(b.started, isTrue);
        expect(
          (await b.query(
            'SELECT epoch FROM persistence_epoch',
          )).single['epoch'],
          0,
        );
        // A clear in place still moves it on.
        await b.execute('UPDATE persistence_epoch SET epoch = 1.5');
        final SQLitePersistence c = await start('C');
        await b.shutdown();
        await b.clearPersistence();
        expect(
          (await c.query(
            'SELECT epoch FROM persistence_epoch',
          )).single['epoch'],
          isA<int>(),
        );
      },
    );

    test('a client row from the future does not keep the file from being '
        'deleted', () async {
      final SQLitePersistence a = await start('A');
      await a.execute(
        'INSERT INTO clients (client_id, update_time_ms, network_enabled, in_foreground) VALUES (?, ?, 1, 1)',
        <Object?>['clock ahead', clock.now + 60000],
      );
      await a.shutdown();
      await a.clearPersistence();
      expect(DatabaseMock.pathForName(name).existsSync(), isFalse);
    });

    test('a lease from the future is reported once a minute', () async {
      final SQLitePersistence a = await start('A');
      final List<String> printed = await capturePrints(() async {
        // Every refresh finds a lease from the future again (A takes it, something writes it back).
        Future<void> refreshWithFutureLease() async {
          await a.execute(
            'UPDATE primary_client SET owner_id = ?, lease_timestamp_ms = ?',
            <Object?>['Z', clock.now + 3600000],
          );
          await a.refreshClientMetadata();
        }

        for (int i = 0; i < 10; i++) {
          clock.advance(refresh);
          await refreshWithFutureLease();
        }
        clock.advance(60000);
        await refreshWithFutureLease();
      });
      expect(
        printed.where((String line) => line.contains('in the future')),
        hasLength(2),
      );
    });
  });

  group('clients in several isolates', () {
    test('exactly one primary through takeover, crash and termination', () async {
      final List<_IsolateClient> isolates = <_IsolateClient>[];
      addTearDown(() async {
        for (final _IsolateClient client in isolates) {
          await client.close();
        }
      });
      for (final String id in <String>['A', 'B', 'C']) {
        isolates.add(await _IsolateClient.spawn(name, id, clock.now));
      }
      final _IsolateClient a = isolates[0];
      final _IsolateClient b = isolates[1];
      final _IsolateClient c = isolates[2];

      Future<String> onePrimary(List<_IsolateClient> running) async {
        final List<String> primaries = <String>[];
        for (final _IsolateClient client in running) {
          if (await client.send('look', clock.now)) {
            primaries.add(client.id);
          }
        }
        expect(primaries, hasLength(1), reason: '$primaries');
        return primaries.single;
      }

      expect(await onePrimary(isolates), 'A');

      // Normal refreshes, all at the same moment.
      for (int i = 0; i < 3; i++) {
        clock.advance(refresh);
        await Future.wait(<Future<bool>>[
          for (final _IsolateClient client in isolates)
            client.send('refresh', clock.now),
        ]);
        expect(await onePrimary(isolates), 'A');
      }

      // A stops refreshing: B and C wait for the validity, then exactly one of them takes over.
      clock.advance(validity);
      await Future.wait(<Future<bool>>[
        b.send('refresh', clock.now),
        c.send('refresh', clock.now),
      ]);
      expect(await onePrimary(isolates), 'A');
      clock.advance(1);
      await Future.wait(<Future<bool>>[
        b.send('refresh', clock.now),
        c.send('refresh', clock.now),
      ]);
      final String afterCrash = await onePrimary(isolates);
      expect(afterCrash, isIn(<String>['B', 'C']));

      // The new primary terminates: the other one takes over at its next refresh, without waiting.
      final _IsolateClient leaving = afterCrash == 'B' ? b : c;
      final _IsolateClient staying = afterCrash == 'B' ? c : b;
      await leaving.send('shutdown', clock.now);
      await staying.send('refresh', clock.now);
      await a.send('refresh', clock.now);
      expect(await onePrimary(<_IsolateClient>[a, staying]), staying.id);
    });
  });
}

/// A client in its own isolate, driven by messages. Its clock is the time of the last message.
class _IsolateClient {
  _IsolateClient._(this.id, this._isolate, this._commands, this._replies);

  final String id;
  final Isolate _isolate;
  final SendPort _commands;
  final StreamIterator<Object?> _replies;

  static Future<_IsolateClient> spawn(String name, String id, int now) async {
    final ReceivePort replies = ReceivePort();
    final Isolate isolate = await Isolate.spawn(_run, <Object?>[
      name,
      id,
      now,
      replies.sendPort,
    ]);
    final StreamIterator<Object?> iterator = StreamIterator<Object?>(replies);
    expect(await iterator.moveNext(), isTrue);
    final SendPort commands = iterator.current! as SendPort;
    expect(await iterator.moveNext(), isTrue);
    return _IsolateClient._(id, isolate, commands, iterator);
  }

  /// Sends [command] at the time [now] and returns whether the client is primary afterwards.
  Future<bool> send(String command, int now) async {
    _commands.send(<Object?>[command, now]);
    expect(await _replies.moveNext(), isTrue);
    final Object? reply = _replies.current;
    if (reply is String) {
      fail('client $id failed to $command: $reply');
    }
    return reply! as bool;
  }

  Future<void> close() async {
    _isolate.kill(priority: Isolate.immediate);
    await _replies.cancel();
  }

  static Future<void> _run(List<Object?> args) async {
    final String name = args[0]! as String;
    final String id = args[1]! as String;
    int now = args[2]! as int;
    final SendPort replies = args[3]! as SendPort;
    final ReceivePort commands = ReceivePort();
    replies.send(commands.sendPort);

    final SQLitePersistence persistence = await createClient(
      name,
      id,
      () => now,
    );
    await persistence.start();
    replies.send(persistence.isPrimary);

    await for (final Object? message in commands) {
      final List<Object?> command = message! as List<Object?>;
      now = command[1]! as int;
      try {
        switch (command[0]) {
          case 'refresh':
            await persistence.refreshClientMetadata();
          case 'look':
            await persistence.runTransaction('look', () async {});
          case 'shutdown':
            await persistence.shutdown();
        }
        replies.send(persistence.isPrimary);
      } catch (e) {
        replies.send('$e');
      }
    }
  }
}
