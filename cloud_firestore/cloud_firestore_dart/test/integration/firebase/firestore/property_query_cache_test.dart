// Property: the results that a client serves from its cache agree with the
// backend, for the memory and the SQLite persistence, with and without
// pending writes.
//
// For random collections (values of mixed types, missing fields, nulls, NaN,
// arrays, maps) and random queries (equality, ranges, in, not-in,
// array-contains(-any), composite and/or filters, several orderBy, limit,
// limitToLast, cursors), every query is answered by:
//  * the backend itself, through Firestore Lite (no cache, no local
//    evaluation): the reference;
//  * a listener of each client, once it is in sync with the backend;
//  * `get(Source.cache)` of each client while that listener is active, and
//    for the SQLite persistence also after it was removed (the target and the
//    documents stay in the cache; the memory cache collects them eagerly);
//  * `get(Source.cache)` of a query the client never listened to, while all
//    documents of the collection are cached (a scan of the collection);
//  * with pending writes: each client goes offline with all documents of the
//    collection cached, applies random set / merge / update / delete writes,
//    and answers the queries from its cache (`get(Source.cache)` and the
//    first snapshot of a listener). The writes are then committed and the
//    backend's answer after the commit is the reference.
//
// The second test opens two clients on one SQLite file: A writes, B reads
// from the cache after a listen, and the primary lease moves between them
// (the primary disables its network). Both are compared with the backend;
// see [_checkSharedCacheCase].
//
// Operands null and NaN of `in`, `not-in`, the array filters, `<=` and `>=`
// are not generated: a Standard edition backend never matches them, the SDK
// does (see "Values, queries and API" in docs/ARCHITECTURE.md and
// property_query_test.dart, which covers that case).
//
// By default the first test takes 15 to 80 seconds on the emulator (8
// collections), depending on the load of the machine, and the second about 75
// seconds (2 collections, mostly waiting for the lease to move).
// PROPERTY_SCALE=<n> runs n times as many collections, PROPERTY_SEED=<seed>
// reruns a failing case and PROPERTY_TRACE=1 prints every step.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart'
    show SQLiteClientMetadata;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/internal.dart' show InternalLogLevel;
import 'package:test/test.dart';

import '../../../unit/firebase/firestore/local/mock/database_mock.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/lite_test_util.dart' show newLiteTestFirestore;
import '../../../util/property.dart';
import '../../../util/property_backend.dart';

final String? needsEmulator = IntegrationTestUtil.emulatorHost == null
    ? 'Runs against the emulator only: set FIRESTORE_EMULATOR_HOST.'
    : null;

const int documentCount = 30;
const int queriesPerPhase = 40;
const int writeCount = 14;
const Duration syncTimeout = Duration(seconds: 15);

/// The queries of each phase of the shared cache property.
const int sharedQueriesPerPhase = 20;

/// How often the primary lease moves from A to B and back per collection of
/// the shared cache property.
const int leaseRounds = 2;

/// The longest a move of the primary lease may take: the lease is refreshed
/// every four seconds.
const Duration leaseTimeout = Duration(seconds: 20);

