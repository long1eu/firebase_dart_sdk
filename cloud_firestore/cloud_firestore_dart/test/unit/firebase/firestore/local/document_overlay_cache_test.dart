// Copyright 2021 Google LLC
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

// Port of the Android SDK's DocumentOverlayCacheTestCase, run against the memory and the SQLite persistence.
// testSaveOverlaysThrowsNullPointerExceptionOnNullMapValue is not ported: the Dart map type does not allow null values.

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart'
    as firestore;
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/user_data_converter.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  _run('memory', () => createEagerGCMemoryPersistence());
  _run('sqlite', () => createSQLitePersistence());
}

void _run(String name, Future<Persistence> Function() createPersistence) {
  group(name, () {
    late Persistence persistence;
    late DocumentOverlayCache cache;

    setUp(() async {
      persistence = await createPersistence();
      cache = persistence.getDocumentOverlayCache(User.unauthenticated);
    });

    tearDown(() => persistence.shutdown());

    Future<void> saveOverlays(int largestBatch, List<Mutation> mutations) {
      return persistence.runTransaction('saveOverlays', () {
        return cache.saveOverlays(largestBatch, <DocumentKey, Mutation>{
          for (Mutation mutation in mutations) mutation.key: mutation,
        });
      });
    }

    Future<void> saveOverlaysForKeys(int largestBatch, List<String> keys) {
      return saveOverlays(largestBatch, <Mutation>[
        for (String k in keys) setMutation(k, map()),
      ]);
    }

    void verifyOverlayContains(
      Map<DocumentKey, Overlay> overlays,
      List<String> keys,
    ) {
      expect(overlays.keys.toSet(), keys.map(key).toSet());
    }

    test('testReturnsNullWhenOverlayIsNotFound', () async {
      expect(await cache.getOverlay(key('coll/doc1')), isNull);
    });

    test('testSkipsNonExistingOverlayInBatchLookup', () async {
      expect(await cache.getOverlays(<DocumentKey>[key('coll/doc1')]), isEmpty);
    });

    test('testSupportsEmptyBatchInBatchLookup', () async {
      expect(await cache.getOverlays(<DocumentKey>[]), isEmpty);
    });

    test('testCanReadSavedOverlay', () async {
      final Mutation m = patchMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      await saveOverlays(2, <Mutation>[m]);

      expect((await cache.getOverlay(key('coll/doc1')))!.mutation, m);
    });

    test('testCanReadSavedOverlays', () async {
      final Mutation m1 = patchMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      final Mutation m2 = setMutation(
        'coll/doc2',
        map(<dynamic>['foo', 'bar']),
      );
      final Mutation m3 = deleteMutation('coll/doc3');
      await saveOverlays(3, <Mutation>[m1, m2, m3]);

      expect((await cache.getOverlay(key('coll/doc1')))!.mutation, m1);
      expect((await cache.getOverlay(key('coll/doc2')))!.mutation, m2);
      expect((await cache.getOverlay(key('coll/doc3')))!.mutation, m3);
    });

    test('testCanReadSavedOverlaysInBatches', () async {
      final Mutation m1 = setMutation('coll1/a', map(<dynamic>['a', 1]));
      final Mutation m2 = setMutation('coll1/b', map(<dynamic>['b', 2]));
      final Mutation m3 = setMutation('coll2/c', map(<dynamic>['c', 3]));
      await saveOverlays(3, <Mutation>[m1, m2, m3]);

      final Map<DocumentKey, Overlay> overlays = await cache.getOverlays(
        <DocumentKey>[key('coll1/a'), key('coll1/b'), key('coll2/c')],
      );
      expect(overlays[key('coll1/a')]!.mutation, m1);
      expect(overlays[key('coll1/b')]!.mutation, m2);
      expect(overlays[key('coll2/c')]!.mutation, m3);
    });

    test('testCanReadUnlimitedNumberOfOverlays', () async {
      // This test that we can read more than 1000 overlays, which exceeds the bind var limit in SQLite.
      final List<DocumentKey> keys = <DocumentKey>[];
      for (int i = 0; i < 1001; ++i) {
        keys.add(key('coll/$i'));
        await saveOverlays(i, <Mutation>[setMutation('coll/$i', map())]);
      }
      expect(await cache.getOverlays(keys), hasLength(1001));
    });

    test('testSavingOverlayOverwrites', () async {
      final Mutation m1 = patchMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      final Mutation m2 = setMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'set', 'bar', 42]),
      );
      await saveOverlays(2, <Mutation>[m1]);
      await saveOverlays(2, <Mutation>[m2]);

      expect((await cache.getOverlay(key('coll/doc1')))!.mutation, m2);
    });

    test('testDeleteRepeatedlyWorks', () async {
      final Mutation m = patchMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      await saveOverlays(2, <Mutation>[m]);

      await cache.removeOverlaysForBatchId(2);
      expect(await cache.getOverlay(key('coll/doc1')), isNull);

      // Repeat
      await cache.removeOverlaysForBatchId(2);
      expect(await cache.getOverlay(key('coll/doc1')), isNull);
    });

    /// Port of the JS SDK's `can delete overlays` (document_overlay_cache.test.ts). The port removes the overlays of a
    /// batch by batch id only, as the Android SDK does.
    test('can delete overlays', () async {
      final Mutation m1 = patchMutation('coll1/doc1', map(<dynamic>['a', 'b']));
      final Mutation m2 = patchMutation('coll1/doc2', map(<dynamic>['a', 'b']));
      final Mutation m3 = patchMutation('coll1/doc3', map(<dynamic>['a', 'b']));
      final Mutation m4 = patchMutation('coll1/doc4', map(<dynamic>['a', 'b']));
      final Mutation m5 = patchMutation(
        'coll2/doc1/coll3/doc1',
        map(<dynamic>['a', 'b']),
      );
      final Mutation m6 = patchMutation(
        'coll2/doc2/coll3/doc2',
        map(<dynamic>['a', 'b']),
      );
      await saveOverlays(2, <Mutation>[m1, m2]);
      await saveOverlays(3, <Mutation>[m3]);
      await saveOverlays(4, <Mutation>[m4]);
      await saveOverlays(2, <Mutation>[m5, m6]);

      // Remove documents with batch id 2.
      await cache.removeOverlaysForBatchId(2);
      expect(await cache.getOverlay(key('coll1/doc1')), isNull);
      expect(await cache.getOverlay(key('coll1/doc2')), isNull);
      expect(await cache.getOverlay(key('coll2/doc1/coll3/doc1')), isNull);
      expect(await cache.getOverlay(key('coll2/doc2/coll3/doc2')), isNull);
      expect(await cache.getOverlay(key('coll1/doc3')), isNotNull);
      expect(await cache.getOverlay(key('coll1/doc4')), isNotNull);

      // Remove documents with batch id 3.
      await cache.removeOverlaysForBatchId(3);
      expect(await cache.getOverlay(key('coll1/doc3')), isNull);
      expect(await cache.getOverlay(key('coll1/doc4')), isNotNull);

      // Remove documents with batch id 4.
      await cache.removeOverlaysForBatchId(4);
      expect(await cache.getOverlay(key('coll1/doc4')), isNull);
    });

    // Ported from the iOS SDK (Firestore/core/test/unit/local/document_overlay_cache_test.cc).
    test('testGetOverlayExactlyMatchesTheGivenDocumentKey', () async {
      await saveOverlaysForKeys(1, <String>['coll/doc1/sub/doc2']);

      expect(await cache.getOverlay(key('coll/d')), isNull);
      expect(await cache.getOverlay(key('coll/doc1')), isNull);
      expect(await cache.getOverlay(key('coll/doc1ZZ')), isNull);

      final Overlay? overlay = await cache.getOverlay(
        key('coll/doc1/sub/doc2'),
      );
      expect(overlay, isNotNull);
      expect(overlay!.key, key('coll/doc1/sub/doc2'));
    });

    // Ported from the iOS SDK (Firestore/core/test/unit/local/document_overlay_cache_test.cc).
    test('testOverwriteEntryUpdatesIndexes', () async {
      final Mutation mutation1 = patchMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      await saveOverlays(100, <Mutation>[mutation1]);
      final Mutation mutation2 = patchMutation(
        'coll/doc1',
        map(<dynamic>['biz', 'baz']),
      );
      await saveOverlays(101, <Mutation>[mutation2]);

      expect(await cache.getOverlay(key('coll/doc1')), Overlay(101, mutation2));
      await cache.removeOverlaysForBatchId(101);
      expect(await cache.getOverlay(key('coll/doc1')), isNull);

      // Overwriting an overlay drops the entry of its old batch: removing that
      // batch leaves the new overlay alone.
      final Mutation mutation3 = patchMutation(
        'coll/doc1',
        map(<dynamic>['xxx', 'yyy']),
      );
      await saveOverlays(200, <Mutation>[mutation3]);
      await cache.removeOverlaysForBatchId(100);
      expect(await cache.getOverlay(key('coll/doc1')), Overlay(200, mutation3));
      expect(await cache.getOverlaysForCollection(path('coll'), -1), hasLength(1));
    });

    // Ported from the iOS SDK (Firestore/core/test/unit/local/document_overlay_cache_test.cc).
    test('testSaveDoesntAffectSubCollections', () async {
      final Mutation mutation1 = patchMutation(
        'coll/doc/subcoll/subdoc',
        map(<dynamic>['foo', 'bar1']),
      );
      final Mutation mutation2 = patchMutation(
        'coll/doc',
        map(<dynamic>['foo', 'bar2']),
      );
      await saveOverlays(1, <Mutation>[mutation1]);
      await saveOverlays(2, <Mutation>[mutation2]);

      expect(
        (await cache.getOverlay(key('coll/doc/subcoll/subdoc')))!.mutation,
        mutation1,
      );
      expect((await cache.getOverlay(key('coll/doc')))!.mutation, mutation2);
    });

    test('testGetAllOverlaysForCollection', () async {
      final Mutation m1 = patchMutation(
        'coll/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      final Mutation m2 = setMutation(
        'coll/doc2',
        map(<dynamic>['foo', 'bar']),
      );
      final Mutation m3 = deleteMutation('coll/doc3');
      // m4 and m5 are not under "coll"
      final Mutation m4 = setMutation(
        'coll/doc1/sub/sub_doc',
        map(<dynamic>['foo', 'bar']),
      );
      final Mutation m5 = setMutation(
        'other/doc1',
        map(<dynamic>['foo', 'bar']),
      );
      await saveOverlays(3, <Mutation>[m1, m2, m3, m4, m5]);

      final Map<DocumentKey, Overlay> overlays = await cache
          .getOverlaysForCollection(path('coll'), -1);
      verifyOverlayContains(overlays, <String>[
        'coll/doc1',
        'coll/doc2',
        'coll/doc3',
      ]);
    });

    test('testGetAllOverlaysSinceBatchId', () async {
      await saveOverlaysForKeys(2, <String>['coll/doc1', 'coll/doc2']);
      await saveOverlaysForKeys(3, <String>['coll/doc3']);
      await saveOverlaysForKeys(4, <String>['coll/doc4']);

      final Map<DocumentKey, Overlay> overlays = await cache
          .getOverlaysForCollection(path('coll'), 2);
      verifyOverlayContains(overlays, <String>['coll/doc3', 'coll/doc4']);
    });

    test(
      'testGetAllOverlaysFromCollectionGroupEnforcesCollectionGroup',
      () async {
        await saveOverlaysForKeys(2, <String>['coll1/doc1', 'coll2/doc1']);
        await saveOverlaysForKeys(3, <String>['coll1/doc2']);
        await saveOverlaysForKeys(4, <String>['coll2/doc2']);

        final Map<DocumentKey, Overlay> overlays = await cache
            .getOverlaysForCollectionGroup('coll1', -1, 50);
        verifyOverlayContains(overlays, <String>['coll1/doc1', 'coll1/doc2']);
      },
    );

    test('testGetAllOverlaysFromCollectionGroupEnforcesBatchId', () async {
      await saveOverlaysForKeys(2, <String>['coll/doc1']);
      await saveOverlaysForKeys(3, <String>['coll/doc2']);

      final Map<DocumentKey, Overlay> overlays = await cache
          .getOverlaysForCollectionGroup('coll', 2, 50);
      verifyOverlayContains(overlays, <String>['coll/doc2']);
    });

    test('testGetAllOverlaysFromCollectionGroupEnforcesLimit', () async {
      await saveOverlaysForKeys(1, <String>['coll/doc1']);
      await saveOverlaysForKeys(2, <String>['coll/doc2']);
      await saveOverlaysForKeys(3, <String>['coll/doc3']);

      final Map<DocumentKey, Overlay> overlays = await cache
          .getOverlaysForCollectionGroup('coll', -1, 2);
      verifyOverlayContains(overlays, <String>['coll/doc1', 'coll/doc2']);
    });

    test(
      'testGetAllOverlaysFromCollectionGroupWithLimitIncludesFullBatches',
      () async {
        await saveOverlaysForKeys(1, <String>['coll/doc1']);
        await saveOverlaysForKeys(2, <String>['coll/doc2', 'coll/doc3']);

        final Map<DocumentKey, Overlay> overlays = await cache
            .getOverlaysForCollectionGroup('coll', -1, 2);
        verifyOverlayContains(overlays, <String>[
          'coll/doc1',
          'coll/doc2',
          'coll/doc3',
        ]);
      },
    );

    test('testUpdateDocumentOverlay', () async {
      final Mutation mutation1 = setMutation(
        'coll/doc',
        map(<dynamic>['foo', 1]),
      );
      final Mutation mutation2 = setMutation(
        'coll/doc',
        map(<dynamic>['foo', 2]),
      );
      await saveOverlays(1, <Mutation>[mutation1]);
      await saveOverlays(2, <Mutation>[mutation2]);

      // Verify that `getOverlay()` returns the updated mutation.
      expect(await cache.getOverlay(key('coll/doc')), Overlay(2, mutation2));

      // Verify that `removeOverlaysForBatchId()` removes the overlay completely.
      await cache.removeOverlaysForBatchId(2);
      expect(await cache.getOverlay(key('coll/doc')), isNull);
    });

    test('testOverlaysArePerUser', () async {
      final Mutation m = setMutation('coll/doc', map(<dynamic>['foo', 1]));
      await saveOverlays(1, <Mutation>[m]);

      final DocumentOverlayCache other = persistence.getDocumentOverlayCache(
        const User('other'),
      );
      expect(await other.getOverlay(key('coll/doc')), isNull);
      expect(
        await persistence
            .getDocumentOverlayCache(User.unauthenticated)
            .getOverlay(key('coll/doc')),
        Overlay(1, m),
      );
    });

    test('testStoresPendingServerTimestamps', () async {
      final Mutation patch = UserDataConverter(DatabaseId.forProject('p'))
          .parseUpdateData(<String, Object>{
            'time': firestore.FieldValue.serverTimestamp(),
          })
          .toMutation(key('coll/doc'), Precondition.none);
      final Mutation overlay = Mutation.calculateOverlayMutation(
        patch.applyToLocalView(
          doc('coll/doc', 1, map(<dynamic>['time', 1])),
          null,
          Timestamp(10, 0),
        ),
        null,
      )!;
      expect(
        (overlay as dynamic).value.get(field('time')),
        isA<ServerTimestampValue>(),
      );
      await saveOverlays(5, <Mutation>[overlay]);

      expect(await cache.getOverlay(key('coll/doc')), Overlay(5, overlay));
    });
  });
}
