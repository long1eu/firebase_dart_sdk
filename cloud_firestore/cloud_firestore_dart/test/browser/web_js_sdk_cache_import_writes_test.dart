// importJsSdkCache with every kind of write the JS SDK queues (js_sdk_cache_fixtures/writes.json, written by the real
// JS SDK, see tool/bench/web_idb/js_import/static/fixtures.js), into every kind of cache: after the import this SDK
// sends them, and the backend ends up with exactly what it held when the JS SDK sent the same writes itself (the
// `expected` of the fixture).
//
//   FIRESTORE_EMULATOR_PORT=8404 tool/test_browser.sh both test/browser/web_js_sdk_cache_import_writes_test.dart

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/indexeddb_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:test/test.dart';

import 'js_sdk_cache_import_util.dart';

const String project = 'demo-jsimport';
const GetOptions cache = GetOptions(source: Source.cache);

/// Removes the fields [fields] of docs/values from the writes of [writes] and from [expected].
void withoutFields(Json writes, Json expected, List<String> fields) {
  for (final Json row in records(writes, 'mutations')) {
    for (final Object? write in row['mutations']! as List<Object?>) {
      final Object? update = (write! as Map<Object?, Object?>)['update'];
      if (update is Map && update['fields'] is Map) {
        fields.forEach((update['fields']! as Map<Object?, Object?>).remove);
      }
    }
  }
  fields.forEach((expected['docs/values']! as Map<Object?, Object?>).remove);
}

