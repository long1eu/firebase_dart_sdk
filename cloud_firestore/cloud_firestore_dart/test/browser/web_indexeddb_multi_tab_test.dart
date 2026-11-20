// The multi-tab mode of the IndexedDB engine at the persistence level, in a browser: two persistences on one database
// in one page (IndexedDB is shared by the page), standing for two tabs. The primary lease, its handover, the
// secondary's primary-only transactions, and a one-tab and a multi-tab client refusing each other.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_multi_tab_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_error.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_schema.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/idb.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/indexeddb_persistence_web.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../util/test_util.dart';
import 'indexeddb_test_persistence.dart';

void main() {
  late String key;
  final List<WebIndexedDbPersistence> opened = <WebIndexedDbPersistence>[];

  setUp(() {
    key = newIndexedDbPersistenceKey('idb-multi-tab');
  });

  tearDown(() async {
    String? name;
    for (final WebIndexedDbPersistence persistence in opened) {
      name = persistence.databaseName;
      if (persistence.started) {
        await persistence.shutdown();
      }
    }
    opened.clear();
    if (name != null) {
      await deleteIndexedDbDatabase(name);
    }
  });

  /// A client ("tab") of the database of this test.
  Future<WebIndexedDbPersistence> open(
    String clientId, {
    bool multiTab = true,
  }) async {
    final WebIndexedDbPersistence persistence =
        await newIndexedDbTestPersistence(
          persistenceKey: key,
          clientId: clientId,
          multiTab: multiTab,
        );
    opened.add(persistence);
    return persistence;
  }

  /// The primary states [persistence] reports, starting with the current one.
  List<bool> primaryStates(WebIndexedDbPersistence persistence) {
    final List<bool> states = <bool>[];
    persistence.setPrimaryStateListener(states.add);
    return states;
  }

  Future<Map<String, Object?>?> readOwner(String name) async {
    final web.IDBDatabase db =
        (await idbRequest(web.window.indexedDB.open(name)))! as web.IDBDatabase;
    try {
      final Object? row = idbToDart(
        await idbRequest(
          db
              .transaction(DbStores.owner.toJS)
              .objectStore(DbStores.owner)
              .get(DbStores.ownerKey.toJS),
        ),
      );
      return row is Map ? row.cast<String, Object?>() : null;
    } finally {
      db.close();
    }
  }

  Matcher primaryLeaseLoss() => predicate<Object>(
    isPrimaryLeaseLoss,
    'the error of a client that is not primary',
  );

  Matcher refusal() => isA<FirestoreException>()
      .having(
        (FirestoreException e) => e.errorCode,
        'errorCode',
        FirestoreErrorCode.failedPrecondition,
      )
      .having(
        (FirestoreException e) => e.message,
        'message',
        contains('only one tab at a time may use it'),
      );

  test('one client becomes primary, the other secondary', () async {
    final WebIndexedDbPersistence a = await open('client-a');
    final WebIndexedDbPersistence b = await open('client-b');

    expect(a.isPrimary, isTrue);
    expect(b.isPrimary, isFalse);
    expect(primaryStates(a), <bool>[true]);
    expect(primaryStates(b), <bool>[false]);

    final Map<String, Object?>? owner = await readOwner(a.databaseName);
    expect(owner?['ownerId'], 'client-a');
    expect(owner?['allowTabSynchronization'], isTrue);
    expect(
      await a.getActiveClients(),
      unorderedEquals(<String>['client-a', 'client-b']),
    );
    expect(
      await b.getActiveClients(),
      unorderedEquals(<String>['client-a', 'client-b']),
    );
    expect(
      await countIndexedDbRows(a.databaseName, DbStores.clientMetadata),
      2,
    );

    // A refresh keeps the roles.
    await b.refreshClientMetadata();
    await a.refreshClientMetadata();
    expect(a.isPrimary, isTrue);
    expect(b.isPrimary, isFalse);
  });

  test('a primary-only transaction fails on the secondary', () async {
    final WebIndexedDbPersistence a = await open('client-a');
    final WebIndexedDbPersistence b = await open('client-b');
    final List<bool> statesB = primaryStates(b);

    await expectLater(
      b.runPrimaryTransaction<int>('primary only', () async => 1),
      throwsA(primaryLeaseLoss()),
    );
    expect(b.isPrimary, isFalse);
    expect(statesB, <bool>[false]);

    // Other transactions work on the secondary, and the primary's on the primary.
    expect(await b.runTransactionAndReturn<int>('any', () async => 2), 2);
    expect(
      await a.runPrimaryTransaction<int>('primary only', () async => 3),
      3,
    );
  });

  test('the secondary takes over when the primary shuts down', () async {
    final WebIndexedDbPersistence a = await open('client-a');
    final WebIndexedDbPersistence b = await open('client-b');
    final List<bool> statesB = primaryStates(b);

    await a.shutdown();
    expect(await readOwner(b.databaseName), isNull);
    expect(await b.getActiveClients(), <String>['client-b']);

    await b.refreshClientMetadata();
    expect(b.isPrimary, isTrue);
    expect(statesB, <bool>[false, true]);
    expect((await readOwner(b.databaseName))?['ownerId'], 'client-b');
    expect(
      await b.runPrimaryTransaction<int>('primary only', () async => 1),
      1,
    );
  });

  test('the secondary takes over when the lease expires', () async {
    final WebIndexedDbPersistence a = await open('client-a');
    final WebIndexedDbPersistence b = await open('client-b');
    final List<bool> statesA = primaryStates(a);
    final List<bool> statesB = primaryStates(b);

    // A stops refreshing (a tab whose timers the browser froze): the lease lapses after 5 s.
    await b.refreshClientMetadata();
    expect(b.isPrimary, isFalse);
    await Future<void>.delayed(
      const Duration(milliseconds: indexedDbPrimaryLeaseMs + 500),
    );
    await b.refreshClientMetadata();
    expect(b.isPrimary, isTrue);
    expect(statesB, <bool>[false, true]);
    expect((await readOwner(b.databaseName))?['ownerId'], 'client-b');

    // A finds out at its next primary-only transaction, or its next refresh, and stays open as a secondary.
    await expectLater(
      a.runPrimaryTransaction<int>('primary only', () async => 1),
      throwsA(primaryLeaseLoss()),
    );
    expect(a.isPrimary, isFalse);
    expect(statesA, <bool>[true, false]);
    await a.refreshClientMetadata();
    expect(a.isPrimary, isFalse);
    expect(statesA, <bool>[true, false]);
    expect(await a.runTransactionAndReturn<int>('any', () async => 2), 2);
  });

  test(
    'a hidden primary without network gives the lease to a better client',
    () async {
      final WebIndexedDbPersistence a = await open('client-a');
      final WebIndexedDbPersistence b = await open('client-b');

      // Hidden, but online: it keeps the lease.
      await a.setInForeground(false);
      expect(a.isPrimary, isTrue);

      // Offline as well: B (visible and online) is better placed.
      await b.refreshClientMetadata();
      await a.setNetworkEnabled(false);
      expect(a.isPrimary, isFalse);
      expect(await readOwner(a.databaseName), isNull);
      await b.refreshClientMetadata();
      expect(b.isPrimary, isTrue);

      // Back online and visible, A stays secondary while B holds the lease.
      await a.setNetworkEnabled(true);
      await a.setInForeground(true);
      expect(a.isPrimary, isFalse);
    },
  );

  test('the clients read the target metadata the other one wrote', () async {
    final WebIndexedDbPersistence a = await open('client-a');
    final WebIndexedDbPersistence b = await open('client-b');

    await a.runTransaction(
      'add a target',
      () => a.queryCache.addQueryData(
        QueryData(query('rooms').toTarget(), 1, 1, QueryPurpose.listen),
      ),
    );
    await b.runTransaction('add a target', () async {
      expect(b.queryCache.highestTargetId, 1);
      await b.queryCache.addQueryData(
        QueryData(query('halls').toTarget(), 2, 2, QueryPurpose.listen),
      );
    });
    await a.runTransaction('read', () async {
      expect(a.queryCache.highestTargetId, 2);
      expect(a.queryCache.targetCount, 2);
    });
  });

  test(
    'a multi-tab client refuses a database a one-tab client holds',
    () async {
      final WebIndexedDbPersistence single = await open(
        'client-single',
        multiTab: false,
      );
      expect(single.isPrimary, isTrue);
      expect(
        (await readOwner(single.databaseName))?['allowTabSynchronization'],
        isFalse,
      );

      await expectLater(open('client-multi'), throwsA(refusal()));
      expect(single.isPrimary, isTrue);
      expect(
        await single.runPrimaryTransaction<int>('primary only', () async => 1),
        1,
      );
    },
  );

  test(
    'a one-tab client refuses a database a multi-tab client holds',
    () async {
      final WebIndexedDbPersistence multi = await open('client-multi');
      expect(multi.isPrimary, isTrue);

      await expectLater(
        open('client-single', multiTab: false),
        throwsA(refusal()),
      );
      expect(multi.isPrimary, isTrue);
      expect(
        await multi.runPrimaryTransaction<int>('primary only', () async => 1),
        1,
      );
    },
  );

  test(
    'a multi-tab secondary stops when a one-tab client took the lapsed lease',
    () async {
      final WebIndexedDbPersistence a = await open('client-a');
      final WebIndexedDbPersistence b = await open('client-b');
      // A dies without releasing its lease, and a one-tab client takes the lapsed lease (as a JS tab with
      // persistentSingleTabManager would).
      await putLease(a.databaseName, 'client-single');
      final List<bool> statesB = primaryStates(b);

      await expectLater(
        b.runTransactionAndReturn<int>('any', () async => 1),
        throwsA(refusal()),
      );
      await b.refreshClientMetadata();
      expect(b.isPrimary, isFalse);
      expect(statesB, <bool>[false]);
    },
  );
}
