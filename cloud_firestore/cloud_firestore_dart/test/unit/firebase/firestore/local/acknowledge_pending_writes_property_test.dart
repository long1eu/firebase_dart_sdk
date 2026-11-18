// After every acknowledgement, rejection, write and remote event, the document the local store returns must be
// the remote document with every remaining batch of the queue applied in order. LocalDocumentsView has a shortcut
// for acknowledgements of a document with many pending patches (a summary of the remaining batches instead of a
// replay); this test replays the queue itself and compares, over random sequences that take the shortcut and
// sequences that cannot.

import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// Which kinds of writes a run draws from.
enum _Mix {
  /// Only what the shortcut accepts: plain fields, server timestamps, increments.
  shortcut,

  /// Also array transforms, field deletes, sets, deletes, nested paths and batches of two documents.
  everything,
}

void main() {
  final UserDataConverter converter = UserDataConverter(
    DatabaseId.forProject('project'),
  );
  final List<DocumentKey> keys = <DocumentKey>[key('coll/a'), key('coll/b')];

  Mutation update(DocumentKey documentKey, Map<String, Object?> data) =>
      converter
          .parseUpdateData(data)
          .toMutation(documentKey, Precondition(exists: true));

  Mutation randomMutation(Random random, _Mix mix, DocumentKey documentKey) {
    final int kinds = mix == _Mix.shortcut ? 4 : 10;
    final Map<String, Object?> data = <String, Object?>{};
    final int fields = 1 + random.nextInt(3);
    for (int i = 0; i < fields; i++) {
      final String name = 'f${random.nextInt(4)}';
      switch (random.nextInt(kinds)) {
        case 0:
          data[name] = random.nextInt(100);
        case 1:
          data['time'] = FieldValue.serverTimestamp();
        case 2:
          data['count'] = FieldValue.increment(1 + random.nextInt(5));
        case 3:
          data[name] = 'text${random.nextInt(100)}';
        case 4:
          data['tags'] = FieldValue.arrayUnion(<Object?>[random.nextInt(5)]);
        case 5:
          data['tags'] = FieldValue.arrayRemove(<Object?>[random.nextInt(5)]);
        case 6:
          data[name] = FieldValue.delete();
        case 7:
          data['nested.${random.nextInt(2)}'] = random.nextInt(100);
        case 8:
          data['nested'] = <String, Object?>{'x': random.nextInt(100)};
        case 9:
          data['nested.time'] = FieldValue.serverTimestamp();
      }
    }
    if (mix == _Mix.everything) {
      final int other = random.nextInt(20);
      if (other == 0) {
        return setMutation(documentKey.path.canonicalString, <String, Object?>{
          'f0': random.nextInt(100),
        });
      }
      if (other == 1) {
        return deleteMutation(documentKey.path.canonicalString);
      }
    }
    return update(documentKey, data);
  }

  /// Returns the number of overlays the shortcut saved.
  Future<int> run(Persistence persistence, int seed, _Mix mix) async {
    final Random random = Random(seed);
    final LocalStore localStore = LocalStore(persistence, User.unauthenticated);
    await localStore.start();
    final int targetId = (await localStore.allocateTarget(
      query('coll').toTarget(),
    )).targetId;
    int remoteVersion = 10;

    Future<void> check(String step) async {
      for (final DocumentKey documentKey in keys) {
        final MaybeDocument? expected = await persistence
            .runTransactionAndReturn('replay the queue', () async {
              MaybeDocument? document = await persistence.remoteDocumentCache
                  .get(documentKey);
              final List<MutationBatch> batches = await persistence
                  .getMutationQueue(User.unauthenticated)
                  .getAllMutationBatchesAffectingDocumentKey(documentKey);
              for (final MutationBatch batch in batches) {
                document = batch.applyToLocalView(documentKey, document);
              }
              return document;
            });
        final MaybeDocument? actual = await localStore.readDocument(
          documentKey,
        );
        final String reason = 'seed $seed, $step, $documentKey';
        expect(actual is Document, expected is Document, reason: reason);
        if (actual is Document && expected is Document) {
          expect(actual.data, expected.data, reason: reason);
          expect(
            actual.hasLocalMutations,
            expected.hasLocalMutations,
            reason: reason,
          );
        }
      }
    }

    Future<void> remote(DocumentKey documentKey) async {
      remoteVersion += 10;
      await localStore.applyRemoteEvent(
        updateRemoteEvent(
          doc(documentKey, remoteVersion, <String, Object?>{
            'f0': random.nextInt(100),
            'count': random.nextInt(100),
            if (random.nextBool()) 'tags': <int>[1, 2],
          }),
          <int>[targetId],
          <int>[],
        ),
      );
    }

    for (final DocumentKey documentKey in keys) {
      await remote(documentKey);
    }
    await check('start');

    int pending = 0;
    for (int step = 0; step < 150; step++) {
      // Mostly long queues that then drain, as after a long time offline.
      final int action = random.nextInt(pending < 3 ? 4 : 20);
      if (action < 4 &&
          pending < 40 &&
          (pending > 0 || random.nextInt(3) > 0)) {
        final DocumentKey documentKey = keys[random.nextInt(2)];
        final List<Mutation> mutations = <Mutation>[
          randomMutation(random, mix, documentKey),
          if (mix == _Mix.everything && random.nextInt(10) == 0)
            randomMutation(random, mix, keys[random.nextInt(2)]),
        ];
        // Two mutations of one batch may be on the same document; the local store accepts that.
        await localStore.writeLocally(mutations);
        pending++;
        await check('step $step write');
      } else if (action < 4 && pending == 0 && mix == _Mix.everything) {
        // Only with an empty queue: a remote event does not recalculate the overlays of a document that keeps
        // existing (as in the other SDKs), so with pending transforms the stored overlay and a replay differ
        // until the next acknowledgement, with or without the shortcut.
        await remote(keys[random.nextInt(2)]);
        await check('step $step remote event');
      } else if (pending > 0) {
        final MutationBatch batch = (await localStore.getNextMutationBatch(
          -1,
        ))!;
        if (action == 5 && mix == _Mix.everything) {
          await localStore.rejectBatch(batch.batchId);
          await check('step $step reject');
        } else {
          remoteVersion += 10;
          final List<MutationResult> results = <MutationResult>[
            for (final Mutation mutation in batch.mutations)
              MutationResult(version(remoteVersion), <model.FieldValue>[
                if (mutation is PatchMutation)
                  for (final dynamic transform in mutation.fieldTransforms)
                    // What the backend answered for the transform: any value will do, the client stores it.
                    transform.fieldPath.canonicalString.contains('time')
                        ? wrap(DateTime.utc(2026, 1, 1, 0, 0, remoteVersion))
                        : transform.fieldPath.canonicalString == 'tags'
                        ? wrap(<int>[random.nextInt(5)])
                        : wrap(1000 + random.nextInt(100)),
              ]),
          ];
          await localStore.acknowledgeBatch(
            MutationBatchResult.create(
              batch,
              version(remoteVersion),
              results,
              Uint8List(0),
            ),
          );
          await check('step $step acknowledge');
        }
        pending--;
      }
    }
    return localStore.localDocumentsForTesting.overlaysSavedFromSummary;
  }

  for (final _Mix mix in _Mix.values) {
    for (final String cache in <String>['memory', 'sqlite']) {
      test(
        '${mix.name} writes, $cache cache',
        () async {
          int fromSummary = 0;
          for (int seed = 0; seed < (cache == 'memory' ? 60 : 15); seed++) {
            final Persistence persistence = cache == 'memory'
                ? await createLRUMemoryPersistence()
                : await createSQLitePersistence();
            try {
              fromSummary += await run(persistence, seed, mix);
            } finally {
              await persistence.shutdown();
            }
          }
          // The run must have taken the shortcut, or it proves nothing about it.
          expect(fromSummary, greaterThan(mix == _Mix.shortcut ? 50 : 0));
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }
  }
}
