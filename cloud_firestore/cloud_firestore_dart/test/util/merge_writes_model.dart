// The queue that `mergeUnsentWrites` builds from a sequence of writes, and a model of the backend that commits it: for
// merge_unsent_writes_model_test.dart, and to check that model against the emulator in
// merge_unsent_writes_sequences_test.dart.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show Timestamp;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/unsent_write_merge.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';

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
(MaybeDocument?, bool) commitOnModelBackend(
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

/// [value] as plain values, with every server timestamp written as `time` and its path and time added to [times].
/// The sequences write no timestamp of their own, so every timestamp of the backend is one it set.
Object? plainBackendValue(
  FieldValue value,
  String path,
  Map<String, Timestamp> times,
) => switch (value) {
  final ObjectValue object => <String, Object?>{
    for (final MapEntry<String, FieldValue> entry in object.internalValue)
      entry.key: plainBackendValue(
        entry.value,
        path.isEmpty ? entry.key : '$path.${entry.key}',
        times,
      ),
  },
  final ArrayValue array => <Object?>[
    for (final FieldValue element in array.internalValue)
      plainBackendValue(element, '$path[]', times),
  ],
  // The model backend leaves the server timestamps it sets pending, at the commit time; the backend sets them.
  final ServerTimestampValue timestamp => () {
    times[path] = timestamp.localWriteTime;
    return 'time';
  }(),
  final TimestampValue timestamp => () {
    times[path] = timestamp.value;
    return 'time';
  }(),
  _ => '${value.runtimeType}(${value.value})',
};

/// The document as plain values (see [plainBackendValue]) and the times of its server timestamps by path.
(Object?, Map<String, Timestamp>) describeOnBackend(MaybeDocument? document) {
  final Map<String, Timestamp> times = <String, Timestamp>{};
  return (
    document is Document
        ? plainBackendValue(document.data, '', times)
        : 'no document',
    times,
  );
}
