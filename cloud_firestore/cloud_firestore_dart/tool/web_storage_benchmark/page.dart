// The page of the web storage benchmark (run.dart starts it): fills a
// persistent cache with documents through a bundle, then, after a reload,
// opens it and measures memory and read latency. Reports to the server that
// served it.
//
// Query parameters: `storage` (`indexeddb` or `opfs`), `docs` (count),
// `phase` (`fill`, then `read`).

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
// For `Firestore.initialized`: when the cache is open.
import 'package:cloud_firestore_dart/src/internal_access.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

import '../../example/sqlite_database_web.dart';

const String projectId = 'demo-bench';
const String collection = 'bench';

late final String storage;
late final int docs;

Future<void> main() async {
  final Map<String, String> query = Uri.base.queryParameters;
  storage = query['storage']!;
  docs = int.parse(query['docs']!);
  try {
    if (query['phase'] == 'fill') {
      final Map<String, Object?> filled = await fill();
      await report('filled', filled);
      // The measurements start from a new page, as after a page load.
      web.window.location.replace(
        Uri.base
            .replace(
              queryParameters: <String, String>{...query, 'phase': 'read'},
            )
            .toString(),
      );
    } else {
      await report('result', await read());
    }
  } catch (error, stackTrace) {
    await report('error', <String, Object?>{
      'error': '$error',
      'stack': '$stackTrace',
    });
  }
}

Future<void> report(String kind, Map<String, Object?> body) async {
  await web.window
      .fetch(
        '/$kind'.toJS,
        web.RequestInit(
          method: 'POST',
          body: jsonEncode(<String, Object?>{
            'storage': storage,
            'docs': docs,
            'compiler': const bool.fromEnvironment('dart.tool.dart2wasm')
                ? 'dart2wasm'
                : 'dart2js',
            ...body,
          }).toJS,
        ),
      )
      .toDart;
}

Firestore newClient() {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(
      apiKey: 'demo-key',
      applicationId: '1:1234567890:dart:bench',
      projectId: projectId,
    ),
    name: 'bench',
  );
  return Firestore.instanceFor(
    app: app,
    openDatabase: sqliteWebOpener(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      opfsWorker: storage == 'opfs' ? Uri.parse('sqlite_opfs_worker.js') : null,
    ),
    settings: FirestoreSettings(
      // No eviction: every document stays in the cache.
      cacheSettings: PersistentCacheSettings(
        sizeBytes: FirestoreSettings.cacheSizeUnlimited,
      ),
    ).withEmulator('127.0.0.1', 9),
  );
}

/// About 1 KB of fields per document.
String documentJson(String root, int i) {
  final Random random = Random(i);
  final String text = String.fromCharCodes(
    List<int>.generate(900, (_) => 97 + random.nextInt(26)),
  );
  return '{"document":{"name":"$root/$collection/d$i",'
      '"createTime":{"seconds":1,"nanos":0},'
      '"updateTime":{"seconds":1,"nanos":0},"fields":{'
      '"n":{"integerValue":"$i"},'
      '"title":{"stringValue":"Document number $i"},'
      '"tags":{"arrayValue":{"values":[{"stringValue":"t${i % 7}"},'
      '{"stringValue":"u${i % 13}"}]}},'
      '"text":{"stringValue":"$text"}}}}';
}

/// The bundle, in chunks of 1000 documents.
Stream<List<int>> bundle() async* {
  const String root = 'projects/$projectId/databases/(default)/documents';
  const String readTime = '{"seconds":1000,"nanos":0}';
  Iterable<String> elements(int from, int to) sync* {
    for (int i = from; i < to; i++) {
      yield '{"documentMetadata":{"name":"$root/$collection/d$i",'
          '"readTime":$readTime,"exists":true}}';
      yield documentJson(root, i);
    }
  }

  String chunk(int from, int to) => <String>[
    for (final String element in elements(from, to))
      '${utf8.encode(element).length}$element',
  ].join();

  int totalBytes = 0;
  for (int i = 0; i < docs; i += 1000) {
    totalBytes += utf8.encode(chunk(i, min(i + 1000, docs))).length;
  }
  final String metadata =
      '{"metadata":{"id":"bench","createTime":{"seconds":1001,"nanos":0},'
      '"version":1,"totalDocuments":$docs,"totalBytes":$totalBytes}}';
  yield utf8.encode('${utf8.encode(metadata).length}$metadata');
  for (int i = 0; i < docs; i += 1000) {
    yield utf8.encode(chunk(i, min(i + 1000, docs)));
  }
}

