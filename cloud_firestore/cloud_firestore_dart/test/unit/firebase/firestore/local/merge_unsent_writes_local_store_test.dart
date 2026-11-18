// The local store with `mergeUnsentWrites`: over random sequences of writes, hand-outs to the write pipeline,
// acknowledgements and rejections, the documents it returns must be (1) the cached remote document with the batches
// of its queue applied, and (2) the same as with every write the app made that is still pending applied one by one.

import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_write_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final UserDataConverter converter = UserDataConverter(
    DatabaseId.forProject('project'),
  );
  final List<DocumentKey> keys = <DocumentKey>[key('coll/a'), key('coll/b')];

  Mutation randomMutation(Random random, DocumentKey documentKey) {
    final Map<String, Object?> data = <String, Object?>{};
    for (int i = 1 + random.nextInt(3); i > 0; i--) {
      switch (random.nextInt(12)) {
        case 0:
          data['count'] = FieldValue.increment(1 + random.nextInt(5));
        case 1:
          data['time'] = FieldValue.serverTimestamp();
        case 2:
          data['f${random.nextInt(3)}'] = FieldValue.delete();
        case 3:
          data['n'] = <String, Object?>{'x': random.nextInt(100)};
        case 4:
          data['tags'] = FieldValue.arrayUnion(<Object?>[random.nextInt(5)]);
        default:
          data['f${random.nextInt(3)}'] = random.nextInt(100);
      }
    }
    switch (random.nextInt(12)) {
      case 0:
        return deleteMutation(documentKey.path.canonicalString);
      case 1:
      case 2:
        data.removeWhere(
          (String _, Object? value) =>
              value is FieldValue && value == FieldValue.delete(),
        );
        return converter
            .parseSetData(data)
            .toMutation(documentKey, Precondition.none);
      case 3:
      case 4:
        return converter
            .parseMergeData(data, null)
            .toMutation(documentKey, Precondition.none);
      default:
        if (random.nextInt(4) == 0) {
          data['n.y'] = random.nextInt(100);
        }
        return converter
            .parseUpdateData(data)
            .toMutation(documentKey, Precondition(exists: true));
    }
  }

  /// The data without the fields that transforms write. A server timestamp shows the time of its batch, and an
  /// increment or array transform starts from the value recorded when it was written, which a plain replay of the
  /// writes does not know once a write under it was acknowledged or rejected. The runs with writes only compare
  /// these fields too, see [withTimes].
  String withoutTransforms(MaybeDocument? document) => document is Document
      ? document.data
            .toString()
            .replaceAll(RegExp(r',?time:\{[^}]*\}'), '')
            .replaceAll(RegExp(r',?tags:\[[^\]]*\]'), '')
            .replaceAll(RegExp(r',?count:[^,}]*'), '')
            .replaceAll('{,', '{')
      : 'no document';

  /// The whole data, with every pending server timestamp as one word: its estimate is the time of its batch.
  String withTimes(MaybeDocument? document) => document is Document
      ? document.data.toString().replaceAll(
          RegExp(r'\{__local_write_time__:.*?__type__:server_timestamp\}'),
          'time',
        )
      : 'no document';

  String withoutPreviousValue(String data) =>
      data.replaceAll(RegExp(r'__previous_value__:.*?,__type__'), '__type__');

  /// Returns the number of writes that were merged.
  ///
  /// With [onlyWrites] nothing is acknowledged or rejected, and the documents must equal a replay of all the writes
  /// in every field: what the app sees with merging is what it sees without.
  Future<int> run(
    Persistence persistence,
    int seed, {
    bool onlyWrites = false,
  }) async {
    final Random random = Random(seed);
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated)
      ..mergeUnsentWrites = true;
    await localStore.start();
    final int targetId = (await localStore.allocateTarget(
      query('coll').toTarget(),
    )).targetId;
    int remoteVersion = 10;
    int merges = 0;

    // The writes of the app that are still pending, by the batch that carries them now, in the order they were made.
    final Map<int, List<(int, List<Mutation>)>> written =
        <int, List<(int, List<Mutation>)>>{};
    int sequence = 0;
    int handedOut = -1;

    Future<void> check(String step) async {
      for (final DocumentKey documentKey in keys) {
        final String reason = 'seed $seed, $step, $documentKey';
        final (MaybeDocument?, MaybeDocument?) expected = await persistence
            .runTransactionAndReturn('replay', () async {
              final MaybeDocument? remote = await persistence
                  .remoteDocumentCache
                  .get(documentKey);
              MaybeDocument? fromQueue = remote;
              final List<MutationBatch> batches = await persistence
                  .getMutationQueue(User.unauthenticated)
                  .getAllMutationBatchesAffectingDocumentKey(documentKey);
              for (final MutationBatch batch in batches) {
                fromQueue = batch.applyToLocalView(documentKey, fromQueue);
              }
              MaybeDocument? fromWrites = remote;
              final List<(int, List<Mutation>)> all =
                  written.values
                      .expand((List<(int, List<Mutation>)> l) => l)
                      .toList()
                    ..sort(
                      ((int, List<Mutation>) a, (int, List<Mutation>) b) =>
                          a.$1.compareTo(b.$1),
                    );
              for (final (int, List<Mutation>) entry in all) {
                // As a batch does: the transforms of all its writes start from the document before the batch.
                final MaybeDocument? beforeBatch = fromWrites;
                for (final Mutation mutation in entry.$2) {
                  if (mutation.key == documentKey) {
                    fromWrites = mutation.applyToLocalView(
                      fromWrites,
                      beforeBatch,
                      Timestamp(1000, 0),
                    );
                  }
                }
              }
              return (fromQueue, fromWrites);
            });
        final MaybeDocument? actual = await localStore.readDocument(
          documentKey,
        );
        expect(actual is Document, expected.$1 is Document, reason: reason);
        if (actual is Document) {
          // Without the previous value inside a pending server timestamp: after a merge it is still the one of the
          // document with the replaced write, until the overlay is next recalculated from the queue.
          expect(
            withoutPreviousValue(actual.data.toString()),
            withoutPreviousValue((expected.$1! as Document).data.toString()),
            reason: reason,
          );
        }
        expect(
          withoutTransforms(actual),
          withoutTransforms(expected.$2),
          reason: reason,
        );
        if (onlyWrites) {
          expect(withTimes(actual), withTimes(expected.$2), reason: reason);
        }
      }
    }

    for (final DocumentKey documentKey in keys) {
      if (random.nextBool()) {
        await localStore.applyRemoteEvent(
          updateRemoteEvent(
            doc(documentKey, remoteVersion, <String, Object?>{
              'f0': 1,
              'count': 7,
              'tags': <int>[1],
            }),
            <int>[targetId],
            <int>[],
          ),
        );
      }
    }
    await check('start');

    for (int step = 0; step < 200; step++) {
      final int action = random.nextInt(onlyWrites ? 16 : 20);
      if (action < 14) {
        final DocumentKey documentKey = keys[random.nextInt(2)];
        final List<Mutation> mutations = <Mutation>[
          randomMutation(random, documentKey),
          if (random.nextInt(15) == 0)
            randomMutation(random, keys[random.nextInt(2)]),
        ];
        final LocalWriteResult result = await localStore.writeLocally(
          mutations,
          mayMerge: true,
        );
        final List<(int, List<Mutation>)> carried = <(int, List<Mutation>)>[];
        for (final int merged in result.mergedBatchIds) {
          // Never a batch that the write pipeline has.
          expect(merged, greaterThan(handedOut), reason: 'seed $seed');
          carried.addAll(written.remove(merged)!);
          merges++;
        }
        written[result.batchId] = carried..add((sequence++, mutations));
        await check('step $step write');
      } else if (action < 16) {
        final MutationBatch? next = await localStore.getNextMutationBatch(
          handedOut,
        );
        if (next != null) {
          handedOut = next.batchId;
        }
      } else {
        final MutationBatch? batch = await localStore.getNextMutationBatch(-1);
        if (batch == null) {
          continue;
        }
        handedOut = max(handedOut, batch.batchId);
        written.remove(batch.batchId);
        if (action == 16) {
          await localStore.rejectBatch(batch.batchId);
          await check('step $step reject');
          continue;
        }
        remoteVersion += 10;
        await localStore.acknowledgeBatch(
          MutationBatchResult.create(
            batch,
            version(remoteVersion),
            <MutationResult>[
              for (final Mutation mutation in batch.mutations)
                MutationResult(version(remoteVersion), <model.FieldValue>[
                  for (final dynamic transform in mutation.fieldTransforms)
                    transform.fieldPath.canonicalString == 'time'
                        ? wrap(DateTime.utc(2026, 1, 1, 0, 0, remoteVersion))
                        : transform.fieldPath.canonicalString == 'tags'
                        ? wrap(<int>[random.nextInt(5)])
                        : wrap(1000 + random.nextInt(100)),
                ]),
            ],
            Uint8List(0),
          ),
        );
        await check('step $step acknowledge');
      }
    }
    return merges;
  }

  for (final String cache in <String>['memory', 'sqlite']) {
    test(
      'random writes with merging, $cache cache',
      () async {
        int merges = 0;
        for (int seed = 0; seed < (cache == 'memory' ? 60 : 15); seed++) {
          final Persistence persistence = cache == 'memory'
              ? await createLRUMemoryPersistence()
              : await createSQLitePersistence();
          try {
            merges += await run(persistence, seed);
          } finally {
            await persistence.shutdown();
          }
        }
        expect(merges, greaterThan(200));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'random writes with merging and no acknowledgement, $cache cache',
      () async {
        int merges = 0;
        for (int seed = 0; seed < (cache == 'memory' ? 200 : 20); seed++) {
          final Persistence persistence = cache == 'memory'
              ? await createLRUMemoryPersistence()
              : await createSQLitePersistence();
          try {
            merges += await run(persistence, 1000 + seed, onlyWrites: true);
          } finally {
            await persistence.shutdown();
          }
        }
        expect(merges, greaterThan(1000));
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