void main() {
  for (final Destination destination in Destination.values) {
    test(
      'every kind of write reaches the backend as the JS SDK sends it: ${destination.name}',
      () async {
        final String? skip = await unavailable(destination);
        if (skip != null) {
          markTestSkipped(skip);
          return;
        }
        final Json writes = await fixture('writes');
        final Json expected =
            ((writes['expected']! as Json)['open']! as Map<Object?, Object?>)
                .cast();
        if (destination == Destination.indexedDbEngine) {
          // Two bugs of the engine's serializer, whoever writes the values (left to its owners): an empty Bytes value
          // is stored as `{}` and can not be read back ("Unknown value"), and with dart2js a timestamp less than half
          // a millisecond before a whole second is stored one second late (toProto3Json of package:protobuf), the
          // last second of 9999 as 10000, which can not be read back. Without those two values.
          withoutFields(writes, expected, <String>['bEmpty', 'tsMax']);
        }
        await clearProject(project);
        await seedProject(
          project,
          (writes['seed']! as Map<Object?, Object?>).cast(),
        );
        final String jsApp = await loadAsJsApp(writes, projectId: project);
        final ImportClient client = await openClient(
          projectId: project,
          destination: destination,
          appName: uniqueName('dart-writes'),
        );
        final FirebaseFirestore firestore = client.firestore;
        expect(firestore.client.persistence, switch (destination) {
          Destination.memory => isA<MemoryPersistence>(),
          Destination.indexedDbEngine => isA<IndexedDbPersistence>(),
          Destination.sqliteIndexedDb ||
          Destination.sqliteOpfs => isA<SQLitePersistence>(),
          Destination.keyValue => isNot(
            anyOf(isA<SQLitePersistence>(), isA<MemoryPersistence>()),
          ),
        });
        await firestore.disableNetwork();

        final JsSdkCacheImportResult result = await importJsSdkCache(
          firestore,
          jsAppName: jsApp,
          allowMemoryCache: destination == Destination.memory,
        );
        final int batches = records(writes, 'mutations').length;
        expect(result.status, JsSdkCacheImportStatus.imported);
        expect(result.users, 1);
        expect(result.batches, batches);
        expect(await firestore.getPendingWriteCount(), batches);
        // Nothing is left in the JS database.
        expect(
          await jsStoreCounts(jsDatabaseName(jsApp, project)),
          <String, int>{
            'version': 18,
            'mutations': 0,
            'documentMutations': 0,
            'documentOverlays': 0,
            'remoteDocumentsV14': 0,
          },
        );

        // The local view before anything is sent.
        final DocumentSnapshot<Json> order = await firestore
            .doc('docs/order')
            .get(cache);
        expect(order.metadata.hasPendingWrites, isTrue);
        expect(order.data(), <String, Object?>{
          'v': 3,
          'log': <String>['1', '2', '3', '4'],
          'w': 1,
        });
        expect(
          (await firestore.doc('docs/order2').get(cache)).data(),
          <String, Object?>{'again': true},
        );
        final Json values = (await firestore.doc('docs/values').get(cache))
            .data()!;
        expect(values['maxSafe'], 9007199254740991);
        expect((values['nan']! as double).isNaN, isTrue);
        if (destination != Destination.indexedDbEngine) {
          // The engine keeps -0 as 0, as the backend's REST answer does (the comparison below can not tell).
          expect((values['negZero']! as double).isNegative, isTrue);
        }
        expect(values['v'], isA<VectorValue>());
        expect(values['r'], isA<DocumentReference<Json>>());
        expect((values['b']! as Blob).bytes, <int>[0, 1, 2, 254, 255]);

        await firestore.enableNetwork();
        await firestore.waitForPendingWrites();
        expect(await firestore.getPendingWriteCount(), 0);
        await expectBackend(
          project,
          expected,
          referenceProject: writes['referenceProject']! as String,
        );

        // Everything was imported: the JS database can go, and a later import finds none.
        expect(await deleteJsSdkCache(firestore, jsAppName: jsApp), isTrue);
        expect(
          (await importJsSdkCache(firestore, jsAppName: jsApp)).status,
          JsSdkCacheImportStatus.noJsDatabase,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('imported while online: the writes are sent at once', () async {
    final String? skip = await unavailable(Destination.sqliteIndexedDb);
    if (skip != null) {
      markTestSkipped(skip);
      return;
    }
    final Json writes = await fixture('writes');
    await clearProject(project);
    await seedProject(
      project,
      (writes['seed']! as Map<Object?, Object?>).cast(),
    );
    final String jsApp = await loadAsJsApp(writes, projectId: project);
    final ImportClient client = await openClient(
      projectId: project,
      destination: Destination.sqliteIndexedDb,
      appName: uniqueName('dart-online'),
    );
    final JsSdkCacheImportResult result = await importJsSdkCache(
      client.firestore,
      jsAppName: jsApp,
    );
    expect(result.batches, records(writes, 'mutations').length);
    await client.firestore.waitForPendingWrites();
    await expectBackend(
      project,
      ((writes['expected']! as Json)['open']! as Map<Object?, Object?>).cast(),
      referenceProject: writes['referenceProject']! as String,
    );
  });

  test(
    'the IndexedDB engine on the JS database itself: nothing to import, nothing deleted',
    () async {
      final Json writes = await fixture('writes');
      final String jsApp = await loadAsJsApp(writes, projectId: project);
      // The engine of an app with the JS app's name uses the JS database as its cache.
      final ImportClient client = await openClient(
        projectId: project,
        destination: Destination.indexedDbEngine,
        appName: jsApp,
      );
      final FirebaseFirestore firestore = client.firestore;
      await firestore.disableNetwork();
      final int batches = records(writes, 'mutations').length;
      // The engine reads the JS SDK's pending writes as its own.
      expect(await firestore.getPendingWriteCount(), batches);
      final JsSdkCacheImportResult result = await importJsSdkCache(firestore);
      expect(result.status, JsSdkCacheImportStatus.nothingToImport);
      expect(result.batches, 0);
      expect(result.skipped.single, contains('IndexedDbCacheSettings'));
      expect(await deleteJsSdkCache(firestore), isFalse);
      expect(await firestore.getPendingWriteCount(), batches);
      expect(
        (await jsStoreCounts(jsDatabaseName(jsApp, project)))!['mutations'],
        batches,
      );
    },
  );
}