Future<Map<String, Object?>> fill() async {
  final Stopwatch watch = Stopwatch()..start();
  final Firestore firestore = newClient();
  await firestore.initialized;
  await firestore.disableNetwork();
  final LoadBundleTaskProgress progress = await firestore
      .loadBundleStream(bundle())
      .future;
  final int loaded = progress.documentsLoaded;
  await firestore.terminate();
  return <String, Object?>{
    'loaded': loaded,
    'fillMs': watch.elapsedMilliseconds,
  };
}

/// The memory of this page and its workers (JavaScript heaps, array buffers
/// and WebAssembly memories), from `performance.measureUserAgentSpecificMemory`
/// (needs cross-origin isolation, which the server sets up).
Future<Map<String, int>> memory() async {
  final JSObject performance = web.window.performance as JSObject;
  final JSObject result = await performance
      .callMethod<JSPromise<JSObject>>('measureUserAgentSpecificMemory'.toJS)
      .toDart;
  int workers = 0;
  for (final JSObject entry
      in (result['breakdown']! as JSArray<JSObject>).toDart) {
    final List<JSObject> attribution =
        (entry['attribution']! as JSArray<JSObject>).toDart;
    if (attribution.any(
      (JSObject a) =>
          (a['scope'] as JSString?)?.toDart == 'DedicatedWorkerGlobalScope',
    )) {
      workers += (entry['bytes']! as JSNumber).toDartInt;
    }
  }
  return <String, int>{
    'total': (result['bytes']! as JSNumber).toDartInt,
    'workers': workers,
  };
}

double median(List<double> values) {
  final List<double> sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

Future<Map<String, Object?>> read() async {
  final Map<String, int> before = await memory();
  final Stopwatch watch = Stopwatch()..start();
  final Firestore firestore = newClient();
  await firestore.initialized;
  await firestore.disableNetwork();
  final int openMs = watch.elapsedMilliseconds;

  final CollectionReference<Map<String, Object?>> bench = firestore.collection(
    collection,
  );
  watch.reset();
  final DocumentSnapshot<Map<String, Object?>> first = await bench
      .doc('d0')
      .get(Source.cache);
  final int firstReadMs = watch.elapsedMilliseconds;
  if (!first.exists) {
    throw StateError('d0 is not in the cache');
  }

  // Reads of single documents by id, in a random order.
  final Random random = Random(1);
  final List<double> pointMs = <double>[];
  for (int i = 0; i < 200; i++) {
    watch.reset();
    final DocumentSnapshot<Map<String, Object?>> doc = await bench
        .doc('d${random.nextInt(docs)}')
        .get(Source.cache);
    pointMs.add(watch.elapsedMicroseconds / 1000);
    if (!doc.exists) {
      throw StateError('${doc.id} is not in the cache');
    }
  }
  final Map<String, int> open = await memory();

  // A query that the cache answers by scanning the collection.
  watch.reset();
  QuerySnapshot<Map<String, Object?>>? some = await bench
      .whereEqualTo('n', docs ~/ 2)
      .get(Source.cache);
  final int filteredMs = watch.elapsedMilliseconds;
  if (some.docs.length != 1) {
    throw StateError('the filtered query found ${some.docs.length}');
  }
  some = null;

  watch.reset();
  QuerySnapshot<Map<String, Object?>>? all = await bench.get(Source.cache);
  final int scanMs = watch.elapsedMilliseconds;
  if (all.docs.length != docs) {
    throw StateError('the scan found ${all.docs.length} of $docs');
  }
  final Map<String, int> scanned = await memory();
  all = null;

  await firestore.terminate();
  final Map<String, int> closed = await memory();
  final JSObject estimate = await web.window.navigator.storage
      .estimate()
      .toDart;
  return <String, Object?>{
    'openMs': openMs,
    'firstReadMs': firstReadMs,
    'pointMedianMs': median(pointMs),
    'pointMaxMs': pointMs.reduce(max),
    'filteredMs': filteredMs,
    'scanMs': scanMs,
    'memoryBefore': before,
    'memoryOpen': open,
    'memoryAfterScan': scanned,
    'memoryClosed': closed,
    'storageUsage': (estimate['usage'] as JSNumber?)?.toDartDouble,
  };
}
