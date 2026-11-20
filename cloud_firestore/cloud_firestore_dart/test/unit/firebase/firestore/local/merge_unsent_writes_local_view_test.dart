// `mergeUnsentWrites` and what the app sees offline: two local stores on the same kind of cache, one with the setting
// and one without, start from the same cached documents and take the same random sequence of single writes (none is
// handed to the network). After every write each document, its pending-writes flag and the results of a few queries
// (one ordered by a field the writes merge into, one filtered on a nested field) must be the same in both.
//
// The one documented difference is the estimate of a pending server timestamp (the time of the newer write after a
// merge), so a pending server timestamp compares by the value the app sees under it with
// ServerTimestampBehavior.previous, not by its time; no server timestamp is written to the ordered field, where the
// estimate decides the order.
//
// Runs on the memory cache, the SQLite cache and the key-value cache (a MemoryLogStore). PROPERTY_SCALE multiplies
// the number of seeds, PROPERTY_SEED moves them.

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/merge_writes_gen.dart';
import '../../../../util/property.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// [value] as plain values; a pending server timestamp as `time`, and with [previous] also the value the app sees
/// under it with ServerTimestampBehavior.previous.
Object? plainLocal(FieldValue value, {required bool previous}) =>
    switch (value) {
      final ObjectValue object => <String, Object?>{
        for (final MapEntry<String, FieldValue> entry in object.internalValue)
          entry.key: plainLocal(entry.value, previous: previous),
      },
      final ArrayValue array => <Object?>[
        for (final FieldValue element in array.internalValue)
          plainLocal(element, previous: previous),
      ],
      final ServerTimestampValue timestamp =>
        !previous
            ? 'time'
            : <String, Object?>{
                'time, previous': switch (timestamp.previousFieldValue) {
                  final FieldValue value => plainLocal(value, previous: true),
                  null => null,
                },
              },
      _ => '${value.runtimeType}(${value.value})',
    };

Object? describeLocal(MaybeDocument? document, {required bool previous}) =>
    switch (document) {
      final Document d => <Object?>[
        plainLocal(d.data, previous: previous),
        d.hasLocalMutations,
      ],
      null => 'unknown',
      _ => '${document.runtimeType}',
    };

void main() {
  final List<DocumentKey> keys = <DocumentKey>[
    key('coll/d0'),
    key('coll/d1'),
    key('coll/d2'),
  ];
  final List<Query> queries = <Query>[
    query('coll'),
    query('coll').orderBy(orderBy('a')),
    query('coll').orderBy(orderBy('a', 'desc')).limitToFirst(2),
    query('coll').filter(filter('n.x', '>=', 0)),
  ];

  Future<LocalStore> open(
    Persistence persistence,
    OfflineSequence sequence, {
    required bool merge,
  }) async {
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated)
      ..mergeUnsentWrites = merge;
    await localStore.start();
    final int targetId = (await localStore.allocateTarget(
      query('coll').toTarget(),
    )).targetId;
    for (int i = 0; i < keys.length; i++) {
      final Map<String, Object?>? data = sequence.start[i];
      final MaybeDocument? remote = data != null
          ? doc(keys[i], 10, data)
          // Unknown to the cache for the first document, known as deleted for the others.
          : i == 0
          ? null
          : deletedDoc(keys[i].path.canonicalString, 10);
      if (remote != null) {
        await localStore.applyRemoteEvent(
          updateRemoteEvent(remote, <int>[targetId], <int>[]),
        );
      }
    }
    return localStore;
  }

  Future<List<Object?>> view(
    LocalStore localStore, {
    bool previous = true,
  }) async => <Object?>[
    for (final DocumentKey documentKey in keys)
      describeLocal(
        await localStore.readDocument(documentKey),
        previous: previous,
      ),
    for (final Query q in queries)
      if ((await localStore.executeQuery(q, false)).documents
          case final ImmutableSortedMap<DocumentKey, Document> found)
        () {
          final List<Document> documents = <Document>[
            for (final MapEntry<DocumentKey, Document> e in found) e.value,
          ]..sort(q.comparator);
          final Iterable<Document> limited = q.hasLimit
              ? documents.take(q.getLimit())
              : documents;
          return <Object?>[
            for (final Document d in limited)
              '${d.key.path.canonicalString} '
                  '${describeLocal(d, previous: previous)}',
          ];
        }(),
  ];

  for (final (String cache, int count, Future<Persistence> Function() create)
      in <(String, int, Future<Persistence> Function())>[
        ('memory', 2000, createLRUMemoryPersistence),
        ('sqlite', 250, createSQLitePersistence),
        ('key-value', 400, createKeyValuePersistence),
      ]) {
    test(
      'the local view with the setting equals the local view without, $cache cache',
      () async {
        int merges = 0;
        int writes = 0;
        await forAllAsync<OfflineSequence>(
          'local view with and without mergeUnsentWrites, $cache',
          count: cases(count),
          generate: OfflineSequence.generate,
          show: (OfflineSequence s) => '$s',
          check: (OfflineSequence sequence) async {
            final Persistence separate = await create();
            final Persistence merged = await create();
            try {
              final LocalStore off = await open(
                separate,
                sequence,
                merge: false,
              );
              final LocalStore on = await open(merged, sequence, merge: true);
              expect(await view(on), await view(off), reason: 'start');
              for (int i = 0; i < sequence.writes.length; i++) {
                final OfflineWrite write = sequence.writes[i];
                final Mutation mutation = write.toMutation(
                  keys[write.document],
                );
                await off.writeLocally(<Mutation>[mutation], mayMerge: true);
                final LocalWriteResult result = await on.writeLocally(
                  <Mutation>[mutation],
                  mayMerge: true,
                );
                merges += result.mergedBatchIds.length;
                writes++;
                expect(
                  await view(on),
                  await view(off),
                  reason: 'after write $i ($write)',
                );
              }
            } finally {
              await separate.shutdown();
              await merged.shutdown();
            }
          },
        );
        print('$cache: $writes writes, $merges merged');
        expect(merges, greaterThan(writes ~/ 4));
      },
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}
