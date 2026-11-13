// Ports of the Android IndexingTest and the JS index_configuration.test.ts and
// persistent_cache_index_manager.test.ts (see
// notes/parity/integration_test_map.md).

// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart'
    show autoId;
import 'package:test/test.dart';

import '../../../util/integration_test_util.dart';

const String _validConfiguration = '''
{
  "indexes": [
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "price",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "avgRating",
          "order": "DESCENDING"
        }
      ]
    },
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "price",
          "order": "ASCENDING"
        }
      ]
    }
  ],
  "fieldOverrides": []
}''';

void main() {
  IntegrationTestUtil.currentDatabasePath = 'integration/indexing';

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await IntegrationTestUtil.tearDown();
  });

  final Map<String, Map<String, Object?>> matchDocs =
      <String, Map<String, Object?>>{
        'a': <String, Object?>{'match': true},
        'b': <String, Object?>{'match': false},
        'c': <String, Object?>{'match': false},
      };

  Matcher throwsTerminated() => throwsA(
    isA<FirestoreError>().having(
      (FirestoreError e) => e.message,
      'message',
      contains('The client has already been terminated'),
    ),
  );

  test('testCanConfigureIndexes', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    await db.setIndexConfiguration(_validConfiguration);
  });

  test('testBadJsonDoesNotCrashClient', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    await expectLater(db.setIndexConfiguration('{,'), throwsArgumentError);
    // The client still works.
    await db
        .collection('a')
        .doc('b')
        .get(Source.cache)
        .then<void>(
          (_) {},
          onError: (Object e) => expect(e, isA<FirestoreError>()),
        );
    await db.setIndexConfiguration(_validConfiguration);
  });

  test('testBadIndexDoesNotCrashClient', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    await expectLater(
      db.setIndexConfiguration('''
{
  "indexes": [
    {
      "collectionGroup": "restaurants",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "price",
          "order": "INVALID"
        ,
      ]
    }
  ],
  "fieldOverrides": []
}'''),
      throwsArgumentError,
    );
    // The client still works.
    await db.setIndexConfiguration(_validConfiguration);
  });

  Future<void> checkAutoIndexCreation(Firestore db) async {
    final CollectionReference collection = db.collection('coll${autoId()}');
    await IntegrationTestUtil.writeAllDocs(collection, matchDocs);
    final Query query = collection.where('match', isEqualTo: true);

    expect((await query.get()).length, 1);
    final PersistentCacheIndexManager manager = db.persistentCacheIndexManager!;

    await manager.enableIndexAutoCreation();
    expect((await query.get(Source.cache)).length, 1);

    await manager.disableIndexAutoCreation();
    expect((await query.get(Source.cache)).length, 1);

    await manager.deleteAllIndexes();
    expect((await query.get(Source.cache)).length, 1);
  }

  test('testAutoIndexCreationSetSuccessfully', () async {
    // Persistent cache (explicit).
    final FirestoreSettings base = IntegrationTestUtil.newTestSettings();
    final Firestore db = await IntegrationTestUtil.testFirestore(
      FirestoreSettings(
        host: base.host,
        port: base.port,
        sslEnabled: base.sslEnabled,
        cacheSettings: PersistentCacheSettings(),
      ),
    );
    await checkAutoIndexCreation(db);
  });

  test('testAutoIndexCreationSetSuccessfullyUsingDefault', () async {
    // Persistent cache (default).
    final Firestore db = await IntegrationTestUtil.testFirestore();
    await checkAutoIndexCreation(db);
  });

  test('enable or disable twice succeeds', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    final PersistentCacheIndexManager manager = db.persistentCacheIndexManager!;
    await manager.enableIndexAutoCreation();
    await manager.enableIndexAutoCreation();
    await manager.enableIndexAutoCreation();
    await manager.disableIndexAutoCreation();
    await manager.disableIndexAutoCreation();
    await manager.disableIndexAutoCreation();
  });

  test('testAutoIndexCreationAfterFailsTermination', () async {
    final Firestore db = await IntegrationTestUtil.testFirestore();
    final PersistentCacheIndexManager manager = db.persistentCacheIndexManager!;
    await db.terminate();

    await expectLater(manager.enableIndexAutoCreation(), throwsTerminated());
    await expectLater(manager.disableIndexAutoCreation(), throwsTerminated());
    await expectLater(manager.deleteAllIndexes(), throwsTerminated());
  });

  test(
    'query results stay correct after the auto-created indexes are deleted',
    () async {
      final Firestore db = await IntegrationTestUtil.testFirestore();
      final CollectionReference collection = db.collection('coll${autoId()}');
      await IntegrationTestUtil.writeAllDocs(
        collection,
        <String, Map<String, Object?>>{
          'match': <String, Object?>{'match': true},
          for (int i = 0; i < 100; i++)
            'other$i': <String, Object?>{'match': false},
        },
      );
      final PersistentCacheIndexManager manager =
          db.persistentCacheIndexManager!;
      await manager.enableIndexAutoCreation();

      // Populate the local cache with the entire collection.
      await collection.get();

      // A query that matches one of the documents: it makes the SDK create an
      // index.
      final Query query = collection.where('match', isEqualTo: true);
      expect((await query.get(Source.cache)).length, 1);

      await manager.deleteAllIndexes();

      // Still the one document (the public API does not tell whether an index
      // is used).
      expect((await query.get(Source.cache)).length, 1);
    },
  );
}
