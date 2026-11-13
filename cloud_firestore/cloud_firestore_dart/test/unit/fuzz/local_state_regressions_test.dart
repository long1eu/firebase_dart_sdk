// Regression tests for crashes found by fuzzing the state that other
// processes and clients write: the rows of the SQLite cache, the multi-client
// tables and the SharedClientState entries. One test per fix.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/online_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/serial_queue.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/shared_client_state_storage.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/stored_proto.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/proto/index.dart' as proto;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

import '../../util/sqlite3_database.dart';
import '../../util/test_util.dart' as util;
import '../firebase/firestore/local/persistence_test_helpers.dart';
import 'multi_client_tables_fuzz_test.dart'
    show FakeClock, createClient, newName;
import 'shared_client_state_fuzz_test.dart' show Syncer;

/// Bytes for which protobuf 6.1.0 throws a RangeError, not an
/// InvalidProtocolBufferException (a string length past the end).
final Uint8List rangeErrorBytes = Uint8List.fromList(<int>[
  50, 172, 162, 156, 190, 94, //
]);

/// Bytes for which protobuf 6.1.0 throws an ArgumentError (a negative length).
final Uint8List argumentErrorBytes = Uint8List.fromList(<int>[
  10, 217, 212, 141, 179, 13, //
]);

/// Matches the internal assertion upstream fails for a row it cannot parse.
Matcher failsToParse(String what) => throwsA(
  isA<StateError>().having(
    (StateError e) => e.message,
    'message',
    startsWith('$what failed to parse'),
  ),
);

