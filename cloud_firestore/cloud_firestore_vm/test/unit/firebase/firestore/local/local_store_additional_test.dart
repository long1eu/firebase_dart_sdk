// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// LocalStoreTestCase tests added upstream after the sync point that do not
// depend on features the port lacks (overlays, bundles, limbo-free snapshots):
// testCanHandleBatchAckWhenPendingBatchesHaveOtherDocs and the
// testMultipleFieldPatches* family. Run against the eager memory, LRU memory and
// SQLite persistence variants.

import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/lru_garbage_collector.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/local_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  final Map<String, Future<Persistence> Function()> variants =
      <String, Future<Persistence> Function()>{
    'memory (eager gc)': createEagerGCMemoryPersistence,
    'memory (lru gc)': createLRUMemoryPersistence,
    'sqlite': () => createSQLitePersistence(
        'firebase/firestore/local/local_store_additional_test-${const Uuid().v4()}.db',
        const LruGarbageCollectorParams()),
  };

  for (final MapEntry<String, Future<Persistence> Function()> variant
      in variants.entries) {
    group('LocalStore ${variant.key}', () {
      late LocalStoreDriver d;

      setUp(() async {
        d = LocalStoreDriver(await variant.value());
        await d.start();
      });

      tearDown(() => d.shutdown());

      test('testCanHandleBatchAckWhenPendingBatchesHaveOtherDocs', () async {
        // Prepare two batches, the first one will get rejected by the backend.
        // When the first batch is rejected, overlay is recalculated with only the
        // second batch, even though it has more documents than what is being
        // rejected.
        await d.writeMutation(
            patchMutation('foo/bar', map(<String>['foo', 'bar'])));
        await d.writeMutations(<Mutation>[
          setMutation('foo/bar', map(<String>['foo', 'bar-set'])),
          setMutation('foo/another', map(<String>['foo', 'another'])),
        ]);

        await d.rejectMutation();
        await d.expectContains(doc('foo/bar', 0,
            map(<String>['foo', 'bar-set']), DocumentState.localMutations));
        await d.expectContains(doc('foo/another', 0,
            map(<String>['foo', 'another']), DocumentState.localMutations));
      });

      test('testMultipleFieldPatchesOnRemoteDocs', () async {
        final Query query = Query(ResourcePath.fromString('foo'));
        await d.allocateQuery(query);
        d.expectTargetId(2);

        await d.applyRemoteEvent(addedRemoteEvent(
            doc('foo/bar', 1, map(<dynamic>['likes', 0, 'stars', 0])),
            <int>[2],
            <int>[]));
        d.expectChanged(<Document>[
          doc('foo/bar', 1, map(<dynamic>['likes', 0, 'stars', 0]))
        ]);
        await d.expectContains(
            doc('foo/bar', 1, map(<dynamic>['likes', 0, 'stars', 0])));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['likes', 1])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 0]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 0]),
            DocumentState.localMutations));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['stars', 1])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 1]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 1]),
            DocumentState.localMutations));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['stars', 2])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 2]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 2]),
            DocumentState.localMutations));
      });

      test('testMultipleFieldPatchesInOneBatchOnRemoteDocs', () async {
        final Query query = Query(ResourcePath.fromString('foo'));
        await d.allocateQuery(query);
        d.expectTargetId(2);

        await d.applyRemoteEvent(addedRemoteEvent(
            doc('foo/bar', 1, map(<dynamic>['likes', 0, 'stars', 0])),
            <int>[2],
            <int>[]));
        d.expectChanged(<Document>[
          doc('foo/bar', 1, map(<dynamic>['likes', 0, 'stars', 0]))
        ]);
        await d.expectContains(
            doc('foo/bar', 1, map(<dynamic>['likes', 0, 'stars', 0])));

        await d.writeMutations(<Mutation>[
          patchMutation('foo/bar', map(<dynamic>['likes', 1])),
          patchMutation('foo/bar', map(<dynamic>['stars', 1])),
        ]);
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 1]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 1]),
            DocumentState.localMutations));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['stars', 2])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 2]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 2]),
            DocumentState.localMutations));
      });

      test('testMultipleFieldPatchesOnLocalDocs', () async {
        await d.writeMutation(
            setMutation('foo/bar', map(<dynamic>['likes', 0, 'stars', 0])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 0, 'stars', 0]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 0, 'stars', 0]),
            DocumentState.localMutations));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['likes', 1])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 0]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 0]),
            DocumentState.localMutations));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['stars', 1])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 1]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 1]),
            DocumentState.localMutations));

        await d.writeMutation(
            patchMutation('foo/bar', map(<dynamic>['stars', 2])));
        d.expectChanged(<Document>[
          doc('foo/bar', 0, map(<dynamic>['likes', 1, 'stars', 2]),
              DocumentState.localMutations)
        ]);
        await d.expectContains(doc(
            'foo/bar',
            0,
            map(<dynamic>['likes', 1, 'stars', 2]),
            DocumentState.localMutations));
      });
    });
  }
}
