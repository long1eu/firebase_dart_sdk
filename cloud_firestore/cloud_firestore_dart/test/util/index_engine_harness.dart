// End-to-end checks of the persistent cache indexes against a backend: the same queries are answered from the cache
// through an index and by the server, and must agree.

import 'dart:convert';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:test/test.dart';

// ignore_for_file: deprecated_member_use_from_same_package

typedef Docs = Map<String, Map<String, Object?>>;
typedef QueryBuilder =
    Query<Map<String, Object?>> Function(
      CollectionReference<Map<String, Object?>> collection,
    );

/// A query to check. [index] is the kind of index the engine must find for it once the indexes are configured
/// ([IndexType.none] for a query that is expected to be scanned).
class IndexedQuery {
  const IndexedQuery(this.name, this.build, {this.index = IndexType.full});

  final String name;
  final QueryBuilder build;
  final IndexType index;
}

/// An index definition in the format of the Firebase CLI: every entry of [indexes] is the list of fields of one
/// index, a field being `'name'` (ascending), `'name desc'` or `'name contains'`.
String indexConfiguration(String collectionGroup, List<List<String>> indexes) {
  return jsonEncode(<String, Object?>{
    'indexes': <Object?>[
      for (final List<String> fields in indexes)
        <String, Object?>{
          'collectionGroup': collectionGroup,
          'queryScope': 'COLLECTION',
          'fields': <Object?>[
            for (final String field in fields)
              if (field.endsWith(' contains'))
                <String, Object?>{
                  'fieldPath': field.split(' ').first,
                  'arrayConfig': 'CONTAINS',
                }
              else
                <String, Object?>{
                  'fieldPath': field.split(' ').first,
                  'order': field.endsWith(' desc') ? 'DESCENDING' : 'ASCENDING',
                },
          ],
        },
    ],
  });
}

List<String> _ids(QuerySnapshot<Object?> snapshot) =>
    snapshot.docs.map((QueryDocumentSnapshot<Object?> d) => d.id).toList();

/// Runs index backfills until there is nothing left to index. This is the hook for tests: the scheduled backfill
/// first runs 15 seconds after the client started.
Future<int> backfillAllIndexes(Firestore firestore) async {
  int total = 0;
  while (true) {
    final int processed = await firestore.client.backfillIndexes();
    if (processed == 0) {
      return total;
    }
    total += processed;
  }
}

Future<Map<String, List<String>>> _cacheResults(
  CollectionReference<Map<String, Object?>> collection,
  List<IndexedQuery> queries,
) async {
  final Map<String, List<String>> results = <String, List<String>>{};
  for (final IndexedQuery query in queries) {
    results[query.name] = _ids(await query.build(collection).get(Source.cache));
  }
  return results;
}

/// Writes [docs] to the backend, configures [indexes] for the collection, fills them and checks for every query that
/// the cache (through the index) and the server return the same documents in the same order.
///
/// Then the same again with pending writes ([pendingWrites] is called while the network is disabled): the cache
/// results must be the same before the backfill saw the writes, after it did, and after all indexes were deleted;
/// they must differ from the results without the writes for [affectedByPendingWrites]; and once the writes are
/// committed the server must agree with them.
Future<void> checkIndexedQueries({
  required Firestore firestore,
  required CollectionReference<Map<String, Object?>> collection,
  required Docs docs,
  required List<List<String>> indexes,
  required List<IndexedQuery> queries,
  required Future<void> Function(
    CollectionReference<Map<String, Object?>> collection,
  )
  pendingWrites,
  required List<String> affectedByPendingWrites,
}) async {
  final LocalStore localStore = firestore.client.localStore;
  for (final MapEntry<String, Map<String, Object?>> doc in docs.entries) {
    await collection.doc(doc.key).set(doc.value);
  }
  // Everything is in the cache as the backend has it.
  expect(_ids(await collection.get(Source.server)), hasLength(docs.length));

  await firestore.setIndexConfiguration(
    indexConfiguration(collection.id, indexes),
  );
  expect(localStore.getFieldIndexes(), hasLength(indexes.length));
  expect(await backfillAllIndexes(firestore), docs.length);

  // 1. Synced documents only.
  for (final IndexedQuery query in queries) {
    expect(
      localStore.indexManagerForCurrentUser.getIndexType(
        query.build(collection).query.toTarget(),
      ),
      query.index,
      reason: 'index type of "${query.name}"',
    );
  }
  final Map<String, List<String>> fromIndex = await _cacheResults(
    collection,
    queries,
  );
  for (final IndexedQuery query in queries) {
    final List<String> fromServer = _ids(
      await query.build(collection).get(Source.server),
    );
    expect(fromIndex[query.name], fromServer, reason: query.name);
  }
  // The server reads above changed nothing: the indexes are still complete.
  expect(await backfillAllIndexes(firestore), 0);

  // 2. With pending writes.
  await firestore.disableNetwork();
  await pendingWrites(collection);
  // The writes are in the local store once a cache read went through the queue behind them.
  await collection.get(Source.cache);

  final Map<String, List<String>> beforeBackfill = await _cacheResults(
    collection,
    queries,
  );
  for (final String name in affectedByPendingWrites) {
    expect(
      beforeBackfill[name],
      isNot(fromIndex[name]),
      reason: 'the pending writes change "$name"',
    );
  }

  expect(await backfillAllIndexes(firestore), greaterThan(0));
  final Map<String, List<String>> afterBackfill = await _cacheResults(
    collection,
    queries,
  );
  expect(afterBackfill, beforeBackfill);

  await firestore.persistentCacheIndexManager!.deleteAllIndexes();
  for (final IndexedQuery query in queries) {
    expect(
      localStore.indexManagerForCurrentUser.getIndexType(
        query.build(collection).query.toTarget(),
      ),
      IndexType.none,
    );
  }
  final Map<String, List<String>> withoutIndexes = await _cacheResults(
    collection,
    queries,
  );
  expect(withoutIndexes, beforeBackfill);

  await firestore.enableNetwork();
  await firestore.waitForPendingWrites();
  for (final IndexedQuery query in queries) {
    final List<String> fromServer = _ids(
      await query.build(collection).get(Source.server),
    );
    expect(beforeBackfill[query.name], fromServer, reason: query.name);
  }
}