void main() {
  group('protos stored in the SQLite cache', () {
    test('quirk: protobuf throws errors other than '
        'InvalidProtocolBufferException for malformed lengths', () {
      expect(
        () => proto.MaybeDocument.fromBuffer(rangeErrorBytes),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => proto.MaybeDocument.fromBuffer(argumentErrorBytes),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e is RangeError,
            'is a RangeError',
            isFalse,
          ),
        ),
      );
      expect(
        () => proto.MaybeDocument.fromBuffer(<int>[0]),
        throwsA(isA<InvalidProtocolBufferException>()),
      );
    });

    test('every parse error of a stored proto fails like upstream', () {
      for (final List<int> bytes in <List<int>>[
        rangeErrorBytes,
        argumentErrorBytes,
        <int>[0],
      ]) {
        expect(
          () => parseStoredProto(
            'MaybeDocument',
            () => proto.MaybeDocument.fromBuffer(bytes),
          ),
          failsToParse('MaybeDocument'),
          reason: '$bytes',
        );
      }
    });

    test('a corrupt remote document row fails to parse instead of a '
        'RangeError', () async {
      final SQLitePersistence persistence = await createSQLitePersistence();
      addTearDown(persistence.shutdown);
      final DocumentKey key = util.key('coll/doc');
      await persistence.runTransaction('add', () async {
        await persistence.remoteDocumentCache.add(
          util.doc('coll/doc', 1, <String, Object?>{'a': 1}),
          util.version(1),
        );
      });

      for (final Uint8List corrupt in <Uint8List>[
        rangeErrorBytes,
        argumentErrorBytes,
      ]) {
        await persistence.database.execute(
          'UPDATE remote_documents SET contents = ?',
          <Object?>[corrupt],
        );
        await expectLater(
          persistence.runTransactionAndReturn(
            'read',
            () => persistence.remoteDocumentCache.get(key),
          ),
          failsToParse('MaybeDocument'),
          reason: '$corrupt',
        );
      }
    });
  });

  group('multi-client tables written by another process', () {
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

    Future<SQLitePersistence> start(String clientId) async {
      final SQLitePersistence client = await createClient(
        name,
        clientId,
        clock,
      );
      await client.start();
      clients.add(client);
      return client;
    }

    /// Recreates [table] without its constraints, as another program may.
    Future<void> dropConstraints(
      SQLitePersistence client,
      String table,
      String columns,
    ) async {
      await client.database.execute('CREATE TABLE copy ($columns)');
      await client.database.execute('INSERT INTO copy SELECT * FROM $table');
      await client.database.execute('DROP TABLE $table');
      await client.database.execute('ALTER TABLE copy RENAME TO $table');
    }

    Future<int> count(SQLitePersistence client, String table) async =>
        (await client.database.query(
              'SELECT COUNT(*) AS n FROM $table',
            )).single['n']
            as int;

    test('a client starts on an epoch row that is there twice', () async {
      final SQLitePersistence a = await start('a');
      await dropConstraints(a, 'persistence_epoch', 'id, epoch');
      await a.database.execute('INSERT INTO persistence_epoch VALUES (0, 7)');
      // rows.single failed with "Too many elements".
      final SQLitePersistence b = await start('b');
      expect(b.started, isTrue);
      expect(await count(b, 'persistence_epoch'), 1);
    });

    test(
      'a lease row that is there twice is no lease, and is replaced by one',
      () async {
        final SQLitePersistence a = await start('a');
        await dropConstraints(
          a,
          'primary_client',
          'id, owner_id, allow_synchronization, lease_timestamp_ms',
        );
        await a.database.execute(
          "INSERT INTO primary_client VALUES (0, 'other', 1, ?)",
          <Object?>[clock.now],
        );
        await a.refreshClientMetadata();
        expect(a.isPrimary, isTrue);
        expect(await count(a, 'primary_client'), 1);
        await a.refreshClientMetadata();
        expect(await count(a, 'primary_client'), 1);
      },
    );

    test(
      'a clients table without its key does not grow at every refresh',
      () async {
        final SQLitePersistence a = await start('a');
        await dropConstraints(
          a,
          'clients',
          'client_id, update_time_ms, network_enabled, in_foreground',
        );
        for (int i = 0; i < 3; i++) {
          clock.now += 4000;
          await a.refreshClientMetadata();
        }
        expect(await count(a, 'clients'), 1);
      },
    );

    test(
      'a session token stored as text or a number is read as bytes',
      () async {
        final SQLitePersistence a = await start('a');
        for (final (Object value, List<int> bytes) in <(Object, List<int>)>[
          ('tökén', utf8.encode('tökén')),
          (42, utf8.encode('42')),
        ]) {
          await a.database.execute(
            "INSERT OR REPLACE INTO globals VALUES ('sessionToken', ?)",
            <Object?>[value],
          );
          // A cast to List<int> failed with a TypeError.
          expect(
            await a.runTransactionAndReturn(
              'token',
              () => a.globalsCache.getSessionToken(),
            ),
            bytes,
          );
        }
      },
    );
  });

  group('SharedClientState entries of other clients', () {
    const String key = 'firestore/[DEFAULT]/test-project';

    /// Starts a client, writes [entries] as another client, and returns the
    /// errors of applying them on the queue of the client.
    Future<List<Object>> apply(Map<String, String> entries) async {
      final InMemorySharedClientStateStorage bus =
          InMemorySharedClientStateStorage();
      final SharedClientStateStorage storage = bus.connect();
      final SharedClientStateStorage other = bus.connect();
      final SerialQueue queue = SerialQueue();
      final List<Object> errors = <Object>[];
      final List<Future<void>> operations = <Future<void>>[];
      final StorageSharedClientState state = StorageSharedClientState(
        storage,
        (Future<void> Function() operation) {
          final Future<void> result = queue.run<void>(operation);
          operations.add(result.catchError(errors.add));
          return result.catchError((_) {});
        },
        key,
        'local',
        const User('user'),
      );
      final Syncer syncer = Syncer();
      state
        ..syncEngine = syncer
        ..onlineStateHandler = (OnlineState _) {};
      await state.start();
      entries.forEach(other.setItem);
      await Future.wait(operations);
      state.shutdown();
      return errors;
    }

    test(
      'a batch or target id that does not fit an integer is ignored',
      () async {
        final String digits = '9' * 30;
        // int.parse threw a FormatException on the queue of the client.
        expect(
          await apply(<String, String>{
            'firestore_mutations_${key}_${digits}_user': '{"state":"pending"}',
            'firestore_targets_${key}_$digits': '{"state":"current"}',
          }),
          isEmpty,
        );
      },
    );

    test(
      'a loaded bundle entry that is not a list of names is ignored',
      () async {
        // A cast to String threw a TypeError on the queue of the client.
        expect(
          await apply(<String, String>{
            'firestore_bundle_loaded_v2_$key': '["coll", 1, null]',
          }),
          isEmpty,
        );
      },
    );
  });
}
