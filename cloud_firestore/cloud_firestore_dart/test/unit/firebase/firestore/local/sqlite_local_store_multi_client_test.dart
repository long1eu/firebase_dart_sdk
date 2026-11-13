// Copyright 2026 Google LLC
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

// The LocalStore methods that only the multi-client mode uses (JS local_store_impl.ts:
// localStoreLookupMutationDocuments, localStoreGetCachedTarget, localStoreGetNewDocumentChanges and
// localStoreReleaseTarget with keepPersistedTargetData). The JS SDK covers them through its multi-tab spec tests
// only (IndexedDb); these cases pin their behaviour on SQLite, the port's multi-client persistence.

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_data.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:test/test.dart';

import '../../../../util/local_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  late LocalStoreDriver d;

  setUp(() async {
    d = LocalStoreDriver(await createSQLitePersistence());
    await d.start();
  });

  tearDown(() => d.shutdown());

  group('lookupMutationDocuments', () {
    test('returns the local view of the documents of a batch', () async {
      await d.writeMutation(setMutation('foo/bar', map(<dynamic>['a', 1])));
      await d.writeMutation(patchMutation('foo/bar', map(<dynamic>['b', 2])));

      final ImmutableSortedMap<DocumentKey, MaybeDocument>? documents = await d
          .localStore
          .lookupMutationDocuments(d.batches.first.batchId);
      expect(documents, isNotNull);
      expect(documents!.length, 1);
      expect(
        documents[key('foo/bar')],
        doc(
          'foo/bar',
          0,
          map(<dynamic>['a', 1, 'b', 2]),
          DocumentState.localMutations,
        ),
      );
    });

    test('returns null for a batch that is not in the queue', () async {
      expect(await d.localStore.lookupMutationDocuments(42), isNull);
    });
  });

  group('getCachedTarget', () {
    test('returns the target of an active target id', () async {
      final Query q = query('foo');
      final int targetId = await d.allocateQuery(q);
      expect(await d.localStore.getCachedTarget(targetId), q.toTarget());
    });

    test('reads a target that is not active from the target cache', () async {
      final Query q = query('foo');
      final int targetId = await d.allocateQuery(q);
      await d.localStore.releaseTarget(targetId, keepPersistedTargetData: true);

      final Target? target = await d.localStore.getCachedTarget(targetId);
      expect(target, q.toTarget());
    });

    test('returns null for an unknown target id', () async {
      expect(await d.localStore.getCachedTarget(42), isNull);
    });
  });

  group('releaseTarget', () {
    test('keepPersistedTargetData keeps the persisted target data', () async {
      final Query q = query('foo');
      final int targetId = await d.allocateQuery(q);
      await d.applyRemoteEvent(
        addedRemoteEvent(doc('foo/bar', 10, map(<dynamic>['a', 1])), <int>[
          targetId,
        ], <int>[]),
      );

      await d.localStore.releaseTarget(targetId, keepPersistedTargetData: true);

      final QueryData? persisted = await d.persistence.queryCache.getQueryData(
        q.toTarget(),
      );
      expect(persisted, isNotNull);
      expect(persisted!.targetId, targetId);
      // Allocating the target again resumes the persisted one.
      expect(await d.allocateQuery(q), targetId);
    });
  });

  group('getNewDocumentChanges', () {
    test('returns the documents read since the previous call', () async {
      final int targetId = await d.allocateQuery(query('foo'));
      await d.applyRemoteEvent(
        addedRemoteEvent(doc('foo/a', 1, map(<dynamic>['v', 1])), <int>[
          targetId,
        ], <int>[]),
      );
      await d.applyRemoteEvent(
        addedRemoteEvent(doc('bar/a', 1, map(<dynamic>['v', 1])), <int>[
          targetId,
        ], <int>[]),
      );

      ImmutableSortedMap<DocumentKey, MaybeDocument> changes = await d
          .localStore
          .getNewDocumentChanges('foo');
      expect(_keys(changes), <DocumentKey>[key('foo/a')]);

      // Nothing was read since.
      changes = await d.localStore.getNewDocumentChanges('foo');
      expect(changes.isEmpty, isTrue);

      await d.applyRemoteEvent(
        addedRemoteEvent(doc('foo/b', 2, map(<dynamic>['v', 2])), <int>[
          targetId,
        ], <int>[]),
      );
      changes = await d.localStore.getNewDocumentChanges('foo');
      expect(_keys(changes), <DocumentKey>[key('foo/b')]);

      // The read time of each collection group is tracked separately.
      changes = await d.localStore.getNewDocumentChanges('bar');
      expect(_keys(changes), <DocumentKey>[key('bar/a')]);
    });
  });
}

List<DocumentKey> _keys(ImmutableSortedMap<DocumentKey, MaybeDocument> map) =>
    <DocumentKey>[
      for (final MapEntry<DocumentKey, MaybeDocument> entry in map) entry.key,
    ];
