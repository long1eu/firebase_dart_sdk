// The overlays of a collection of the key-value cache: getOverlaysForCollection against a model of the overlays that
// were saved, and getOverlaysForCollectionQuery against the split of the overlays of the collection (the SQLite cache
// has two ways to read them, see sqlite_overlays_for_collection_test.dart).

import 'dart:math';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
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
  test('the overlays of a collection are those that were saved', () async {
    final Persistence persistence = await createKeyValuePersistence();
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
    final List<User> users = <User>[User.unauthenticated, const User('u')];
    // What a user saved last for each document: the batch id and the mutation.
    final Map<User, Map<DocumentKey, (int, Mutation)>> model =
        <User, Map<DocumentKey, (int, Mutation)>>{
          for (final User user in users) user: <DocumentKey, (int, Mutation)>{},
        };
    for (final User user in users) {
      final DocumentOverlayCache cache = persistence.getDocumentOverlayCache(
        user,
      );
      for (int batch = 1; batch <= 120; batch++) {
        final Map<DocumentKey, Mutation> mutations = <DocumentKey, Mutation>{};
        for (int i = 1 + random.nextInt(3); i > 0; i--) {
          final DocumentKey k = key(
            '${collections[random.nextInt(collections.length)]}/d${random.nextInt(40)}',
          );
          mutations[k] = setMutation(k.path.canonicalString, <String, Object?>{
            'n': batch,
          });
        }
        await persistence.runTransaction('save', () {
          return cache.saveOverlays(batch, mutations);
        });
        for (final MapEntry<DocumentKey, Mutation> e in mutations.entries) {
          model[user]![e.key] = (batch, e.value);
        }
      }
    }

    String describe(Iterable<(DocumentKey, int, Object)> overlays) =>
        (overlays
                .map(
                  ((DocumentKey, int, Object) e) => '${e.$1}:${e.$2}:${e.$3}',
                )
                .toList()
              ..sort())
            .join('\n');

    int compared = 0;
    for (final User user in users) {
      final DocumentOverlayCache cache = persistence.getDocumentOverlayCache(
        user,
      );
      for (final String collection in <String>[...collections, 'none']) {
        for (final int since in <int>[-1, 0, 1, 50, 100, 119, 120, 500]) {
          final String actual = await persistence.runTransactionAndReturn(
            'read',
            () async => describe(
              (await cache.getOverlaysForCollection(
                path(collection),
                since,
              )).entries.map(
                (MapEntry<DocumentKey, Overlay> e) =>
                    (e.key, e.value.largestBatchId, e.value.mutation),
              ),
            ),
          );
          final String expected = describe(
            model[user]!.entries
                .where(
                  (MapEntry<DocumentKey, (int, Mutation)> e) =>
                      e.key.path.popLast() == path(collection) &&
                      e.value.$1 > since,
                )
                .map(
                  (MapEntry<DocumentKey, (int, Mutation)> e) =>
                      (e.key, e.value.$1, e.value.$2),
                ),
          );
          expect(actual, expected, reason: '$user $collection $since');
          if (expected.isNotEmpty) {
            compared++;
          }
        }
      }
    }
    expect(compared, greaterThan(40));
  });

  test(
    'the overlays of a collection query are those of the collection, split',
    () async {
      final Persistence persistence = await createKeyValuePersistence();
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
        expect(
          await persistence.runTransactionAndReturn(
            'query',
            () async =>
                describe(await cache.getOverlaysForCollectionQuery(q, now)),
          ),
          expected,
          reason: '$q',
        );
      }
    },
  );
}