void main() {
  configureGeneratorsForBackend();
  IntegrationTestUtil.currentDatabasePath = 'integration/property_query_cache';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  test(
    'cached query results agree with the backend for the memory and the '
    'SQLite persistence, with and without pending writes',
    skip:
        needsEmulator ??
        IntegrationTestUtil.skipOnEnterprise(
          'an Enterprise edition database returns other documents for `!=` '
          'and `not-in` with a limit; see property_query_test.dart',
        ),
    () async {
      final _Stats stats = _Stats();
      final lite.Firestore backend = newLiteTestFirestore();
      final Firestore writer = await IntegrationTestUtil.testFirestore();
      final FirestoreSettings settings = IntegrationTestUtil.newTestSettings();
      final List<_Client> clients = <_Client>[
        _Client(
          'memory',
          await IntegrationTestUtil.testFirestore(
            settings.copyWith(persistenceEnabled: false),
          ),
          keepsTargets: false,
        ),
        _Client(
          'sqlite',
          await IntegrationTestUtil.testFirestore(settings),
          keepsTargets: true,
        ),
      ];

      for (int i = 0; i < cases(8); i++) {
        await _checkCase(
          caseSeed(i),
          backend: backend,
          writer: writer,
          clients: clients,
          stats: stats,
        );
        if (stats.failures.length >= _Stats.maxFailures) {
          break;
        }
      }
      print('query cache property: $stats');
      if (stats.failures.isNotEmpty) {
        fail(
          '${stats.failures.length} failure(s):\n\n'
          '${stats.failures.join('\n')}',
        );
      }
      // The generator must mostly produce queries that the SDK and the
      // backend accept.
      expect(
        stats.compared,
        greaterThan(cases(8) * clients.length * queriesPerPhase * 3 ~/ 2),
        reason: '$stats',
      );
      expect(stats.writesApplied, greaterThan(0), reason: '$stats');
    },
    timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))),
  );

  test(
    'two clients on one SQLite cache agree with the backend while the '
    'primary lease moves between them',
    skip:
        needsEmulator ??
        IntegrationTestUtil.skipOnEnterprise(
          'an Enterprise edition database returns other documents for `!=` '
          'and `not-in` with a limit; see property_query_test.dart',
        ),
    () async {
      final _Stats stats = _Stats();
      final lite.Firestore backend = newLiteTestFirestore();
      final Firestore writer = await IntegrationTestUtil.testFirestore();
      for (int i = 0; i < cases(2); i++) {
        await _checkSharedCacheCase(
          caseSeed(5000 + i),
          backend: backend,
          writer: writer,
          stats: stats,
        );
        if (stats.failures.length >= _Stats.maxFailures) {
          break;
        }
      }
      print('shared cache query property: $stats');
      if (stats.failures.isNotEmpty) {
        fail(
          '${stats.failures.length} failure(s):\n\n'
          '${stats.failures.join('\n')}',
        );
      }
      // One comparison per query and phase (two phases per round); the SDK
      // and the backend must accept at least half of the queries.
      expect(
        stats.compared,
        greaterThan(cases(2) * leaseRounds * sharedQueriesPerPhase),
        reason: '$stats',
      );
      expect(stats.writesApplied, greaterThan(0), reason: '$stats');
    },
    timeout: Timeout(Duration(minutes: 2 + 2 * cases(1))),
  );
}

class _Client {
  _Client(this.name, this.firestore, {required this.keepsTargets});

  final String name;
  final Firestore firestore;

  /// Whether the target and its documents stay in the cache after the last
  /// listener of a query is removed (not with eager garbage collection).
  final bool keepsTargets;
}

class _Stats {
  int compared = 0;
  int rejectedBySdk = 0;
  int rejectedByBackend = 0;
  int writesApplied = 0;
  int writesRejected = 0;
  int limitListenersInLimbo = 0;
  int leaseTakenAfterStall = 0;
  final List<String> failures = <String>[];

  static const int maxFailures = 8;

  @override
  String toString() =>
      'compared $compared query results; the SDK rejected $rejectedBySdk, '
      'the backend $rejectedByBackend queries; $writesApplied writes '
      'committed, $writesRejected rejected (update of a missing document)'
      '${limitListenersInLimbo == 0 ? '' : '; $limitListenersInLimbo limit '
                'listeners waited for the writes of the other client'}'
      '${leaseTakenAfterStall == 0 ? '' : '; the secondary took the lease '
                'after $leaseTakenAfterStall stalls and gave it back'}';
}

/// One generated write; [data] holds references of the writer, see [_rebind].
class _Write {
  _Write(this.id, this.kind, this.data);

  final String id;
  final String kind;
  final Map<String, Object?>? data;

  @override
  String toString() =>
      '$id.$kind(${data == null ? '' : describe(_withoutSentinels(data))})';
}

Object? _withoutSentinels(Object? value) => switch (value) {
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry<String, Object?> e in map.entries)
      e.key: e.value is FieldValue ? '<delete>' : _withoutSentinels(e.value),
  },
  _ => value,
};

/// [value] with every document reference replaced by the same path in
/// [firestore]: a client only accepts its own references.
Object? _rebind(Object? value, Firestore firestore) => switch (value) {
  final DocumentReference<Object?> ref => firestore.doc(ref.path),
  final List<Object?> list => <Object?>[
    for (final Object? v in list) _rebind(v, firestore),
  ],
  final Map<String, Object?> map => <String, Object?>{
    for (final MapEntry<String, Object?> e in map.entries)
      e.key: _rebind(e.value, firestore),
  },
  _ => value,
};

String _id(int i) => 'd${i.toString().padLeft(2, '0')}';

