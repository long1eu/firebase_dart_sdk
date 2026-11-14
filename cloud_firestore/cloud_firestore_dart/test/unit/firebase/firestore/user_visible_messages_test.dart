// Messages a user can see print internal objects on one line, with the
// canonical path of a document (as the JS and Android SDKs do), instead of
// the multi-line debug output of the object.

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_set.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:test/test.dart';

import '../../../util/test_util.dart';

void main() {
  test('FirestoreError.toString has the JS format on one line', () {
    // JS: `${name}: [code=${code}]: ${message}`, with the name of the code
    // in this SDK.
    expect(
      FirestoreError(
        'Missing permissions',
        FirestoreErrorCode.permissionDenied,
      ).toString(),
      'FirestoreError: [code=permissionDenied]: Missing permissions',
    );
    expect(
      FirestoreError(
        'Failed',
        FirestoreErrorCode.unavailable,
        StateError('cause'),
        StackTrace.current,
      ).toString(),
      'FirestoreError: [code=unavailable]: Failed',
    );
  });

  test('Timestamp.toString has the JS and Android format', () {
    expect(
      const Timestamp(1, 2).toString(),
      'Timestamp(seconds=1, nanoseconds=2)',
    );
    expect(
      const Timestamp(-62135596800, 999999999).toString(),
      'Timestamp(seconds=-62135596800, nanoseconds=999999999)',
    );
  });

  test('DocumentKey.toString is the path', () {
    expect(key('rooms/eros').toString(), 'rooms/eros');
    expect(key('rooms/eros/messages/1').toString(), 'rooms/eros/messages/1');
  });

  test('SnapshotVersion.toString is on one line', () {
    // The Android wording.
    expect(
      const SnapshotVersion(Timestamp(5, 6000)).toString(),
      'SnapshotVersion(seconds=5, nanos=6000)',
    );
  });

  test('a key that is not in a DocumentSet is named by its path', () {
    expect(
      () =>
          DocumentSet.emptySet((_, __) => 0).getPredecessor(key('rooms/eros')),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          'Key not contained in DocumentSet: rooms/eros',
        ),
      ),
    );
  });

  test('a mutation batch names mismatching keys by their paths', () {
    final MutationBatch batch = MutationBatch(
      batchId: 1,
      localWriteTime: Timestamp.now(),
      baseMutations: const <Mutation>[],
      mutations: <Mutation>[
        setMutation('rooms/eros', <String, Object?>{'a': 1}),
      ],
    );
    expect(
      () => batch.applyToLocalView(
        key('rooms/eros'),
        doc('rooms/other', 1, <String, Object?>{}),
      ),
      throwsA(
        isA<AssertionError>().having(
          (AssertionError e) => e.message,
          'message',
          "applyToLocalView: key rooms/eros doesn't match maybeDoc key "
              'rooms/other',
        ),
      ),
    );
  });
}
