// `mergeUnsentWrites` against the emulator, as a property over random sequences of single writes to a few documents
// (test/util/merge_writes_gen.dart: set, set with merge and mergeFields, update with nested paths and field deletes,
// delete, and every transform). Each sequence is made offline twice, by one client with the setting and one without,
// each in a collection of its own that starts with the same documents:
//
//  * after every write, what each client shows from its cache is the same: each document (data with
//    ServerTimestampBehavior.none and .previous, hasPendingWrites) and three queries (ordered by a field the writes
//    merge into, ordered and limited, filtered on a nested field);
//  * the client with the setting queues the writes as the merge rules say (its pending write count);
//  * once both go online, the backend holds the same documents: the same values, a server timestamp in the same
//    fields, and never two server timestamps of one document in the opposite order (their times differ: a merged
//    write is one commit);
//  * the future of every write has the same outcome, except the documented one: a write replaced by a `set` or a
//    `delete` is not checked (an `update` of a missing document followed by a `set` succeeds);
//  * the documents of the client without the setting are those of the model backend of
//    test/unit/firebase/firestore/local/merge_unsent_writes_model_test.dart, which runs far more sequences.
//
// On the SQLite cache (PersistentCacheSettings), the memory cache and the key-value cache. PROPERTY_SCALE multiplies
// the number of seeds, PROPERTY_SEED moves them. Against a private emulator:
//
//   tool/start_private_emulator.sh 8405
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8405 dart test test/integration/firebase/firestore/merge_unsent_writes_sequences_test.dart

import 'dart:async';

import 'package:cloud_firestore_dart/cache_store.dart';
import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:test/test.dart';

import '../../../../example/cache_store/memory_log/memory_log_store.dart';
import '../../../util/integration_test_util.dart';
import '../../../util/merge_writes_gen.dart';
import '../../../util/merge_writes_model.dart';
import '../../../util/property.dart';
import '../../../util/test_util.dart' show doc, key, wrapMap;

