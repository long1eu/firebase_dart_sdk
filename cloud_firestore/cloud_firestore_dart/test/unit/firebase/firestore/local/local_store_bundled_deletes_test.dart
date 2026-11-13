// ignore_for_file: cascade_invocations

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_store.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// A bundled NoDocument at SnapshotVersion.none (the shape of a manufactured
/// delete, as for a rejected limbo listen) removes the document from the cache
/// instead of storing it, like upstream's populateDocumentChangeBuffer.
void main() {
  final Map<String, Future<Persistence> Function()> persistences =
      <String, Future<Persistence> Function()>{
        'memory': createEagerGCMemoryPersistence,
        'sqlite': createSQLitePersistence,
      };

  persistences.forEach((String name, Future<Persistence> Function() create) {
    group(name, () {
      late Persistence persistence;
      late LocalStore localStore;

      setUp(() async {
        persistence = await create();
        localStore = LocalStore(persistence, User.unauthenticated);
        await localStore.start();
      });

      tearDown(() => persistence.shutdown());

      Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> bundle(
        List<MaybeDocument> docs,
      ) {
        ImmutableSortedMap<DocumentKey, MaybeDocument> map =
            DocumentCollections.emptyMaybeDocumentMap();
        for (final MaybeDocument d in docs) {
          map = map.insert(d.key, d);
        }
        return localStore.applyBundledDocuments(map, 'bundle');
      }

      test('removes a cached document', () async {
        final int target = (await localStore.allocateTarget(
          query('foo').toTarget(),
        )).targetId;
        await localStore.applyRemoteEvent(
          addedRemoteEvent(doc('foo/a', 2, map(<Object>['v', 1])), <int>[
            target,
          ], <int>[]),
        );
        expect(
          await localStore.readDocument(key('foo/a')),
          doc('foo/a', 2, map(<Object>['v', 1])),
        );

        final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
            await bundle(<MaybeDocument>[deletedDoc('foo/a', 0)]);

        expect(changes[key('foo/a')], deletedDoc('foo/a', 0));
        expect(await localStore.readDocument(key('foo/a')), isNull);
      });

      test('does not add a document that was not cached', () async {
        final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
            await bundle(<MaybeDocument>[
              deletedDoc('foo/a', 0),
              doc('foo/b', 1, map(<Object>['v', 1])),
            ]);

        expect(changes[key('foo/a')], deletedDoc('foo/a', 0));
        expect(await localStore.readDocument(key('foo/a')), isNull);
        expect(
          await localStore.readDocument(key('foo/b')),
          doc('foo/b', 1, map(<Object>['v', 1])),
        );
      });

      test('a versioned bundled delete is stored', () async {
        await bundle(<MaybeDocument>[deletedDoc('foo/a', 3)]);
        expect(
          await localStore.readDocument(key('foo/a')),
          deletedDoc('foo/a', 3),
        );
      });
    });
  });
}
