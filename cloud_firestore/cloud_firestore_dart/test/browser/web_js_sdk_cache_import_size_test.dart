// importJsSdkCache on a large JS database: 5,000 pending writes and 20,000 cached documents. The rows are HAND-BUILT
// copies of rows the real JS SDK wrote (a set of js_sdk_cache_fixtures/writes.json, a document of
// js_sdk_cache_fixture.json), under other names. Prints the times and the JS heap (Chrome's performance.memory, which
// counts the objects of dart2wasm too) of each step; checks that the import ends, imports everything and that this
// SDK then sends every write.
//
//   FIRESTORE_EMULATOR_PORT=8404 tool/test_browser.sh both test/browser/web_js_sdk_cache_import_size_test.dart

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'js_sdk_cache_import_util.dart';

const String project = 'demo-jsimport-size';
const int writes = 5000;
const int documents = 20000;

/// The JS heap in MB, or null outside Chrome.
double? heapMb() {
  final JSObject? memory = web.window.performance.getProperty<JSObject?>(
    'memory'.toJS,
  );
  final JSNumber? used = memory?.getProperty<JSNumber?>('usedJSHeapSize'.toJS);
  return used == null ? null : used.toDartDouble / (1024 * 1024);
}

/// Replaces [from] by [to] in every string of [json].
Object? rename(Object? json, String from, String to) => switch (json) {
  final String s => s.replaceAll(from, to),
  final Map<Object?, Object?> m => <String, Object?>{
    for (final MapEntry<Object?, Object?> e in m.entries)
      e.key! as String: rename(e.value, from, to),
  },
  final List<Object?> l => <Object?>[
    for (final Object? e in l) rename(e, from, to),
  ],
  _ => json,
};

/// Writes the large JS database (see the header) as the database of a new JS app, and returns the name of that app.
/// The rows are built here, so that they are garbage once written.
Future<String> loadLargeJsDatabase() async {
  // A set of one document, as the JS SDK wrote it, for every write; a cached document for every document.
  final Json source = await fixture('writes');
  final Json set = records(source, 'mutations').firstWhere((Json row) {
    final List<Object?> batch = row['mutations']! as List<Object?>;
    final Map<Object?, Object?> write = batch.first! as Map<Object?, Object?>;
    return batch.length == 1 &&
        write['update'] is Map &&
        !write.containsKey('updateMask') &&
        jsonPath(row).endsWith('/docs/order');
  });
  final Json legacy = await fixture('legacy');
  final Json cached = records(
    legacy,
    'remoteDocumentsV14',
  ).firstWhere((Json row) => row['documentId'] == 'cached1');
  final Json dump = await fixture('writes');
  final String setPath = jsonPath(set).split('/documents/').last;
  for (final Object? s in dump['stores']! as List<Object?>) {
    final Json store = (s! as Map<Object?, Object?>).cast();
    switch (store['name']) {
      case 'mutations':
        store['records'] = <Object?>[
          for (int i = 1; i <= writes; i++)
            <String, Object?>{
              'key': i,
              'value': <String, Object?>{
                ...(rename(set, setPath, 'big/w$i')! as Json),
                'batchId': i,
                'localWriteTimeMs': 1700000000000 + i,
              },
            },
        ];
      case 'documentMutations':
        store['records'] = <Object?>[
          for (int i = 1; i <= writes; i++)
            <String, Object?>{
              'key': <Object?>['', 'big\u0001\u0001w$i\u0001\u0001', i],
              'value': <String, Object?>{},
            },
        ];
      case 'documentOverlays':
        store['records'] = <Object?>[];
      case 'remoteDocumentsV14':
        store['records'] = <Object?>[
          for (int i = 0; i < documents; i++)
            <String, Object?>{
              'key': null,
              'value': <String, Object?>{
                ...(rename(
                      cached,
                      'demo-idb/databases/(default)/documents/items/cached1',
                      '$project/databases/(default)/documents/cached/d$i',
                    )!
                    as Json),
                'collectionGroup': 'cached',
                'documentId': 'd$i',
              },
            },
        ];
    }
  }
  await clearProject(project);
  return loadAsJsApp(
    rename(dump, 'demo-jsimport/', '$project/')! as Json,
    projectId: project,
  );
}

void main() {
  test(
    '5,000 pending writes and 20,000 documents',
    () async {
      final String? skip = await unavailable(Destination.sqliteIndexedDb);
      if (skip != null) {
        markTestSkipped(skip);
        return;
      }
      final Stopwatch watch = Stopwatch()..start();
      void report(String step) {
        print(
          '$step: ${watch.elapsedMilliseconds} ms, JS heap ${heapMb()?.toStringAsFixed(1)} MB',
        );
        watch.reset();
      }

      final String jsApp = await loadLargeJsDatabase();
      final String dbName = jsDatabaseName(jsApp, project);
      expect(await jsStoreCounts(dbName), <String, int>{
        'version': 18,
        'mutations': writes,
        'documentMutations': writes,
        'documentOverlays': 0,
        'remoteDocumentsV14': documents,
      });
      report('JS database written');

      final ImportClient c = await openClient(
        projectId: project,
        destination: Destination.sqliteIndexedDb,
        appName: uniqueName('dart-size'),
      );
      final FirebaseFirestore firestore = c.firestore;
      await firestore.disableNetwork();
      report('client started');
      final JsSdkCacheImportResult result = await importJsSdkCache(
        firestore,
        jsAppName: jsApp,
      );
      report('imported');
      expect(result.batches, writes);
      expect(result.documents, documents);
      expect(await firestore.getPendingWriteCount(), writes);
      expect(await jsStoreCounts(dbName), <String, int>{
        'version': 18,
        'mutations': 0,
        'documentMutations': 0,
        'documentOverlays': 0,
        'remoteDocumentsV14': documents,
      });
      expect(
        (await firestore
                .collection('cached')
                .get(const GetOptions(source: Source.cache)))
            .size,
        documents,
      );
      report('read the documents from the cache');
      expect(
        (await importJsSdkCache(firestore, jsAppName: jsApp)).status,
        JsSdkCacheImportStatus.nothingToImport,
      );
      report('second call');

      await firestore.enableNetwork();
      await firestore.waitForPendingWrites();
      report('sent');
      expect(await firestore.getPendingWriteCount(), 0);
      final Json backend = await readBackend(project, <String>[
        'big/w1',
        'big/w$writes',
      ]);
      expect(backend['big/w1'], isNotNull);
      expect(backend['big/w$writes'], isNotNull);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

/// The name of the document the single write of [row] writes.
String jsonPath(Json row) {
  final Map<Object?, Object?> write =
      (row['mutations']! as List<Object?>).first! as Map<Object?, Object?>;
  final Object? update = write['update'];
  return update is Map ? update['name']! as String : write['delete']! as String;
}
