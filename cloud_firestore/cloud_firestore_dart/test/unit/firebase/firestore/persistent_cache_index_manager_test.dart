// The public API of the persistent cache indexes, on an instance that never reaches a backend: the cases of
// persistent_cache_index_manager.test.ts of the JS SDK and of IndexingTest of the Android SDK, plus checks of what the
// SDK does inside (which upstream cannot observe: "TODO(b/296100693) Add testing hooks").

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../util/index_helpers.dart';
import '../../../util/test_util.dart' show doc, field, version;
import 'clear_persistence_test.dart' show newApp, offlineSettings, openFixed;
import 'local/mock/database_mock.dart';

// ignore_for_file: deprecated_member_use_from_same_package

void main() {
  int appCounter = 0;

  Future<Firestore> open({bool persistent = true}) async {
    final FirebaseApp app = newApp('persistentCacheIndex${appCounter++}');
    addTearDown(app.delete);
    final String dbName = 'cache-index-${const Uuid().v4()}.db';
    addTearDown(() => DatabaseMock.deleteDatabaseFiles(dbName));
    final Firestore firestore = await Firestore.instanceFor(
      app: app,
      settings: offlineSettings,
      openDatabase: persistent ? openFixed(dbName) : null,
    );
    addTearDown(firestore.terminate);
    return firestore;
  }

  /// Puts [count] documents of `coll` into the cache as if the backend had sent them (the instance is offline); the
  /// first [matching] have `match: true`. The automatic index creation only looks at cached documents of the
  /// backend, not at pending writes.
  Future<void> writeDocs(Firestore firestore, int count, int matching) {
    final Persistence persistence = firestore.client.persistence;
    return persistence.runTransaction('seed the cache', () async {
      for (int i = 0; i < count; i++) {
        await persistence.remoteDocumentCache.add(
          doc('coll/doc${i.toString().padLeft(3, '0')}', 1, <String, Object?>{
            'match': i < matching,
            'n': i,
          }),
          version(1),
        );
      }
    });
  }

  Future<List<String>> matchingIds(Firestore firestore) async {
    final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
        .collection('coll')
        .whereEqualTo('match', true)
        .get(Source.cache);
    return snapshot.docs
        .map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id)
        .toList();
  }

  List<FieldIndex> indexes(Firestore firestore) =>
      firestore.client.localStore.getFieldIndexes();

  final Matcher throwsTerminated = throwsA(
    isA<FirestoreError>().having(
      (FirestoreError e) => e.code,
      'code',
      FirestoreErrorCode.failedPrecondition,
    ),
  );

  group('persistentCacheIndexManager', () {
    test('is non-null if, and only if, the persistent cache is used', () async {
      expect((await open()).persistentCacheIndexManager, isNotNull);
      expect(
        (await open(persistent: false)).persistentCacheIndexManager,
        isNull,
      );
    });

    test('always returns the same object', () async {
      final Firestore firestore = await open();
      expect(
        identical(
          firestore.persistentCacheIndexManager,
          firestore.persistentCacheIndexManager,
        ),
        isTrue,
      );
    });
  });

  group('enable/disable persistent index auto creation', () {
    test('enable on new instance should succeed', () async {
      await (await open()).persistentCacheIndexManager!
          .enableIndexAutoCreation();
    });

    test('disable on new instance should succeed', () async {
      await (await open()).persistentCacheIndexManager!
          .disableIndexAutoCreation();
    });

    test('enable when already enabled should succeed', () async {
      final PersistentCacheIndexManager manager =
          (await open()).persistentCacheIndexManager!;
      await manager.enableIndexAutoCreation();
      await manager.enableIndexAutoCreation();
    });

    test('disable when already disabled should succeed', () async {
      final PersistentCacheIndexManager manager =
          (await open()).persistentCacheIndexManager!;
      await manager.disableIndexAutoCreation();
      await manager.disableIndexAutoCreation();
    });

    // testAutoIndexCreationAfterFailsTermination (Android)
    test('enabling, disabling and deleting after terminate() fail', () async {
      final Firestore firestore = await open();
      final PersistentCacheIndexManager manager =
          firestore.persistentCacheIndexManager!;
      await firestore.terminate();

      await expectLater(manager.enableIndexAutoCreation(), throwsTerminated);
      await expectLater(manager.disableIndexAutoCreation(), throwsTerminated);
      await expectLater(manager.deleteAllIndexes(), throwsTerminated);
    });

    // testAutoIndexCreationSetSuccessfully (Android): the results do not depend on the indexes.
    test(
      'query results are the same in every state of auto creation',
      () async {
        final Firestore firestore = await open();
        final PersistentCacheIndexManager manager =
            firestore.persistentCacheIndexManager!;
        await writeDocs(firestore, 3, 1);
        expect(await matchingIds(firestore), <String>['doc000']);

        await manager.enableIndexAutoCreation();
        expect(await matchingIds(firestore), <String>['doc000']);

        await manager.disableIndexAutoCreation();
        expect(await matchingIds(firestore), <String>['doc000']);

        await manager.deleteAllIndexes();
        expect(await matchingIds(firestore), <String>['doc000']);
      },
    );

    test('query returns correct results when index is auto-created', () async {
      final Firestore firestore = await open();
      await firestore.persistentCacheIndexManager!.enableIndexAutoCreation();
      // More than the 100 documents below which no index is considered, and few enough matches (less than half).
      await writeDocs(firestore, 120, 3);
      final List<String> expected = <String>['doc000', 'doc001', 'doc002'];

      expect(indexes(firestore), isEmpty);
      // The scan finds that an index would have helped and creates it.
      expect(await matchingIds(firestore), expected);
      final List<FieldIndex> created = indexes(firestore);
      expect(created, hasLength(1));
      expect(created.single.collectionGroup, 'coll');
      expect(created.single.segments, <IndexSegment>[
        IndexSegment(field('match'), SegmentKind.ascending),
      ]);

      // Not filled yet, partly filled, and filled: always the same result.
      expect(await matchingIds(firestore), expected);
      expect(await firestore.client.backfillIndexes(), 50);
      expect(await matchingIds(firestore), expected);
      while (await firestore.client.backfillIndexes() > 0) {}
      expect(await matchingIds(firestore), expected);

      // A write after the backfill is part of the result too.
      firestore.doc('coll/zzz').set(<String, Object?>{'match': true}).ignore();
      expect(await matchingIds(firestore), <String>[...expected, 'zzz']);
    });

    test('no index is created for a small collection, a query that matches '
        'most documents, or when auto creation is off', () async {
      final Firestore firestore = await open();
      final PersistentCacheIndexManager manager =
          firestore.persistentCacheIndexManager!;

      // Off (the default): a query that would qualify creates nothing.
      await writeDocs(firestore, 120, 3);
      await matchingIds(firestore);
      expect(indexes(firestore), isEmpty);

      await manager.enableIndexAutoCreation();
      // Most documents match: reading them through an index would cost more than the scan.
      final QuerySnapshot<Map<String, Object?>> most = await firestore
          .collection('coll')
          .whereGreaterThanOrEqualTo('n', 10)
          .get(Source.cache);
      expect(most.docs, hasLength(110));
      expect(indexes(firestore), isEmpty);

      // A collection below 100 documents.
      final Persistence persistence = firestore.client.persistence;
      await persistence.runTransaction('seed the cache', () async {
        for (final String id in <String>['a', 'b', 'c']) {
          await persistence.remoteDocumentCache.add(
            doc('small/$id', 1, <String, Object?>{'match': id == 'a'}),
            version(1),
          );
        }
      });
      final QuerySnapshot<Map<String, Object?>> small = await firestore
          .collection('small')
          .whereEqualTo('match', true)
          .get(Source.cache);
      expect(small.docs, hasLength(1));
      expect(indexes(firestore), isEmpty);

      // Disabled again: nothing is created, an existing index would be kept.
      await manager.disableIndexAutoCreation();
      await matchingIds(firestore);
      expect(indexes(firestore), isEmpty);
    });

    test('pending writes do not count as scanned documents', () async {
      final Firestore firestore = await open();
      await firestore.persistentCacheIndexManager!.enableIndexAutoCreation();
      for (int i = 0; i < 120; i++) {
        firestore.doc('coll/doc$i').set(<String, Object?>{
          'match': i < 3,
        }).ignore();
      }
      expect(await matchingIds(firestore), hasLength(3));
      // As upstream: only the cached documents of the backend are counted, and there are none.
      expect(indexes(firestore), isEmpty);
    });

    test('an index created automatically keeps being used after auto '
        'creation is turned off', () async {
      final Firestore firestore = await open();
      final PersistentCacheIndexManager manager =
          firestore.persistentCacheIndexManager!;
      await manager.enableIndexAutoCreation();
      await writeDocs(firestore, 120, 3);
      await matchingIds(firestore);
      expect(indexes(firestore), hasLength(1));

      await manager.disableIndexAutoCreation();
      while (await firestore.client.backfillIndexes() > 0) {}
      expect(indexes(firestore), hasLength(1));
      expect(await matchingIds(firestore), <String>[
        'doc000',
        'doc001',
        'doc002',
      ]);
    });
  });

  group('delete all persistent cache indexes', () {
    test('deleteAllIndexes() on new instance should succeed', () async {
      await (await open()).persistentCacheIndexManager!.deleteAllIndexes();
    });

    test('deleteAllIndexes() should be successful when auto-indexing is '
        'enabled', () async {
      final PersistentCacheIndexManager manager =
          (await open()).persistentCacheIndexManager!;
      await manager.enableIndexAutoCreation();
      await manager.deleteAllIndexes();
    });

    test('deleteAllIndexes() should be successful when auto-indexing is '
        'disabled', () async {
      final PersistentCacheIndexManager manager =
          (await open()).persistentCacheIndexManager!;
      await manager.enableIndexAutoCreation();
      await manager.disableIndexAutoCreation();
      await manager.deleteAllIndexes();
    });

    test('query returns correct results when auto-created index has been '
        'deleted', () async {
      final Firestore firestore = await open();
      final PersistentCacheIndexManager manager =
          firestore.persistentCacheIndexManager!;
      await manager.enableIndexAutoCreation();
      await writeDocs(firestore, 120, 3);
      final List<String> expected = <String>['doc000', 'doc001', 'doc002'];
      expect(await matchingIds(firestore), expected);
      while (await firestore.client.backfillIndexes() > 0) {}
      expect(indexes(firestore), hasLength(1));

      // Turn auto creation off first, or the next scan creates the index again.
      await manager.disableIndexAutoCreation();
      await manager.deleteAllIndexes();
      expect(indexes(firestore), isEmpty);
      expect(await matchingIds(firestore), expected);
      expect(indexes(firestore), isEmpty);
    });

    test('also deletes the indexes of setIndexConfiguration', () async {
      final Firestore firestore = await open();
      await firestore.setIndexConfiguration(
        '{"indexes": [{"collectionGroup": "coll", "fields": '
        '[{"fieldPath": "match", "order": "ASCENDING"}]}]}',
      );
      expect(indexes(firestore), hasLength(1));
      await firestore.persistentCacheIndexManager!.deleteAllIndexes();
      expect(indexes(firestore), isEmpty);
    });
  });

  group('setIndexConfiguration', () {
    const String restaurants = '''
{
  "indexes": [
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "price", "order": "ASCENDING"},
        {"fieldPath": "avgRating", "order": "DESCENDING"}
      ]
    },
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {"fieldPath": "price", "order": "ASCENDING"}
      ]
    }
  ],
  "fieldOverrides": []
}''';

    // testCanConfigureIndexes (Android)
    test('configures the indexes of the definition', () async {
      final Firestore firestore = await open();
      await firestore.setIndexConfiguration(restaurants);

      final List<FieldIndex> configured = indexes(firestore)
        ..sort(FieldIndex.semanticCompare);
      expect(configured, hasLength(2));
      expect(
        FieldIndex.semanticCompare(
          configured[0],
          fieldIndex(
            'restaurants',
            fieldsAndKinds: <Object>['price', SegmentKind.ascending],
          ),
        ),
        0,
      );
      expect(
        FieldIndex.semanticCompare(
          configured[1],
          fieldIndex(
            'restaurants',
            fieldsAndKinds: <Object>[
              'price',
              SegmentKind.ascending,
              'avgRating',
              SegmentKind.descending,
            ],
          ),
        ),
        0,
      );
    });

    test(
      'replaces the configuration and keeps the indexes that stay',
      () async {
        final Firestore firestore = await open();
        await firestore.setIndexConfiguration(restaurants);
        final Set<int> before = indexes(
          firestore,
        ).map((FieldIndex i) => i.indexId).toSet();

        await firestore.setIndexConfiguration(
          '{"indexes": [{"collectionGroup": "restaurants", "fields": '
          '[{"fieldPath": "price", "order": "ASCENDING"}]}, '
          '{"collectionGroup": "cities", "fields": '
          '[{"fieldPath": "tags", "arrayConfig": "CONTAINS"}]}]}',
        );
        final List<FieldIndex> after = indexes(firestore);
        expect(after.map((FieldIndex i) => i.collectionGroup).toSet(), <String>{
          'restaurants',
          'cities',
        });
        expect(after, hasLength(2));
        // The single-field index on price is the same index as before.
        final FieldIndex price = after.singleWhere(
          (FieldIndex i) => i.collectionGroup == 'restaurants',
        );
        expect(before, contains(price.indexId));

        await firestore.setIndexConfiguration('{"indexes": []}');
        expect(indexes(firestore), isEmpty);
      },
    );

    // testBadJsonDoesNotCrashClient / testBadIndexDoesNotCrashClient (Android)
    test('a bad definition fails and does not break the instance', () async {
      final Firestore firestore = await open();
      await expectLater(
        firestore.setIndexConfiguration('{,'),
        throwsArgumentError,
      );
      await expectLater(
        firestore.setIndexConfiguration(
          '{"indexes": [{"collectionGroup": "restaurants", "fields": '
          '[{"fieldPath": "price", "order": "INVALID" ,]}]}',
        ),
        throwsArgumentError,
      );
      expect(indexes(firestore), isEmpty);
      await firestore.setIndexConfiguration(restaurants);
      expect(indexes(firestore), hasLength(2));
    });

    test('fails without the persistent cache', () async {
      final Firestore firestore = await open(persistent: false);
      await expectLater(
        firestore.setIndexConfiguration(restaurants),
        throwsStateError,
      );
    });

    test('fails after terminate()', () async {
      final Firestore firestore = await open();
      await firestore.terminate();
      await expectLater(
        firestore.setIndexConfiguration(restaurants),
        throwsTerminated,
      );
    });

    test('a configured index serves cache queries once it is filled', () async {
      final Firestore firestore = await open();
      await firestore.setIndexConfiguration(
        '{"indexes": [{"collectionGroup": "coll", "fields": '
        '[{"fieldPath": "match", "order": "ASCENDING"}]}]}',
      );
      await writeDocs(firestore, 60, 2);
      expect(await matchingIds(firestore), <String>['doc000', 'doc001']);
      expect(await firestore.client.backfillIndexes(), 50);
      expect(await matchingIds(firestore), <String>['doc000', 'doc001']);
      expect(await firestore.client.backfillIndexes(), 10);
      expect(await firestore.client.backfillIndexes(), 0);
      expect(await matchingIds(firestore), <String>['doc000', 'doc001']);
    });
  });
}
