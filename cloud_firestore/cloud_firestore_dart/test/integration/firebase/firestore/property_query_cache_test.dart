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
// Operands null and NaN of `in`, `not-in`, the array filters, `<=` and `>=`
// are not generated: a Standard edition backend never matches them, the SDK
// does (see "Values, queries and API" in docs/ARCHITECTURE.md and
// property_query_test.dart, which covers that case).
//
// The default run (8 collections) takes 15 to 80 seconds on the emulator,
// depending on the load of the machine. PROPERTY_SCALE=<n> runs n times as
// many collections, PROPERTY_SEED=<seed> reruns a failing case and
// PROPERTY_TRACE=1 prints every step.

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/lite.dart' as lite;
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:test/test.dart';

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
  final List<String> failures = <String>[];

  static const int maxFailures = 8;

  @override
  String toString() =>
      'compared $compared query results; the SDK rejected $rejectedBySdk, '
      'the backend $rejectedByBackend queries; $writesApplied writes '
      'committed, $writesRejected rejected (update of a missing document)';
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

/// Listens to [query] until a snapshot is in sync with the backend. Returns
/// the ids of that snapshot and the subscription, which stays active.
Future<(List<String>, StreamSubscription<QuerySnapshot<Map<String, Object?>>>)>
_listenUntilSynced(Query<Map<String, Object?>> query) async {
  final Completer<List<String>> synced = Completer<List<String>>();
  final StreamSubscription<QuerySnapshot<Map<String, Object?>>> subscription =
      query
          .getSnapshots(MetadataChanges.include)
          .listen(
            (QuerySnapshot<Map<String, Object?>> snapshot) {
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
    return (await synced.future.timeout(syncTimeout), subscription);
  } catch (_) {
    await subscription.cancel();
    rethrow;
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