List<_Write> _generateWrites(Gen gen, List<Object?> pool) {
  const List<String> fields = <String>['a', 'b', 'c', 'd'];
  Object? valueOrDelete() =>
      gen.chance(20) ? FieldValue.delete() : gen.pick(pool);
  return <_Write>[
    for (int i = 0; i < writeCount; i++)
      () {
        final String id = gen.chance(80)
            ? _id(gen.below(documentCount))
            : 'n${gen.below(4)}';
        switch (gen.below(4)) {
          case 0:
            return _Write(id, 'set', queryDocument(gen, pool));
          case 1:
            return _Write(id, 'merge', <String, Object?>{
              for (int j = gen.between(1, 2); j > 0; j--)
                gen.pick(fields): valueOrDelete(),
              if (gen.chance(30)) 'm': <String, Object?>{'x': valueOrDelete()},
            });
          case 2:
            final String nested = gen.chance(50) ? 'm.x' : 'm';
            return _Write(id, 'update', <String, Object?>{
              for (int j = gen.between(1, 2); j > 0; j--)
                // A path and its parent can not both be updated.
                gen.pick(<String>[...fields, nested]): valueOrDelete(),
            });
          default:
            return _Write(id, 'delete', null);
        }
      }(),
  ];
}

/// Applies [write] to [collection]; the returned future completes when the
/// backend accepted or rejected it. Only an update of a missing document may
/// be rejected.
Future<void> _apply(
  _Write write,
  CollectionReference<Map<String, Object?>> collection,
  _Stats stats,
) {
  final DocumentReference<Map<String, Object?>> doc = collection.doc(write.id);
  final Map<String, Object?>? data =
      _rebind(write.data, collection.firestore) as Map<String, Object?>?;
  final Future<void> result = switch (write.kind) {
    'set' => doc.set(data!),
    'merge' => doc.set(data!, SetOptions.mergeAllFields),
    'update' => doc.update(data!),
    _ => doc.delete(),
  };
  return result.then(
    (_) => stats.writesApplied++,
    onError: (Object error) {
      if (write.kind == 'update' &&
          error is FirestoreError &&
          error.code == FirestoreErrorCode.notFound) {
        stats.writesRejected++;
        return;
      }
      throw StateError('$write failed: $error');
    },
  );
}

List<String> _ids(QuerySnapshot<Map<String, Object?>> snapshot) => <String>[
  for (final QueryDocumentSnapshot<Map<String, Object?>> doc in snapshot.docs)
    doc.id,
];

/// The documents the backend returns for [query], or null when it rejects
/// the query.
Future<List<String>?> _backendIds(
  lite.Firestore backend,
  Query<Map<String, Object?>> query,
  _Stats stats,
) async {
  try {
    final lite.QuerySnapshot<Map<String, Object?>> snapshot =
        await lite.Query<Map<String, Object?>>(query.query, backend).get();
    return <String>[
      for (final lite.QueryDocumentSnapshot<Map<String, Object?>> doc
          in snapshot.docs)
        doc.id,
    ];
  } on FirestoreError catch (e) {
    if (e.code == FirestoreErrorCode.invalidArgument ||
        e.code == FirestoreErrorCode.failedPrecondition ||
        e.code == FirestoreErrorCode.unimplemented) {
      stats.rejectedByBackend++;
      return null;
    }
    rethrow;
  }
}

/// The data of every document of [path] on the backend, for messages.
Future<Map<String, Object?>> _backendData(
  lite.Firestore backend,
  String path,
) async {
  final lite.QuerySnapshot<Map<String, Object?>> snapshot = await backend
      .collection(path)
      .get();
  return <String, Object?>{
    for (final lite.QueryDocumentSnapshot<Map<String, Object?>> doc
        in snapshot.docs)
      doc.id: doc.data,
  };
}

String _describeSnapshot(QuerySnapshot<Map<String, Object?>> snapshot) =>
    '${_ids(snapshot)}${snapshot.metadata.isFromCache ? ' from cache' : ''}'
    '${snapshot.metadata.hasPendingWrites ? ' with pending writes' : ''}';

/// Listens to [query] until a snapshot is in sync with the backend. Returns
/// the ids of that snapshot and the subscription, which stays active.
Future<(List<String>, StreamSubscription<QuerySnapshot<Map<String, Object?>>>)>
_listenUntilSynced(Query<Map<String, Object?>> query) async {
  final Completer<List<String>> synced = Completer<List<String>>();
  final List<String> seen = <String>[];
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      query
          .getSnapshots(MetadataChanges.include)
          .listen(
            (QuerySnapshot<Map<String, Object?>> snapshot) {
              seen.add(_describeSnapshot(snapshot));
              if (!snapshot.metadata.isFromCache &&
                  !snapshot.metadata.hasPendingWrites &&
                  !synced.isCompleted) {
                synced.complete(_ids(snapshot));
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!synced.isCompleted) {
                synced.completeError(error, stack);
              }
            },
          );
  try {
    return (
      await synced.future.timeout(
        syncTimeout,
        onTimeout: () => throw TimeoutException(
          'no snapshot in sync without pending writes; snapshots: $seen',
          syncTimeout,
        ),
      ),
      subscription,
    );
  } catch (_) {
    await subscription.cancel();
    rethrow;
  }
}

