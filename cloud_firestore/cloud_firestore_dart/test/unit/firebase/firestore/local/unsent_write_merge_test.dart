// mergeUnsentMutations must only merge two writes when one write leaves the backend with the same document as the two
// sent one after the other, whatever the document was before. This test takes every ordered pair of a pool of writes
// and every one of a pool of documents and compares.

import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show FieldValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/unsent_write_merge.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart'
    as model;
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/array_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/numeric_increment_transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/server_timestamp_operation.dart';
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
    expect(
      mergeUnsentMutations(stamped, writes['update deletes n.t']!),
      isNull,
    );
  });

  // One test per row of the tables in "Merging repeated offline writes" of docs/guides/offline_persistence.md: the
  // guide names the row by these ids (W1 to W5, T1 to T7, N). Each pair merges (or not) as the row says, and a pair
  // that merges leaves the backend as the two writes do on every starting document.
  group('the tables of the guide', () {
    /// The merged write of [first] then [second], checked against the two writes on every starting document.
    Mutation merged(String first, String second) {
      final Mutation? one = mergeUnsentMutations(
        writes[first]!,
        writes[second]!,
      );
      expect(one, isNotNull, reason: '"$first" then "$second"');
      for (final MapEntry<String, MaybeDocument?> before in documents.entries) {
        expect(
          describe(commit(one!, before.value)),
          describe(
            commit(writes[second]!, commit(writes[first]!, before.value)),
          ),
          reason: '"$first" then "$second" on "${before.key}"',
        );
      }
      return one!;
    }

    void notMerged(String first, String second) => expect(
      mergeUnsentMutations(writes[first]!, writes[second]!),
      isNull,
      reason: '"$first" then "$second"',
    );

    FieldTransform? transformAt(Mutation mutation, String path) {
      for (final FieldTransform t in mutation.fieldTransforms) {
        if (t.fieldPath == FieldPath.fromServerFormat(path)) {
          return t;
        }
      }
      return null;
    }

    test(
      'W1: anything, then a set (serverTimestamp allowed) or a delete: the new write',
      () {
        for (final String first in writes.keys) {
          for (final String second in <String>[
            'set a,b',
            'set with time',
            'delete',
          ]) {
            expect(merged(first, second), same(writes[second]));
          }
        }
      },
    );

    test(
      'W2: a set, then an update or a set with merge: one set with the new fields applied',
      () {
        for (final (String, String) pair in <(String, String)>[
          ('set a,b', 'update n.x'),
          ('set with time', 'update a'),
          ('set nested', 'merge b,c'),
          ('set with time', 'merge with time'),
        ]) {
          final Mutation one = merged(pair.$1, pair.$2);
          expect(one, isA<SetMutation>());
          expect(one.precondition, Precondition.none);
        }
      },
    );

    test('W3: an update, then an update: one update of the fields of both', () {
      final Mutation one = merged('update a', 'update n.y, a');
      expect(one, isA<PatchMutation>());
      expect(one.precondition, Precondition(exists: true));
      expect((one as PatchMutation).mask.mask, <FieldPath>{
        field('a'),
        field('n.y'),
      });
    });

    test(
      'W4: a set with merge, then an update or a set with merge: one set with merge of the fields of both',
      () {
        for (final String second in <String>['update b', 'merge b,c']) {
          final Mutation one = merged('merge a', second);
          expect(one, isA<PatchMutation>());
          expect(one.precondition, Precondition.none);
        }
      },
    );

    test('W5: a delete, then a set with merge: one set of the new fields', () {
      final Mutation one = merged('delete', 'merge b,c');
      expect(one, isA<SetMutation>());
      expect(
        (one as SetMutation).value,
        wrapMap(<String, Object?>{'b': 12, 'c': 13}),
      );
    });

    test(
      'T1: any transform, then a value, a delete or a serverTimestamp on that field (or one containing it): the new write\'s',
      () {
        expect(
          transformAt(merged('update with increment', 'update count'), 'count'),
          isNull,
        );
        expect(
          transformAt(merged('update with arrayRemove', 'update tags'), 'tags'),
          isNull,
        );
        expect(
          transformAt(
            merged('update n.count increment', 'update deletes n'),
            'n.count',
          ),
          isNull,
        );
        expect(
          transformAt(
            merged('update with time', 'update time only'),
            'time',
          )!.operation,
          isA<ServerTimestampOperation>(),
        );
      },
    );

    test('T2: a value, then a serverTimestamp: serverTimestamp', () {
      expect(
        transformAt(
          merged('update time to a value', 'update time only'),
          'time',
        )!.operation,
        isA<ServerTimestampOperation>(),
      );
    });

    test(
      'T3: a value (or a set or a delete), then increment: the sum, for two integers within 2^53 - 1 or two doubles',
      () {
        final Mutation ints = merged('update count', 'update with increment');
        expect(transformAt(ints, 'count'), isNull);
        expect((ints as PatchMutation).value.get(field('count')), wrap(46));
        final Mutation fromSet = merged('set count', 'update with increment');
        expect((fromSet as SetMutation).value.get(field('count')), wrap(4));
        final Mutation doubles = merged(
          'update count to a double',
          'update with increment 1.5',
        );
        expect((doubles as PatchMutation).value.get(field('count')), wrap(3.0));
        // An integer with a double, and an increment of a field the pending write does not set.
        notMerged('update count to a double', 'update with increment');
        expect(
          transformAt(
            merged('update a', 'update with increment'),
            'count',
          )!.operation,
          isA<NumericIncrementTransformOperation>(),
        );
        // Out of the exact range of JavaScript numbers.
        final Mutation large = converter
            .parseUpdateData(<String, Object?>{'count': 9007199254740991})
            .toMutation(documentKey, Precondition(exists: true));
        expect(
          mergeUnsentMutations(large, writes['update with increment']!),
          isNull,
        );
      },
    );

    test(
      'T4: arrayUnion(a), then arrayUnion(b): arrayUnion of a then b, without repeats',
      () {
        final FieldTransform union = transformAt(
          merged('update with arrayUnion', 'update with arrayUnion 8,9'),
          'tags',
        )!;
        expect(union.operation, isA<ArrayTransformOperationUnion>());
        expect(
          (union.operation as ArrayTransformOperation).elements,
          <model.FieldValue>[wrap(2), wrap(8), wrap(9), wrap(3.0)],
        );
      },
    );

    test('T5: arrayRemove(a), then arrayRemove(b): arrayRemove of a and b', () {
      final FieldTransform remove = transformAt(
        merged('update with arrayRemove', 'update with arrayRemove 2'),
        'tags',
      )!;
      expect(remove.operation, isA<ArrayTransformOperationRemove>());
      expect(
        (remove.operation as ArrayTransformOperation).elements,
        <model.FieldValue>[wrap(1), wrap(2), wrap(7)],
      );
    });

    test(
      'T6: a transform, then nothing on that field, inside it or containing it: the transform, unchanged',
      () {
        expect(
          transformAt(
            merged('update with increment', 'update a'),
            'count',
          )!.operation,
          isA<NumericIncrementTransformOperation>(),
        );
        expect(
          transformAt(merged('update with time', 'update b'), 'time'),
          isNotNull,
        );
        expect(
          transformAt(merged('update n.tags union', 'update a'), 'n.tags'),
          isNotNull,
        );
      },
    );

    test(
      'T7: nothing on that field (an update or a set with merge), then a transform: the transform, unchanged',
      () {
        expect(
          transformAt(
            merged('update a', 'update with arrayUnion'),
            'tags',
          )!.operation,
          isA<ArrayTransformOperationUnion>(),
        );
        expect(
          transformAt(merged('merge a', 'update n.count increment'), 'n.count'),
          isNotNull,
        );
      },
    );

    test('N: everything else stays queued as two writes', () {
      // increment after increment of the same field.
      notMerged('update with increment', 'update with increment');
      notMerged('update with increment', 'update with negative increment');
      // arrayUnion with arrayRemove on one field.
      notMerged('update with arrayUnion', 'update with arrayRemove 2');
      notMerged('update with arrayRemove', 'update with arrayUnion');
      // An array transform after a set or a delete.
      notMerged('set tags', 'update with arrayUnion');
      notMerged('delete', 'merge with arrayUnion');
      // A pending set with increment or array transforms.
      notMerged('set with increment', 'update a');
      notMerged('set with arrayUnion', 'update a');
      // Another overlap of a transform with a field of the other write.
      notMerged('update n', 'update n.count increment');
      notMerged('update tags', 'update with arrayUnion');
      // A set with merge after an update, an update after a delete.
      notMerged('update a', 'merge b,c');
      notMerged('delete', 'update a');
      // A nested delete after a set whose serverTimestamp is at or under it.
      expect(
        mergeUnsentMutations(
          merged('set count', 'update n.t time'),
          writes['update deletes n.t']!,
        ),
        isNull,
      );
    });
  });
}
