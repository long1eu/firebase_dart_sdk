// Acknowledgements whose document version equals the version of the cached document.
//
// The backend reports an unchanged update time for a write that did not change the document, for example a write
// that is sent again after its acknowledgement was lost (reviews/chaos_findings.md, F1b). Upstream only applies an
// acknowledged write to a cached document that is strictly older; the port also applies it to a cached document of
// the same version when that document is only the result of earlier acknowledgements.

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_batch_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/local_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final Map<String, Future<Persistence> Function()>
  variants = <String, Future<Persistence> Function()>{
    // Not the eager memory collector: it drops an acknowledged document that no target holds.
    'memory (lru gc)': createLRUMemoryPersistence,
    'sqlite': () => createSQLitePersistence(
      'firebase/firestore/local/local_store_ack_same_version_test-${const Uuid().v4()}.db',
      const LruGarbageCollectorParams(),
    ),
  };

  for (final MapEntry<String, Future<Persistence> Function()> variant
      in variants.entries) {
    group('LocalStore ${variant.key}', () {
      late LocalStoreDriver d;

      setUp(() async {
        d = LocalStoreDriver(await variant.value());
        await d.start();
        // A target keeps the documents in the cache (eager garbage collection).
        final int targetId = await d.allocateQuery(
          Query(ResourcePath.fromString('foo')),
        );
        await d.applyRemoteEvent(
          addedRemoteEvent(doc('foo/other', 1, map(<String>['a', 'b'])), <int>[
            targetId,
          ], <int>[]),
        );
      });

      tearDown(() => d.shutdown());

      /// Acknowledges the oldest batch: the backend committed it at [commitVersion] and reports [documentVersion]
      /// as the update time of the document after the write.
      Future<void> acknowledge(int documentVersion, int commitVersion) async {
        final MutationBatch batch = d.batches.removeAt(0);
        await d.localStore.acknowledgeBatch(
          MutationBatchResult.create(
            batch,
            version(commitVersion),
            <MutationResult>[
              MutationResult(version(documentVersion), <FieldValue>[]),
            ],
            Uint8List(0),
          ),
        );
      }

      test('a write that changed nothing on the backend is applied to a cached '
          'estimate of the same version', () async {
        await d.writeMutation(
          setMutation('foo/bar', map(<Object>['n', 0, 'tag', 'first'])),
        );
        await acknowledge(1, 1);
        await d.expectContains(
          doc(
            'foo/bar',
            1,
            map(<Object>['n', 0, 'tag', 'first']),
            DocumentState.committedMutations,
          ),
        );

        // Two writes that the backend already applied once (their acknowledgements were lost) are sent again.
        // The first one changes the document again; the second one changes nothing, so the backend reports the
        // update time of the first one for it.
        await d.writeMutation(patchMutation('foo/bar', map(<Object>['n', 2])));
        await d.writeMutation(
          patchMutation('foo/bar', map(<Object>['tag', 'second'])),
        );
        await acknowledge(4, 4);
        await acknowledge(4, 5);
        await d.expectContains(
          doc(
            'foo/bar',
            4,
            map(<Object>['n', 2, 'tag', 'second']),
            DocumentState.committedMutations,
          ),
        );
      });

      test('a document that came from the backend at the same version is left '
          'alone', () async {
        await d.writeMutation(
          patchMutation('foo/bar', map(<Object>['tag', 'second'])),
        );
        // The watch stream delivers the document, which contains the write, before the acknowledgement arrives.
        await d.applyRemoteEvent(
          addedRemoteEvent(
            doc('foo/bar', 4, map(<Object>['n', 7, 'tag', 'second'])),
            <int>[d.lastTargetId],
            <int>[],
          ),
        );
        await acknowledge(4, 4);
        await d.expectContains(
          doc(
            'foo/bar',
            4,
            map(<Object>['n', 7, 'tag', 'second']),
            DocumentState.synced,
          ),
        );
      });

      test('an older acknowledgement never overwrites a newer document', () async {
        await d.writeMutation(
          patchMutation('foo/bar', map(<Object>['tag', 'old'])),
        );
        // The estimate of a later state arrives first, here from the watch stream.
        await d.applyRemoteEvent(
          addedRemoteEvent(
            doc('foo/bar', 9, map(<Object>['tag', 'newer'])),
            <int>[d.lastTargetId],
            <int>[],
          ),
        );
        await acknowledge(4, 4);
        await d.expectContains(
          doc(
            'foo/bar',
            9,
            map(<Object>['tag', 'newer']),
            DocumentState.synced,
          ),
        );

        // And an estimate that is newer than the acknowledgement is kept as well.
        await d.writeMutation(
          setMutation('foo/baz', map(<Object>['tag', 'estimate'])),
        );
        await acknowledge(9, 9);
        await d.writeMutation(
          patchMutation('foo/baz', map(<Object>['tag', 'late'])),
        );
        await acknowledge(8, 8);
        await d.expectContains(
          doc(
            'foo/baz',
            9,
            map(<Object>['tag', 'estimate']),
            DocumentState.committedMutations,
          ),
        );
      });
    });
  }
}
