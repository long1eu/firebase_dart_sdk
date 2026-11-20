// mergeUnsentMutations must only merge two writes when one write leaves the backend with the same document as the two
// sent one after the other, whatever the document was before. This test takes every ordered pair of a pool of writes
// and every one of a pool of documents and compares.

import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/unsent_write_merge.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  final UserDataConverter converter = UserDataConverter(
    DatabaseId.forProject('project'),
  );
  final DocumentKey documentKey = key('coll/a');
  final Timestamp time = Timestamp(1000, 0);

  Mutation set(Map<String, Object?> data) =>
      converter.parseSetData(data).toMutation(documentKey, Precondition.none);
  Mutation setMerge(Map<String, Object?> data) => converter
      .parseMergeData(data, null)
      .toMutation(documentKey, Precondition.none);
  Mutation update(Map<String, Object?> data) => converter
      .parseUpdateData(data)
      .toMutation(documentKey, Precondition(exists: true));

  final Map<String, Mutation> writes = <String, Mutation>{
    'set a,b': set(<String, Object?>{'a': 1, 'b': 2}),
    'set nested': set(<String, Object?>{
      'n': <String, Object?>{'x': 1, 'y': 2},
    }),
    'set empty': set(<String, Object?>{}),
    'set a is a map': set(<String, Object?>{
      'a': <String, Object?>{'x': 9},
    }),
    'set with time': set(<String, Object?>{
      'a': 3,
      'time': FieldValue.serverTimestamp(),
    }),
    'set with increment': set(<String, Object?>{
      'a': 3,
      'count': FieldValue.increment(2),
    }),
    'set with arrayUnion': set(<String, Object?>{
      'tags': FieldValue.arrayUnion(<Object?>[7]),
    }),
    'merge a': setMerge(<String, Object?>{'a': 10}),
    'merge nested x': setMerge(<String, Object?>{
      'n': <String, Object?>{'x': 11},
    }),
    'merge b,c': setMerge(<String, Object?>{'b': 12, 'c': 13}),
    'merge deletes a': setMerge(<String, Object?>{'a': FieldValue.delete()}),
    'merge with time': setMerge(<String, Object?>{
      'time': FieldValue.serverTimestamp(),
    }),
    'merge with increment': setMerge(<String, Object?>{
      'count': FieldValue.increment(3),
    }),
    'update a': update(<String, Object?>{'a': 20}),
    'update b': update(<String, Object?>{'b': 21}),
    'update n': update(<String, Object?>{
      'n': <String, Object?>{'z': 22},
    }),
    'update n.x': update(<String, Object?>{'n.x': 23}),
    'update n.y, a': update(<String, Object?>{'n.y': 24, 'a': 25}),
    'update a.x': update(<String, Object?>{'a.x': 26}),
    'update deletes a': update(<String, Object?>{'a': FieldValue.delete()}),
    'update deletes n.x': update(<String, Object?>{'n.x': FieldValue.delete()}),
    'update deletes n': update(<String, Object?>{'n': FieldValue.delete()}),
    'update with time': update(<String, Object?>{
      'a': 27,
      'time': FieldValue.serverTimestamp(),
    }),
    'update with increment': update(<String, Object?>{
      'count': FieldValue.increment(4),
    }),
    'update with arrayRemove': update(<String, Object?>{
      'tags': FieldValue.arrayRemove(<Object?>[1]),
    }),
    'update n.x.deep': update(<String, Object?>{'n.x.deep': 28}),
    'update deletes a.x': update(<String, Object?>{'a.x': FieldValue.delete()}),
    'update deletes n.x.deep': update(<String, Object?>{
      'n.x.deep': FieldValue.delete(),
    }),
    'update n to an empty map': update(<String, Object?>{
      'n': <String, Object?>{},
    }),
    'update n to a number': update(<String, Object?>{'n': 29}),
    'merge deletes n.x': setMerge(<String, Object?>{
      'n': <String, Object?>{'x': FieldValue.delete()},
    }),
    'merge n.x.deep': setMerge(<String, Object?>{
      'n': <String, Object?>{
        'x': <String, Object?>{'deep': 30},
      },
    }),
    'merge an empty map': setMerge(<String, Object?>{'n': <String, Object?>{}}),
    'merge nothing': setMerge(<String, Object?>{}),
    'set n is a number': set(<String, Object?>{'n': 31}),
    'update time only': update(<String, Object?>{
      'time': FieldValue.serverTimestamp(),
    }),
    'update time to a value': update(<String, Object?>{'time': 40}),
    'update b with time': update(<String, Object?>{
      'b': 41,
      'time': FieldValue.serverTimestamp(),
    }),
    'update n.t time': update(<String, Object?>{
      'n.t': FieldValue.serverTimestamp(),
    }),
    'update deletes n.t': update(<String, Object?>{'n.t': FieldValue.delete()}),
    'update count': update(<String, Object?>{'count': 42}),
    'update count to a double': update(<String, Object?>{'count': 1.5}),
    'update with increment 1.5': update(<String, Object?>{
      'count': FieldValue.increment(1.5),
    }),
    'update with negative increment': update(<String, Object?>{
      'count': FieldValue.increment(-4),
    }),
    'update a with increment': update(<String, Object?>{
      'a': 43,
      'count': FieldValue.increment(1),
    }),
    'update with arrayUnion': update(<String, Object?>{
      'tags': FieldValue.arrayUnion(<Object?>[2, 8]),
    }),
    'update with arrayUnion 8,9': update(<String, Object?>{
      'tags': FieldValue.arrayUnion(<Object?>[8, 9, 3.0]),
    }),
    'update with arrayRemove 2': update(<String, Object?>{
      'tags': FieldValue.arrayRemove(<Object?>[2, 7]),
    }),
    'update tags': update(<String, Object?>{
      'tags': <int>[3, 4],
    }),
    'update n.tags union': update(<String, Object?>{
      'n.tags': FieldValue.arrayUnion(<Object?>[1]),
    }),
    'update n.count increment': update(<String, Object?>{
      'n.count': FieldValue.increment(6),
    }),
    'merge with arrayUnion': setMerge(<String, Object?>{
      'tags': FieldValue.arrayUnion(<Object?>[9]),
    }),
    'merge time and a': setMerge(<String, Object?>{
      'a': 44,
      'time': FieldValue.serverTimestamp(),
    }),
    'set count': set(<String, Object?>{'count': 0}),
    'set tags': set(<String, Object?>{
      'tags': <int>[1],
    }),
    'delete': deleteMutation('coll/a'),
  };

  final Map<String, MaybeDocument?> documents = <String, MaybeDocument?>{
    'unknown': null,
    'missing': deletedDoc('coll/a', 1),
    'empty': doc('coll/a', 1, <String, Object?>{}),
    'flat': doc('coll/a', 1, <String, Object?>{
      'a': 100,
      'b': 101,
      'c': 102,
      'count': 5,
      'tags': <int>[1, 2],
    }),
    'with time and doubles': doc('coll/a', 1, <String, Object?>{
      'time': 7,
      'count': 2.5,
      'tags': <Object>[2.0, 'x', 8],
      'n': <String, Object?>{'t': 1, 'count': 9007199254740992.0, 'tags': 3},
    }),
    'large count': doc('coll/a', 1, <String, Object?>{
      'count': 9223372036854775806,
      'n': <String, Object?>{'count': 9223372036854775807},
    }),
    'nested': doc('coll/a', 1, <String, Object?>{
      'a': <String, Object?>{'x': 1, 'w': 2},
      'n': <String, Object?>{'x': 103, 'y': 104, 'w': 105},
    }),
    'deep': doc('coll/a', 1, <String, Object?>{
      'n': <String, Object?>{
        'x': <String, Object?>{'deep': 106, 'other': 107},
      },
    }),
    'n is a number': doc('coll/a', 1, <String, Object?>{'n': 5, 'a': 6}),
  };

  /// What the backend holds after [mutation], the only write of its commit: nothing changes when the precondition
  /// fails. The client applies the same rules to its local view.
  MaybeDocument? commit(Mutation mutation, MaybeDocument? document) =>
      mutation.precondition.isValidFor(document)
      ? mutation.applyToLocalView(document, document, time)
      : document;

  // The backend stores its own time for a server timestamp; the previous value under the estimate exists only in
  // the client.
  final RegExp estimate = RegExp(
    r'\{__local_write_time__:.*?__type__:server_timestamp\}',
  );
  String describe(MaybeDocument? document) => document is Document
      ? document.data.toString().replaceAll(estimate, 'time')
      : 'no document';

  test('a merged write leaves the backend as the two writes do', () {
    final List<String> merged = <String>[];
    for (final MapEntry<String, Mutation> first in writes.entries) {
      for (final MapEntry<String, Mutation> second in writes.entries) {
        final Mutation? one = mergeUnsentMutations(first.value, second.value);
        if (one == null) {
          continue;
        }
        merged.add('${first.key} + ${second.key}');
        for (final MapEntry<String, MaybeDocument?> before
            in documents.entries) {
          expect(
            describe(commit(one, before.value)),
            describe(commit(second.value, commit(first.value, before.value))),
            reason: '"${first.key}" then "${second.key}" on "${before.key}"',
          );
        }
      }
    }
    printOnFailure(merged.join('\n'));
    // Most pairs with a plain second write merge; fewer would mean the rules were narrowed without this test.
    expect(merged.length, greaterThan(500));
  });

  test(
    'a queue merged write by write leaves the backend as all the writes do',
    () {
      // A merged write is merged again with the next one, so the pairs above are not all the cases.
      final Random random = Random(1);
      final List<Mutation> pool = writes.values.toList();
      int merges = 0;
      for (int run = 0; run < 20000; run++) {
        final List<Mutation> written = <Mutation>[
          for (int i = 2 + random.nextInt(6); i > 0; i--)
            pool[random.nextInt(pool.length)],
        ];
        final List<Mutation> queue = <Mutation>[];
        for (final Mutation mutation in written) {
          final Mutation? one = queue.isEmpty
              ? null
              : mergeUnsentMutations(queue.last, mutation);
          if (one == null) {
            queue.add(mutation);
          } else {
            queue.last = one;
            merges++;
          }
        }
        for (final MapEntry<String, MaybeDocument?> before
            in documents.entries) {
          expect(
            describe(queue.fold(before.value, (d, m) => commit(m, d))),
            describe(written.fold(before.value, (d, m) => commit(m, d))),
            reason: 'run $run on "${before.key}": $written',
          );
        }
      }
      expect(merges, greaterThan(20000));
    },
  );

  test('transforms that merge, and transforms that do not', () {
    Mutation? merge(String first, String second) =>
        mergeUnsentMutations(writes[first]!, writes[second]!);

    // An edit that stamps a time, again and again: the usual shape of an offline edit.
    expect(merge('update with time', 'update with time'), isNotNull);
    expect(merge('update with time', 'update b with time'), isNotNull);
    expect(merge('update time only', 'update a'), isNotNull);
    expect(merge('update with time', 'update time to a value'), isNotNull);
    expect(merge('set a,b', 'update with time'), isNotNull);
    expect(merge('set with time', 'update with time'), isNotNull);
    expect(
      merge('update with arrayUnion', 'update with arrayUnion 8,9'),
      isNotNull,
    );
    expect(merge('set count', 'update with increment'), isNotNull);
    expect(merge('update count', 'update with increment'), isNotNull);
    expect(merge('update with increment', 'update a'), isNotNull);

    // The backend adds one operand at a time, rounding and saturating at each step.
    expect(merge('update with increment', 'update with increment'), isNull);
    expect(
      merge('update with increment', 'update with negative increment'),
      isNull,
    );
    expect(merge('update count to a double', 'update with increment'), isNull);
    expect(
      merge('update with arrayUnion', 'update with arrayRemove 2'),
      isNull,
    );
    expect(merge('update with arrayRemove', 'update with arrayUnion'), isNull);
    expect(merge('update with time', 'set with increment'), isNull);

    // Found by merge_unsent_writes_model_test.dart: the timestamp at n.t creates the map n, which the delete of n.t
    // leaves empty; a merged write without the timestamp would not create n.
    final Mutation stamped = merge('set count', 'update n.t time')!;
    expect(stamped, isA<SetMutation>());
    expect(mergeUnsentMutations(stamped, writes['update deletes n.t']!), isNull);
  });
}
