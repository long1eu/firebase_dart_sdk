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
import 'package:cloud_firestore_dart/src/firebase/firestore/local/unsent_write_merge.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';

import '../../../../util/merge_writes_gen.dart';
import '../../../../util/property.dart';
import '../../../../util/test_util.dart';

/// A write of the queue: the mutation, the writes of the sequence that went into it (oldest first), and the ones whose
/// precondition the merge dropped (followed by a write that replaced them: a `set` or a `delete`).
final class QueuedWrite {
  QueuedWrite(this.mutation, this.origins, this.unchecked);

  final Mutation mutation;
  final List<int> origins;
  final Set<int> unchecked;
}

/// The queue the setting builds from [mutations], as LocalStore.writeLocally does with every write mergeable (none
/// handed to the network, one client).
List<QueuedWrite> mergedQueue(List<Mutation> mutations) {
  final List<QueuedWrite> queue = <QueuedWrite>[];
  for (int i = 0; i < mutations.length; i++) {
    final Mutation next = mutations[i];
    final int previous = queue.lastIndexWhere(
      (QueuedWrite w) => w.mutation.key == next.key,
    );
    final Mutation? merged = previous < 0
        ? null
        : mergeUnsentMutations(queue[previous].mutation, next);
    if (merged == null) {
      queue.add(QueuedWrite(next, <int>[i], <int>{}));
      continue;
    }
    final QueuedWrite replaced = queue.removeAt(previous);
    queue.add(
      QueuedWrite(
        merged,
        <int>[...replaced.origins, i],
        // Rule 1: the new write alone, whatever the pending one was.
        identical(merged, next)
            ? <int>{...replaced.origins}
            : <int>{...replaced.unchecked},
      ),
    );
  }
  return queue;
}

/// The model backend: [mutation] committed at [time] on [document]; null outcome when its precondition fails (the
/// write is rejected and the document stays as it was).
(MaybeDocument?, bool) commit(
  Mutation mutation,
  MaybeDocument? document,
  Timestamp time,
) {
  if (!mutation.precondition.isValidFor(document)) {
    return (document, false);
  }
  // Without a base document the transforms apply to the written fields, as on the backend. (With one, the local view
  // takes the value of a field that the write cleared from before the write, an upstream edge case of the client.)
  return (mutation.applyToLocalView(document, null, time), true);
}

/// The document as plain values, with every server timestamp written as `time` and its path and time added to
/// [times].
Object? plain(FieldValue value, String path, Map<String, Timestamp> times) =>
    switch (value) {
      final ObjectValue object => <String, Object?>{
        for (final MapEntry<String, FieldValue> entry in object.internalValue)
          entry.key: plain(
            entry.value,
            path.isEmpty ? entry.key : '$path.${entry.key}',
            times,
          ),
      },
      final ArrayValue array => <Object?>[
        for (final FieldValue element in array.internalValue)
          plain(element, '$path[]', times),
      ],
      final ServerTimestampValue timestamp => () {
        times[path] = timestamp.localWriteTime;
        return 'time';
      }(),
      _ => '${value.runtimeType}(${value.value})',
    };

(Object?, Map<String, Timestamp>) describe(MaybeDocument? document) {
  final Map<String, Timestamp> times = <String, Timestamp>{};
  return (
    document is Document ? plain(document.data, '', times) : 'no document',
    times,
  );
}

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
      final (MaybeDocument? after, bool ok) = commit(
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
      final (MaybeDocument? after, bool ok) = commit(
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
      final (Object? one, Map<String, Timestamp> oneTimes) = describe(
        merged[d],
      );
      final (Object? two, Map<String, Timestamp> twoTimes) = describe(
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
    print('$writes writes, $merges merged away, $unchecked unchecked, $changedOutcomes changed outcomes');
    // The generator must reach the merges: most chains of one document merge.
    expect(merges, greaterThan(writes ~/ 4));
    // The documented difference occurs, and is the only one.
    expect(unchecked, greaterThan(0));
    expect(changedOutcomes, greaterThan(0));
  });
}