/// Listens to [query] until a snapshot is in sync with the backend, pending
/// writes allowed, or, with [settle], until that time passed with no such
/// snapshot. Returns the ids of the snapshot in sync (or the latest one),
/// whether it is in sync, and the subscription, which stays active.
Future<
  (List<String>, bool, StreamSubscription<QuerySnapshot<Map<String, Object?>>>)
>
_listenUntilSyncedOrSettled(
  Query<Map<String, Object?>> query, {
  Duration? settle,
}) async {
  final Completer<(List<String>, bool)> done =
      Completer<(List<String>, bool)>();
  final List<String> seen = <String>[];
  List<String>? latest;
  bool settled = false;
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      query
          .getSnapshots(MetadataChanges.include)
          .listen(
            (QuerySnapshot<Map<String, Object?>> snapshot) {
              seen.add(_describeSnapshot(snapshot));
              latest = _ids(snapshot);
              if (done.isCompleted) {
                return;
              }
              if (!snapshot.metadata.isFromCache) {
                done.complete((latest!, true));
              } else if (settled) {
                done.complete((latest!, false));
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!done.isCompleted) {
                done.completeError(error, stack);
              }
            },
          );
  final Timer? timer = settle == null
      ? null
      : Timer(settle, () {
          settled = true;
          if (!done.isCompleted && latest != null) {
            done.complete((latest!, false));
          }
        });
  try {
    final (List<String> ids, bool inSync) = await done.future.timeout(
      syncTimeout,
      onTimeout: () => throw TimeoutException(
        'no snapshot in sync; snapshots: $seen',
        syncTimeout,
      ),
    );
    return (ids, inSync, subscription);
  } catch (_) {
    await subscription.cancel();
    rethrow;
  } finally {
    timer?.cancel();
  }
}

/// The first snapshot of a listener of [query] (offline: from the cache).
Future<List<String>> _firstSnapshot(Query<Map<String, Object?>> query) async =>
    _ids(await query.getSnapshots().first.timeout(syncTimeout));

/// Compares [results] (source name to ids) with [expected] and records a
/// failure that shows all of them.
void _compare({
  required _Stats stats,
  required String context,
  required List<String> expected,
  required Map<String, List<String>> results,
  required Map<String, Object?> data,
}) {
  stats.compared++;
  final Map<String, List<String>> wrong = <String, List<String>>{
    for (final MapEntry<String, List<String>> e in results.entries)
      if (e.value.join(',') != expected.join(',')) e.key: e.value,
  };
  if (wrong.isEmpty || stats.failures.length >= _Stats.maxFailures) {
    return;
  }
  final Set<String> differing = <String>{
    for (final List<String> ids in wrong.values) ...<String>{
      ...ids.where((String id) => !expected.contains(id)),
      ...expected.where((String id) => !ids.contains(id)),
    },
  };
  stats.failures.add(
    'Property "cached query results match the backend" failed.\n'
    '$context\n'
    '  the backend returns: $expected\n'
    '${wrong.entries.map((MapEntry<String, List<String>> e) => '  ${e.key}: ${e.value}\n').join()}'
    '${differing.isEmpty ? '  (same documents, different order)\n' : '  documents on the backend:\n${differing.map((String id) => '    $id = ${data.containsKey(id) ? describe(data[id]) : '(missing)'}\n').join()}'}',
  );
}

