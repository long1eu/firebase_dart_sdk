import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/verify_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

void main() {
  group('Precondition', () {
    test('updateTime holds only for a document at exactly that version', () {
      final Precondition p = Precondition(updateTime: version(5));
      expect(p.isNone, isFalse);
      expect(p.isValidFor(doc('c/a', 5, emptyMap)), isTrue);
      expect(p.isValidFor(doc('c/a', 6, emptyMap)), isFalse);
      // A deleted or unknown document never satisfies an update time.
      expect(p.isValidFor(deletedDoc('c/a', 5)), isFalse);
      expect(p.isValidFor(unknownDoc('c/a', 5)), isFalse);
      expect(p.isValidFor(null), isFalse);
      expect(p.toString(), contains('updateTime'));
    });

    test('exists checks for a found document', () {
      expect(
        Precondition(exists: true).isValidFor(doc('c/a', 1, emptyMap)),
        isTrue,
      );
      expect(
        Precondition(exists: true).isValidFor(deletedDoc('c/a', 1)),
        isFalse,
      );
      expect(Precondition(exists: false).isValidFor(null), isTrue);
      expect(Precondition(exists: false).toString(), contains('exists'));
      expect(Precondition.none.isValidFor(null), isTrue);
      expect(Precondition.none.toString(), contains('<none>'));
    });

    test('cannot carry both an update time and existence', () {
      expect(
        () => Precondition(updateTime: version(1), exists: true),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('VerifyMutation', () {
    final VerifyMutation verify = VerifyMutation(
      key('c/a'),
      Precondition(updateTime: version(1)),
    );

    test('is never applied locally', () {
      expect(
        () => verify.applyToLocalView(
          doc('c/a', 1, emptyMap),
          null,
          Timestamp.now(),
        ),
        throwsStateError,
      );
      expect(
        () => verify.applyToRemoteDocument(
          doc('c/a', 1, emptyMap),
          mutationResult(2),
        ),
        throwsStateError,
      );
    });

    test('equality uses the key and precondition', () {
      expect(
        verify,
        VerifyMutation(key('c/a'), Precondition(updateTime: version(1))),
      );
      expect(
        verify.hashCode,
        VerifyMutation(
          key('c/a'),
          Precondition(updateTime: version(1)),
        ).hashCode,
      );
      expect(
        verify == VerifyMutation(key('c/b'), verify.precondition),
        isFalse,
      );
    });
  });

  group('MutationBatch', () {
    final Timestamp writeTime = Timestamp.now();

    test('applyToLocalDocumentSet applies every key, including missing ones', () {
      final MutationBatch withWrites = MutationBatch(
        batchId: 2,
        localWriteTime: writeTime,
        baseMutations: const <Mutation>[],
        mutations: <Mutation>[
          setMutation('c/a', map(<Object>['v', 1])),
          patchMutation('c/b', map(<Object>['v', 2])),
          setMutation('c/a', map(<Object>['v', 3])),
        ],
      );
      expect(withWrites.keys, <Object>{key('c/a'), key('c/b')});

      final ImmutableSortedMap<DocumentKey, MaybeDocument> input =
          ImmutableSortedMap<DocumentKey, MaybeDocument>.emptyMap(
            DocumentKey.comparator,
          ).insert(key('c/b'), doc('c/b', 1, map(<Object>['w', 1])));
      final ImmutableSortedMap<DocumentKey, MaybeDocument> output = withWrites
          .applyToLocalDocumentSet(input);

      // The later set wins for c/a, and the patch merges into the existing c/b.
      final Document a = output[key('c/a')]! as Document;
      expect(a.data, wrapMap(map(<Object>['v', 3])));
      expect(a.hasLocalMutations, isTrue);
      final Document b = output[key('c/b')]! as Document;
      expect(b.data, wrapMap(map(<Object>['w', 1, 'v', 2])));
      // The input map is persistent and stays untouched.
      expect(input[key('c/a')], isNull);
    });

    test('a result needs one mutation result per mutation', () {
      final MutationBatch batch = MutationBatch(
        batchId: 1,
        localWriteTime: writeTime,
        baseMutations: const <Mutation>[],
        mutations: <Mutation>[setMutation('c/a', emptyMap)],
      );
      expect(
        () => MutationBatchResult.create(
          batch,
          version(1),
          <MutationResult>[],
          Uint8List(0),
        ),
        throwsA(isA<AssertionError>()),
      );

      final MutationBatchResult result = MutationBatchResult.create(
        batch,
        version(3),
        <MutationResult>[mutationResult(2)],
        Uint8List(0),
      );
      expect(result.docVersions[key('c/a')], version(2));
    });

    test('applying a result for another document fails', () {
      final MutationBatch batch = MutationBatch(
        batchId: 1,
        localWriteTime: writeTime,
        baseMutations: const <Mutation>[],
        mutations: <Mutation>[setMutation('c/a', emptyMap)],
      );
      expect(
        () => batch.applyToLocalView(key('c/a'), doc('c/b', 1, emptyMap)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('paths', () {
    test('isImmediateParentOf only accepts a direct child', () {
      final ResourcePath parent = path('a/b');
      expect(parent.isImmediateParentOf(path('a/b/c')), isTrue);
      expect(parent.isImmediateParentOf(path('a/b')), isFalse);
      expect(parent.isImmediateParentOf(path('a/b/c/d')), isFalse);
      expect(parent.isImmediateParentOf(path('a/x/c')), isFalse);
    });

    test('keepFirst and the comparison operators', () {
      expect(path('a/b/c').keepFirst(2), path('a/b'));
      expect(path('a/b') < path('a/b/c'), isTrue);
      expect(path('a/b') <= path('a/b'), isTrue);
      expect(path('b') > path('a/z'), isTrue);
      expect(path('a/b') >= path('a/c'), isFalse);
    });

    test('server format rejects trailing escapes and empty segments', () {
      expect(() => FieldPath.fromServerFormat(r'a\'), throwsArgumentError);
      expect(() => FieldPath.fromServerFormat('a..b'), throwsArgumentError);
      expect(() => FieldPath.fromServerFormat('.a'), throwsArgumentError);
      expect(
        FieldPath.fromServerFormat(r'a\.b.`c.d`'),
        FieldPath.fromSegments(<String>['a.b', 'c.d']),
      );
    });
  });

  group('DocumentSet', () {
    final DocumentSet set = docSet(Document.keyComparator, <Document>[
      doc('c/a', 1, emptyMap),
      doc('c/b', 1, emptyMap),
    ]);

    test('first, last and indexOf', () {
      expect(set.first.key, key('c/a'));
      expect(set.last.key, key('c/b'));
      expect(set.indexOf(key('c/b')), 1);
      expect(set.indexOf(key('c/z')), -1);
    });

    test('getPredecessor needs a contained key', () {
      expect(set.getPredecessor(key('c/a')), isNull);
      expect(set.getPredecessor(key('c/b'))!.key, key('c/a'));
      expect(() => set.getPredecessor(key('c/z')), throwsArgumentError);
    });
  });
}