/// What a client shows offline, for comparing the two clients.
Future<List<Object?>> localView(
  CollectionReference<Map<String, Object?>> c,
) async {
  Object? describe(DocumentSnapshot<Map<String, Object?>> s) => <Object?>[
    s.id,
    s.exists,
    s.data(),
    s.data(serverTimestamps: ServerTimestampBehavior.previous),
    s.metadata.hasPendingWrites,
  ];
  Future<Object?> query(Query<Map<String, Object?>> q) async => <Object?>[
    for (final DocumentSnapshot<Map<String, Object?>> s in (await q.get(
      const GetOptions(source: Source.cache),
    )).docs)
      describe(s),
  ];
  return <Object?>[
    for (int d = 0; d < 3; d++)
      await c
          .doc('d$d')
          .get(const GetOptions(source: Source.cache))
          .then<Object?>(describe, onError: (Object e) => 'not in the cache'),
    await query(c.orderBy('a')),
    await query(c.orderBy('a', descending: true).limit(2)),
    await query(c.where('n.x', isGreaterThanOrEqualTo: 0)),
  ];
}

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/merge_sequences';

  tearDown(() => IntegrationTestUtil.tearDown());

  final List<DocumentKey> keys = <DocumentKey>[
    key('coll/d0'),
    key('coll/d1'),
    key('coll/d2'),
  ];

  for (final (
        String cache,
        int count,
        LocalCacheSettings Function(bool) cacheSettings,
      )
      in <(String, int, LocalCacheSettings Function(bool))>[
        (
          'SQLite',
          150,
          (bool merge) => PersistentCacheSettings(mergeUnsentWrites: merge),
        ),
        (
          'memory',
          150,
          (bool merge) => MemoryCacheSettings(mergeUnsentWrites: merge),
        ),
        (
          'key-value',
          100,
          (bool merge) => keyValueCacheSettings(
            store: MemoryLogStore(),
            mergeUnsentWrites: merge,
          ),
        ),
      ]) {
    test(
      'random offline sequences end the same with and without the setting, $cache cache',
      () async {
        Future<FirebaseFirestore> client(bool merge) =>
            IntegrationTestUtil.testFirestore(
              IntegrationTestUtil.newTestSettings().copyWith(
                cacheSettings: cacheSettings(merge),
              ),
              'integration/merge_sequences_${cache}_$merge',
            );
        final FirebaseFirestore off = await client(false);
        final FirebaseFirestore on = await client(true);
        int writes = 0;
        int merged = 0;
        int changedOutcomes = 0;

        await forAllAsync<OfflineSequence>(
          'mergeUnsentWrites against the emulator, $cache',
          count: cases(count),
          generate: OfflineSequence.generate,
          show: (OfflineSequence s) => '$s',
          check: (OfflineSequence sequence) async {
            final String name =
                'merge_seq_${DateTime.now().microsecondsSinceEpoch}';
            final CollectionReference<Map<String, Object?>> offCollection = off
                .collection('${name}_off');
            final CollectionReference<Map<String, Object?>> onCollection = on
                .collection('${name}_on');
            for (int d = 0; d < 3; d++) {
              if (sequence.start[d] case final Map<String, Object?> data) {
                await offCollection.doc('d$d').set(data);
                await onCollection.doc('d$d').set(data);
              }
            }

            await off.disableNetwork();
            await on.disableNetwork();
            final List<Future<String>> offOutcomes = <Future<String>>[];
            final List<Future<String>> onOutcomes = <Future<String>>[];
            Future<String> outcome(Future<void> write) => write.then(
              (_) => 'ok',
              onError: (Object e) => e is FirestoreException ? e.code : '$e',
            );
            for (int i = 0; i < sequence.writes.length; i++) {
              final OfflineWrite write = sequence.writes[i];
              offOutcomes.add(
                outcome(write.applyTo(offCollection.doc('d${write.document}'))),
              );
              onOutcomes.add(
                outcome(write.applyTo(onCollection.doc('d${write.document}'))),
              );
              expect(
                await localView(onCollection),
                await localView(offCollection),
                reason: 'offline, after write $i ($write)',
              );
            }

            // The queue the client with the setting built.
            final List<QueuedWrite> queue = mergedQueue(<Mutation>[
              for (final OfflineWrite write in sequence.writes)
                write.toMutation(keys[write.document]),
            ]);
            expect(await on.getPendingWriteCount(), queue.length);
            expect(await off.getPendingWriteCount(), sequence.writes.length);
            writes += sequence.writes.length;
            merged += sequence.writes.length - queue.length;

            await off.enableNetwork();
            await on.enableNetwork();
            await off.waitForPendingWrites();
            await on.waitForPendingWrites();
            final List<String> separate = await Future.wait(offOutcomes);
            final List<String> together = await Future.wait(onOutcomes);
            final Set<int> unchecked = <int>{
              for (final QueuedWrite w in queue) ...w.unchecked,
            };
            for (int i = 0; i < separate.length; i++) {
              if (together[i] == separate[i]) {
                continue;
              }
              expect(
                unchecked,
                contains(i),
                reason:
                    'write $i: $separate with separate writes, $together merged',
              );
              expect(separate[i], 'not-found');
              expect(together[i], 'ok');
              changedOutcomes++;
            }

            // The model backend, for the documents without the setting.
            final List<MaybeDocument?> model = <MaybeDocument?>[
              for (int d = 0; d < 3; d++)
                if (sequence.start[d] case final Map<String, Object?> data)
                  doc(keys[d], 1, data)
                else
                  null,
            ];
            for (int i = 0; i < sequence.writes.length; i++) {
              final int d = sequence.writes[i].document;
              model[d] = commitOnModelBackend(
                sequence.writes[i].toMutation(keys[d]),
                model[d],
                Timestamp(1000 + i, 0),
              ).$1;
            }

            for (int d = 0; d < 3; d++) {
              (Object?, Map<String, Timestamp>) server(
                DocumentSnapshot<Map<String, Object?>> s,
              ) {
                final Map<String, Timestamp> times = <String, Timestamp>{};
                return (
                  s.exists
                      ? plainBackendValue(wrapMap(s.data()!), '', times)
                      : 'no document',
                  times,
                );
              }

              final (Object? one, Map<String, Timestamp> oneTimes) = server(
                await onCollection
                    .doc('d$d')
                    .get(const GetOptions(source: Source.server)),
              );
              final (Object? two, Map<String, Timestamp> twoTimes) = server(
                await offCollection
                    .doc('d$d')
                    .get(const GetOptions(source: Source.server)),
              );
              expect(one, two, reason: 'd$d on the backend');
              expect(oneTimes.keys.toSet(), twoTimes.keys.toSet());
              for (final String p in oneTimes.keys) {
                for (final String q in oneTimes.keys) {
                  if (oneTimes[p]!.compareTo(oneTimes[q]!) < 0) {
                    expect(
                      twoTimes[p]!.compareTo(twoTimes[q]!),
                      lessThan(0),
                      reason: 'd$d: $p before $q with the setting',
                    );
                  }
                }
              }
              expect(
                two,
                describeOnBackend(model[d]).$1,
                reason: 'd$d: the emulator and the model backend',
              );
            }
          },
        );
        print(
          '$cache: $writes writes, $merged merged away, '
          '$changedOutcomes outcomes changed as documented',
        );
        expect(merged, greaterThan(writes ~/ 4));
      },
      timeout: const Timeout(Duration(minutes: 30)),
    );
  }
}