Future<void> _checkCase(
  int seed, {
  required lite.Firestore backend,
  required Firestore writer,
  required List<_Client> clients,
  required _Stats stats,
}) async {
  final Gen gen = Gen(seed);
  final List<Object?> pool = queryValuePool(
    gen,
    (String id) => writer.doc('property_refs/$id'),
  );
  final Map<String, Map<String, Object?>> data = <String, Map<String, Object?>>{
    for (int i = 0; i < documentCount; i++) _id(i): queryDocument(gen, pool),
  };
  final List<_Write> writes = _generateWrites(gen, pool);

  for (final _Client client in clients) {
    // Every client gets a collection of its own with the same documents, so
    // that the writes of one client do not reach the cache of the other.
    final String path = 'property_query_cache_${autoId()}';
    // Every step has a deadline, so that a hang names the step.
    Future<T> step<T>(String what, Future<T> future) {
      if (traceProperties) {
        print('TRACE seed $seed, ${client.name}: $what');
      }
      return future.timeout(
        syncTimeout * 2,
        onTimeout: () => throw TimeoutException(
          'seed $seed (rerun with PROPERTY_SEED=$seed), client '
          '${client.name}: $what did not complete',
        ),
      );
    }

    await step('write the documents', writeAll(writer.collection(path), data));
    final CollectionReference<Map<String, Object?>> collection = client
        .firestore
        .collection(path);
    final List<Object?> clientPool = <Object?>[
      for (final Object? v in pool) _rebind(v, client.firestore),
    ];
    GeneratedQuery? query(int q) => generateQuery(
      Gen((seed + (q + 1) * 104729) & 0x7fffffff),
      collection,
      clientPool,
    );
    String context(String phase, int q, GeneratedQuery generated) =>
        '  seed: $seed (rerun with PROPERTY_SEED=$seed), client: '
        '${client.name}, $phase, query #$q:\n    $generated';

    // ------------------------------------------- without pending writes
    Map<String, Object?> serverData = await step(
      'read the collection from the backend',
      _backendData(backend, path),
    );
    for (int q = 0; q < queriesPerPhase; q++) {
      final GeneratedQuery? generated = query(q);
      if (generated == null) {
        stats.rejectedBySdk++;
        continue;
      }
      final List<String>? expected = await step(
        'run query #$q on the backend',
        _backendIds(backend, generated.query, stats),
      );
      if (expected == null) {
        continue;
      }
      final (
        List<String> listened,
        StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription,
      ) = await step(
        'listen to query #$q',
        _listenUntilSynced(generated.query),
      );
      final List<String> cached = _ids(
        await step(
          'query #$q from the cache',
          generated.query.get(Source.cache),
        ),
      );
      await step('stop listening to query #$q', subscription.cancel());
      _compare(
        stats: stats,
        context: context('no pending writes', q, generated),
        expected: expected,
        results: <String, List<String>>{
          'listener in sync': listened,
          'cache while listening': cached,
          if (client.keepsTargets)
            'cache after the listener was removed': _ids(
              await step(
                'query #$q from the cache after the listener',
                generated.query.get(Source.cache),
              ),
            ),
        },
        data: serverData,
      );
    }

    // ---------------------------------------------- with pending writes
    // The queries of this phase are new to the client. With every document
    // of the collection cached and no target for the query, the cache is
    // scanned and the documents are filtered and sorted locally.
    final (_, StreamSubscription<QuerySnapshot<Map<String, Object?>>> all) =
        await step('listen to the collection', _listenUntilSynced(collection));
    for (int q = queriesPerPhase; q < 2 * queriesPerPhase; q++) {
      final GeneratedQuery? generated = query(q);
      if (generated == null) {
        stats.rejectedBySdk++;
        continue;
      }
      final List<String>? expected = await step(
        'run query #$q on the backend',
        _backendIds(backend, generated.query, stats),
      );
      if (expected == null) {
        continue;
      }
      _compare(
        stats: stats,
        context: context(
          'no pending writes, all documents cached',
          q,
          generated,
        ),
        expected: expected,
        results: <String, List<String>>{
          'cache without a target': _ids(
            await step(
              'query #$q from the cache',
              generated.query.get(Source.cache),
            ),
          ),
        },
        data: serverData,
      );
    }

    await step('disable the network', client.firestore.disableNetwork());
    final List<Future<void>> committed = <Future<void>>[
      for (final _Write write in writes) _apply(write, collection, stats),
    ];
    final Map<int, Map<String, List<String>>> offline =
        <int, Map<String, List<String>>>{};
    for (int q = queriesPerPhase; q < 2 * queriesPerPhase; q++) {
      final GeneratedQuery? generated = query(q);
      if (generated == null) {
        continue;
      }
      offline[q] = <String, List<String>>{
        'cache with pending writes': _ids(
          await step(
            'query #$q from the cache with pending writes',
            generated.query.get(Source.cache),
          ),
        ),
        'listener with pending writes': await step(
          'listen to query #$q with pending writes',
          _firstSnapshot(generated.query),
        ),
      };
    }
    await step('enable the network', client.firestore.enableNetwork());
    await step('commit the writes', Future.wait(committed));
    await step(
      'wait for pending writes',
      client.firestore.waitForPendingWrites(),
    );
    await step('stop listening to the collection', all.cancel());

    serverData = await step(
      'read the collection from the backend',
      _backendData(backend, path),
    );
    for (final MapEntry<int, Map<String, List<String>>> entry
        in offline.entries) {
      final GeneratedQuery generated = query(entry.key)!;
      final List<String>? expected = await step(
        'run query #${entry.key} on the backend',
        _backendIds(backend, generated.query, stats),
      );
      if (expected == null) {
        continue;
      }
      _compare(
        stats: stats,
        context:
            '${context('pending writes, compared with the backend after the '
            'commit', entry.key, generated)}\n'
            '  writes: ${writes.join(', ')}',
        expected: expected,
        results: entry.value,
        data: serverData,
      );
    }
  }
}

