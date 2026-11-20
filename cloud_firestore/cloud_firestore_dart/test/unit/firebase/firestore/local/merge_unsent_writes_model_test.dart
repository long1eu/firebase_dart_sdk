// `mergeUnsentWrites` as a property, without a backend: a random sequence of single writes to a few documents, made
// offline, is queued once as without the setting (one write each) and once as the setting queues it (each write merged
// into the pending write of its document when mergeUnsentMutations allows it, the merged write taking the place of the
// newer one). A model of the backend then commits each queue in order, one commit time per write, and the two must
// end with the same documents: the same values, a server timestamp in the same fields (its time differs: the merged
// write is one commit), never two server timestamps of one document in the opposite order, and the same outcome for
// every write except the one the guide documents (a write replaced by a `set` or `delete` is not checked).
//
// The model of the backend is Mutation.applyToLocalView without a base document, with the commit time as the local
// write time: the fields of the write, then its transforms on the result, as the backend applies them; test/integration/firebase/firestore/
// merge_unsent_writes_sequences_test.dart runs the same kind of sequences against the emulator.
//
// PROPERTY_SCALE multiplies the number of seeds, PROPERTY_SEED moves them.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show Timestamp;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:test/test.dart';

import '../../../../util/merge_writes_gen.dart';
import '../../../../util/merge_writes_model.dart';
import '../../../../util/property.dart';
import '../../../../util/test_util.dart';

void main() {
  final List<DocumentKey> keys = <DocumentKey>[
    key('coll/d0'),
    key('coll/d1'),
    key('coll/d2'),
  ];

  int merges = 0;
  int writes = 0;
  int unchecked = 0;
  int changedOutcomes = 0;

  void check(OfflineSequence sequence) {
    final List<Mutation> mutations = <Mutation>[
      for (final OfflineWrite write in sequence.writes)
        write.toMutation(keys[write.document]),
    ];
    final List<MaybeDocument?> start = <MaybeDocument?>[
      for (int i = 0; i < keys.length; i++)
        if (sequence.start[i] case final Map<String, Object?> data)
          doc(keys[i], 1, data)
        else
          null,
    ];

    // Without the setting: one commit per write, in order.
    final List<MaybeDocument?> separate = List<MaybeDocument?>.of(start);
    final List<bool> separateOutcomes = <bool>[];
    for (int i = 0; i < mutations.length; i++) {
      final int d = sequence.writes[i].document;
      final (MaybeDocument? after, bool ok) = commitOnModelBackend(
        mutations[i],
        separate[d],
        Timestamp(1000 + i, 0),
      );
      separate[d] = after;
      separateOutcomes.add(ok);
    }

    // With the setting.
    final List<QueuedWrite> queue = mergedQueue(mutations);
    final List<MaybeDocument?> merged = List<MaybeDocument?>.of(start);
    final List<bool?> mergedOutcomes = List<bool?>.filled(
      mutations.length,
      null,
    );
    for (int i = 0; i < queue.length; i++) {
      final QueuedWrite write = queue[i];
      final int d = keys.indexOf(write.mutation.key);
      final (MaybeDocument? after, bool ok) = commitOnModelBackend(
        write.mutation,
        merged[d],
        Timestamp(1000 + i, 0),
      );
      merged[d] = after;
      for (final int origin in write.origins) {
        mergedOutcomes[origin] = ok;
      }
      // The outcome of the merged write is that of its newest write.
      expect(ok, separateOutcomes[write.origins.last], reason: 'write $i');
      for (final int origin in write.origins) {
        if (write.unchecked.contains(origin)) {
          unchecked++;
          if (ok != separateOutcomes[origin]) {
            changedOutcomes++;
            // Documented: only an update that failed, followed by a set or a delete, which succeed.
            expect(separateOutcomes[origin], isFalse);
            expect(mutations[origin].precondition.exists, isTrue);
          }
        } else {
          expect(
            ok,
            separateOutcomes[origin],
            reason: 'outcome of write $origin, merged into ${write.origins}',
          );
        }
      }
    }
    merges += mutations.length - queue.length;
    writes += mutations.length;

    for (int d = 0; d < keys.length; d++) {
      final (Object? one, Map<String, Timestamp> oneTimes) = describeOnBackend(
        merged[d],
      );
      final (Object? two, Map<String, Timestamp> twoTimes) = describeOnBackend(
        separate[d],
      );
      expect(one, two, reason: 'document d$d');
      expect(oneTimes.keys.toSet(), twoTimes.keys.toSet());
      // Never two server timestamps in the opposite order (the merged write gives several the same time).
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
    }
  }

  test('random offline sequences leave the backend as without the setting', () {
    forAll<OfflineSequence>(
      'merged queue equals separate writes on the model backend',
      count: cases(30000),
      generate: OfflineSequence.generate,
      check: check,
      show: (OfflineSequence s) => '$s',
    );
    print(
      '$writes writes, $merges merged away, $unchecked unchecked, $changedOutcomes changed outcomes',
    );
    // The generator must reach the merges: most chains of one document merge.
    expect(merges, greaterThan(writes ~/ 4));
    // The documented difference occurs, and is the only one.
    expect(unchecked, greaterThan(0));
    expect(changedOutcomes, greaterThan(0));
  });
}
