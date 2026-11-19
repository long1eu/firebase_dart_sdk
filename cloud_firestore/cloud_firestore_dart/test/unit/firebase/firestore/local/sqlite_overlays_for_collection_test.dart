// SQLiteDocumentOverlayCache.getOverlaysForCollection reads through the batch id index when few overlays are newer
// than the batch asked for, and through the primary key otherwise. Both must return the same overlays.

import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/overlay.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

void main() {
  test('both reads of the overlays of a collection return the same', () async {
    final int before = SQLiteDocumentOverlayCache.batchIdIndexMaxRows;
    addTearDown(() => SQLiteDocumentOverlayCache.batchIdIndexMaxRows = before);
    final Persistence persistence = await createSQLitePersistence();
    addTearDown(persistence.shutdown);
    final Random random = Random(7);
    const List<String> collections = <String>[
      'a',
      'b',
      'a/1/b',
      'a/1/a',
      'a/2/b',
      'c',
    ];
    for (final User user in <User>[User.unauthenticated, const User('u')]) {
      final DocumentOverlayCache cache = persistence.getDocumentOverlayCache(
        user,
      );
      for (int batch = 1; batch <= 120; batch++) {
        await persistence.runTransaction('save', () {
          return cache.saveOverlays(
            batch,
            <DocumentKey, Mutation>{
              for (int i = 1 + random.nextInt(3); i > 0; i--)
                key(
                  '${collections[random.nextInt(collections.length)]}/d${random.nextInt(40)}',
                ): setMutation('x/y', <String, Object?>{
                  'n': batch,
                }),
            }.map(
              (DocumentKey k, Mutation _) => MapEntry<DocumentKey, Mutation>(
                k,
                setMutation(k.path.canonicalString, <String, Object?>{
                  'n': batch,
                }),
              ),
            ),
          );
        });
      }
    }

    String read(Map<DocumentKey, Overlay> overlays) =>
        (overlays.entries
                .map(
                  (MapEntry<DocumentKey, Overlay> e) =>
                      '${e.key}:${e.value.largestBatchId}:${e.value.mutation}',
                )
                .toList()
              ..sort())
            .join('\n');

    int compared = 0;
    for (final User user in <User>[User.unauthenticated, const User('u')]) {
      final DocumentOverlayCache cache = persistence.getDocumentOverlayCache(
        user,
      );
      for (final String collection in <String>[...collections, 'none']) {
        for (final int since in <int>[-1, 0, 1, 50, 100, 119, 120, 500]) {
          Future<String> get(int maxRows) {
            SQLiteDocumentOverlayCache.batchIdIndexMaxRows = maxRows;
            return persistence.runTransactionAndReturn(
              'read',
              () async => read(
                await cache.getOverlaysForCollection(path(collection), since),
              ),
            );
          }

          final String byCollection = await get(0);
          expect(
            await get(1000000),
            byCollection,
            reason: '$collection $since',
          );
          expect(await get(10), byCollection, reason: '$collection $since');
          if (byCollection.isNotEmpty) {
            compared++;
          }
        }
      }
    }
    expect(compared, greaterThan(40));
  });

  test(
    'the overlays of a collection query read a page at a time are those of the collection, split',
    () async {
      final int before = SQLiteDocumentOverlayCache.collectionPageSize;
      addTearDown(() => SQLiteDocumentOverlayCache.collectionPageSize = before);
      final Persistence persistence = await createSQLitePersistence();
      addTearDown(persistence.shutdown);
      final DocumentOverlayCache cache = persistence.getDocumentOverlayCache(
        User.unauthenticated,
      );
      final Random random = Random(11);
      for (int batch = 1; batch <= 60; batch++) {
        final int i = random.nextInt(50);
        final String path = random.nextInt(5) == 0
            ? 'c/d$i/s/e$i'
            : (random.nextBool() ? 'c/d$i' : 'b/d$i');
        final Mutation mutation = switch (random.nextInt(4)) {
          0 => patchMutation(path, <String, Object?>{'n': batch}),
          1 => deleteMutation(path),
          _ => setMutation(path, <String, Object?>{'n': batch % 7}),
        };
        await persistence.runTransaction('save', () {
          return cache.saveOverlays(batch, <DocumentKey, Mutation>{
            mutation.key: mutation,
          });
        });
      }

      String describe(CollectionOverlays overlays) => <String>[
        for (final MapEntry<DocumentKey, Overlay> e
            in overlays.overlays.entries)
          '${e.key} overlay ${e.value.largestBatchId} ${e.value.mutation}',
        for (final MapEntry<DocumentKey, Document> e
            in overlays.documents.entries)
          '${e.key} document ${e.value}',
        for (final String id in overlays.hiddenIds) 'hidden $id',
      ].sorted().join('\n');

      final Timestamp now = Timestamp.now();
      for (final Query q in <Query>[
        query('c'),
        query('c').filter(filter('n', '>=', 3)),
        query('b').filter(filter('n', '==', 1)),
        query('none'),
      ]) {
        final String expected = await persistence.runTransactionAndReturn(
          'split',
          () async => describe(
            CollectionOverlays.split(
              await cache.getOverlaysForCollection(q.path, -1),
              q,
              now,
            ),
          ),
        );
        for (final int pageSize in <int>[1, 3, 1000]) {
          SQLiteDocumentOverlayCache.collectionPageSize = pageSize;
          expect(
            await persistence.runTransactionAndReturn(
              'paged',
              () async =>
                  describe(await cache.getOverlaysForCollectionQuery(q, now)),
            ),
            expected,
            reason: '$q $pageSize',
          );
        }
      }
    },
  );
}