String _describeLease(String name, Firestore firestore) =>
    '$name holds the lease ${firestore.client.isPrimaryClient}, acts as '
    'primary ${firestore.client.syncEngine.isPrimaryClient}, can use the '
    'network ${firestore.client.remoteStore.canUseNetwork}';

/// Waits until [primary] holds the primary lease of the shared cache and
/// [secondary] knows that it does not.
Future<void> _waitForLease(Firestore primary, Firestore secondary) async {
  bool settled() =>
      primary.client.isPrimaryClient &&
      primary.client.syncEngine.isPrimaryClient &&
      !secondary.client.isPrimaryClient &&
      !secondary.client.syncEngine.isPrimaryClient;
  final Stopwatch watch = Stopwatch()..start();
  while (!settled()) {
    if (watch.elapsed > leaseTimeout) {
      throw TimeoutException('the primary lease did not move', leaseTimeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// One collection of the shared cache property: clients A and B open one
/// SQLite file. A writes, B reads; the primary lease moves from A to B and
/// back [leaseRounds] times.
///
/// Each round:
///  1. A is primary. A commits random writes. For each query, A listens until
///     it is in sync and reads it from the cache; B, the secondary, listens
///     (from the cache) and reads it from the cache. All four answers are
///     compared with the backend.
///  2. A disables its network and B enables its own, which gives the lease to
///     B. A makes random writes, which stay pending in the shared mutation
///     queue: only A sends them, once it is primary again. For each query B
///     listens until it is in sync with the backend and reads it from the
///     cache, and A reads it from the cache. Both see A's pending writes.
///  3. A enables its network and B disables its own, which moves the lease
///     back to A. A sends its writes; the answers of step 2 are compared with
///     the backend after they are committed.
///
/// The secondary always has its network disabled (it does not use it). The
/// lease is valid for five seconds after a refresh, and refreshed every four:
/// when the timers of the isolate run more than a second late (a loaded
/// machine), the lease expires and the other client takes it. With the
/// network of the secondary disabled, the election gives the lease back to
/// the client with network on the next refreshes. With both online the
/// lease would stay with the client that took it, and the pending writes of
/// the other one would not be sent until it is primary again: clients that
/// share a cache do not share their pending writes yet (see the multi-client
/// row in docs/ARCHITECTURE.md).
Future<void> _checkSharedCacheCase(
  int seed, {
  required lite.Firestore backend,
  required Firestore writer,
  required _Stats stats,
}) async {
  final Gen gen = Gen(seed);
  final List<Object?> pool = queryValuePool(
    gen,
    (String id) => writer.doc('property_refs/$id'),
  );
  final Map<String, Map<String, Object?>> data = <String, Map<String, Object?>>{
    for (int i = 0; i < documentCount; i++) _id(i): queryDocument(gen, pool),
  };
  final String path = 'property_query_shared_${autoId()}';
  final String dbName = 'property_query_shared_${autoId()}.db';
  DatabaseMock.deleteDatabaseFiles(dbName);
  Future<Firestore> open() => IntegrationTestUtil.testFirestoreInstance(
    IntegrationTestUtil.provider.projectId,
    InternalLogLevel.w,
    IntegrationTestUtil.newTestSettings(),
    IntegrationTestUtil.currentDatabasePath,
    fixedDbName: dbName,
  );

  String phase = 'opening the clients';
  final List<(String, Firestore)> opened = <(String, Firestore)>[];
  String leaseState() => <String>[
    for (final (String name, Firestore f) in opened) _describeLease(name, f),
  ].join('; ');
  Future<T> step<T>(String what, Future<T> future) {
    if (traceProperties) {
      print('TRACE seed $seed, $phase: $what');
    }
    String failed(String reason) =>
        'seed $seed (rerun with PROPERTY_SEED=$seed), $phase: $what $reason '
        '(${leaseState()})';
    // A timeout inside [future] (a listener that never gets in sync) is
    // reported with the step too.
    return future
        .timeout(
          leaseTimeout * 2,
          onTimeout: () => throw TimeoutException(failed('did not complete')),
        )
        .catchError(
          (Object error) => throw TimeoutException(failed('timed out: $error')),
          test: (Object error) =>
              error is TimeoutException &&
              !(error.message ?? '').startsWith('seed '),
        );
  }

  // The client that opens the cache last takes the primary lease.
  final Firestore b = await step('open B', open());
  opened.add(('B', b));
  final Firestore a = await step('open A', open());
  opened.add(('A', a));
  final List<StreamSubscription<Object?>> subscriptions =
      <StreamSubscription<Object?>>[];
  try {
    await step('B disables its network', b.disableNetwork());
    await step('B learns that A holds the lease', _waitForLease(a, b));
    await step('write the documents', writeAll(writer.collection(path), data));
    final CollectionReference<Map<String, Object?>> collectionA = a.collection(
      path,
    );
    final CollectionReference<Map<String, Object?>> collectionB = b.collection(
      path,
    );
    final List<Object?> poolA = <Object?>[
      for (final Object? v in pool) _rebind(v, a),
    ];
    final List<Object?> poolB = <Object?>[
      for (final Object? v in pool) _rebind(v, b),
    ];
    // The same query (same seed) on A and on B.
    (GeneratedQuery, GeneratedQuery)? query(int q) {
      Gen queryGen() => Gen((seed + (q + 1) * 104729) & 0x7fffffff);
      final GeneratedQuery? forA = generateQuery(
        queryGen(),
        collectionA,
        poolA,
      );
      final GeneratedQuery? forB = generateQuery(
        queryGen(),
        collectionB,
        poolB,
      );
      if (forA == null || forB == null) {
        stats.rejectedBySdk++;
        return null;
      }
      return (forA, forB);
    }

    String context(int q, GeneratedQuery generated) =>
        '  seed: $seed (rerun with PROPERTY_SEED=$seed), shared SQLite cache, '
        '$phase, query #$q:\n    $generated';

    // A keeps every document of the collection in the cache: the primary
    // client writes what it hears from the backend to the shared file.
    phase = 'round 1, A primary';
    final (
      _,
      StreamSubscription<QuerySnapshot<Map<String, Object?>>> all,
    ) = await step(
      'A listens to the collection',
      _listenUntilSynced(collectionA),
    );
    subscriptions.add(all);

    for (int round = 1; round <= leaseRounds; round++) {
      final int first = (round - 1) * 2 * sharedQueriesPerPhase;

      // ------------------------------------------------------ A primary
      phase = 'round $round, A primary';
      if (round == 1) {
        // The isolate of both clients stalls for longer than the lease is
        // valid, as on a loaded machine: B may take the lease on its next
        // refresh. The election must give it back to A, which has network.
        sleep(const Duration(milliseconds: 5500));
        bool taken = false;
        final Timer watch = Timer.periodic(
          const Duration(milliseconds: 20),
          (_) => taken = taken || b.client.isPrimaryClient,
        );
        await Future<void>.delayed(SQLiteClientMetadata.refreshInterval * 2);
        watch.cancel();
        if (taken) {
          stats.leaseTakenAfterStall++;
        }
        await step(
          'A holds the lease again after a stall',
          _waitForLease(a, b),
        );
      }
      final List<_Write> online = _generateWrites(gen, pool);
      await step(
        'A commits its writes',
        Future.wait(<Future<void>>[
          for (final _Write write in online) _apply(write, collectionA, stats),
        ]),
      );
      Map<String, Object?> serverData = await step(
        'read the collection from the backend',
        _backendData(backend, path),
      );
      for (int q = first; q < first + sharedQueriesPerPhase; q++) {
        final (GeneratedQuery, GeneratedQuery)? generated = query(q);
        if (generated == null) {
          continue;
        }
        final (GeneratedQuery forA, GeneratedQuery forB) = generated;
        final List<String>? expected = await step(
          'run query #$q on the backend',
          _backendIds(backend, forA.query, stats),
        );
        if (expected == null) {
          continue;
        }
        final (
          List<String> listenedA,
          StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription,
        ) = await step(
          'A listens to query #$q: $forA',
          _listenUntilSynced(forA.query),
        );
        final List<String> cachedA = _ids(
          await step(
            'A reads query #$q from the cache',
            forA.query.get(Source.cache),
          ),
        );
        await step('A stops listening to query #$q', subscription.cancel());
        final List<String> listenedB = await step(
          'B listens to query #$q: $forB',
          _firstSnapshot(forB.query),
        );
        final List<String> cachedB = _ids(
          await step(
            'B reads query #$q from the cache',
            forB.query.get(Source.cache),
          ),
        );
        _compare(
          stats: stats,
          context: '${context(q, forA)}\n  writes of A: ${online.join(', ')}',
          expected: expected,
          results: <String, List<String>>{
            'A listener in sync': listenedA,
            'A cache while listening': cachedA,
            'B listener (secondary, from the cache)': listenedB,
            'B cache (secondary)': cachedB,
          },
          data: serverData,
        );
      }

      // ---------------------------------- B primary, A offline with writes
      phase = 'round $round, B primary';
      await step('A disables its network', a.disableNetwork());
      await step('B enables its network', b.enableNetwork());
      await step('B takes the lease', _waitForLease(b, a));
      final List<_Write> pending = _generateWrites(gen, pool);
      final List<Future<void>> committed = <Future<void>>[
        for (final _Write write in pending) _apply(write, collectionA, stats),
      ];
      final Map<int, (GeneratedQuery, Map<String, List<String>>)> answers =
          <int, (GeneratedQuery, Map<String, List<String>>)>{};
      for (
        int q = first + sharedQueriesPerPhase;
        q < first + 2 * sharedQueriesPerPhase;
        q++
      ) {
        final (GeneratedQuery, GeneratedQuery)? generated = query(q);
        if (generated == null) {
          continue;
        }
        final (GeneratedQuery forA, GeneratedQuery forB) = generated;
        // Only queries that the backend accepts (it is asked again after the
        // commit).
        if (await step(
              'run query #$q on the backend',
              _backendIds(backend, forA.query, stats),
            ) ==
            null) {
          continue;
        }
        // A pending write of A can move a document into the window of a
        // limit query that the backend does not return yet: the document is
        // in limbo until the write is committed, and B can not send the
        // writes of A. Its listener stays `isFromCache` until A is primary
        // again (as a single client's does while offline with such a write).
        // Every other query must get in sync.
        final bool limited =
            forB.query.query.hasLimitToFirst || forB.query.query.hasLimitToLast;
        final (
          List<String> listenedB,
          bool inSync,
          StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription,
        ) = await step(
          'B listens to query #$q: $forB',
          _listenUntilSyncedOrSettled(
            forB.query,
            settle: limited ? const Duration(seconds: 3) : null,
          ),
        );
        if (!inSync) {
          stats.limitListenersInLimbo++;
        }
        final List<String> cachedB = _ids(
          await step(
            'B reads query #$q from the cache',
            forB.query.get(Source.cache),
          ),
        );
        await step('B stops listening to query #$q', subscription.cancel());
        final List<String> cachedA = _ids(
          await step(
            'A reads query #$q from the cache',
            forA.query.get(Source.cache),
          ),
        );
        answers[q] = (
          forA,
          <String, List<String>>{
            'B listener (primary), with the writes of A': listenedB,
            'B cache while listening': cachedB,
            'A cache (secondary, offline, its own writes pending)': cachedA,
          },
        );
      }

      // ------------------------------------------ the lease goes back to A
      phase = 'round $round, the lease goes back to A';
      await step('A enables its network', a.enableNetwork());
      await step('B disables its network', b.disableNetwork());
      await step('A takes the lease', _waitForLease(a, b));
      await step('A commits its pending writes', Future.wait(committed));
      serverData = await step(
        'read the collection from the backend',
        _backendData(backend, path),
      );
      phase = 'round $round, B primary, compared after the commit';
      for (final MapEntry<int, (GeneratedQuery, Map<String, List<String>>)>
          entry
          in answers.entries) {
        final (GeneratedQuery generated, Map<String, List<String>> results) =
            entry.value;
        final List<String>? expected = await step(
          'run query #${entry.key} on the backend',
          _backendIds(backend, generated.query, stats),
        );
        if (expected == null) {
          continue;
        }
        _compare(
          stats: stats,
          context:
              '${context(entry.key, generated)}\n'
              '  pending writes of A: ${pending.join(', ')}',
          expected: expected,
          results: results,
          data: serverData,
        );
      }
    }
  } finally {
    for (final StreamSubscription<Object?> subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final Firestore firestore in <Firestore>[a, b]) {
      IntegrationTestUtil.firestoreStatus.remove(firestore);
      IntegrationTestUtil.credentialsProviders.remove(firestore);
      await firestore.shutdown();
    }
    DatabaseMock.deleteDatabaseFiles(dbName);
  }
}
