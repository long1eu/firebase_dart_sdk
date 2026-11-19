// Reads from a cache of acknowledged documents, in the browser, for docs/spikes/cache_read_profile.md ("In the
// browser"). The page of the same four cases as `tool/bench/cache_read_profile_bench.dart`, through the public API.
// Run through run.dart (`dart run.dart read --port=8397 --docs=20000`), which needs a Firestore emulator.
//
// read.html?p=read&kind=engine|sqlite-idb|sqlite-opfs&n=N&port=P&phase=load|seed|measure&tag=T
//
// load     once: writes N documents `rb/d0000000...` to the emulator (project demo-readbench) with a memory cache.
//          Shape as the VM bench: a = i % 100, order = random integer, payload = 200 characters.
// seed     a client on a new, empty cache of `kind` reads the collection from the server (`get`, in 100 queries by `a`), so that every
//          document is in the cache as acknowledged by the backend, with no pending write. Then terminates.
// measure  a new page load (a fresh client on the stored cache), network disabled: opens and reads one document,
//          then for each case one first read (kept apart) and [reps] timed reads; the result is their median.
//            point  one document by key (per document, over 100 documents of a random order)
//            whole  the collection
//            eq     a == 7, no index
//            ord    orderBy(order desc).limit(20), no index
//          Then terminates and deletes the origin's databases and OPFS files.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart/indexeddb_cache.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

double now() => web.window.performance.now();

const int batchSize = 500;
const int reps = 5;
const String project = 'demo-readbench';
final String payload = 'x' * 200;

String docId(int i) => 'd${i.toString().padLeft(7, '0')}';

Map<String, Object?> data(int i, Random random) => <String, Object?>{
  'a': i % 100,
  'order': random.nextInt(1 << 30),
  'payload': payload,
};

FirebaseFirestore open(
  String kind,
  String tag,
  int port, {
  required bool memory,
}) {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(apiKey: 'key', appId: 'appId', projectId: project),
    name: 'read',
  );
  if (memory) {
    return FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(
        cacheSettings: const MemoryCacheSettings(),
      ).withEmulator('127.0.0.1', port),
    );
  }
  if (kind == 'engine') {
    return FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(
        cacheSettings: indexedDbCacheSettings(),
      ).withEmulator('127.0.0.1', port),
    );
  }
  return FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: PersistentCacheSettings(),
    ).withEmulator('127.0.0.1', port),
    openDatabase: sqliteWebOpener(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      opfsWorker: kind == 'sqlite-opfs'
          ? Uri.parse('sqlite_opfs_worker.js')
          : null,
      storagePrefix: 'read-$tag',
    ),
  );
}

const GetOptions fromCache = GetOptions(source: Source.cache);

Future<void> load(int total, int port, Map<String, Object?> result) async {
  final double start = now();
  final FirebaseFirestore firestore = open(
    'engine',
    'load',
    port,
    memory: true,
  );
  final Random random = Random(42);
  for (int from = 0; from < total; from += batchSize) {
    final WriteBatch batch = firestore.batch();
    for (int i = from; i < min(from + batchSize, total); i++) {
      batch.set(firestore.doc('rb/${docId(i)}'), data(i, random));
    }
    await batch.commit();
  }
  result['load'] = now() - start;
  await firestore.terminate();
}

Future<void> seed(
  String kind,
  String tag,
  int port,
  Map<String, Object?> result,
) async {
  final double start = now();
  final FirebaseFirestore firestore = open(kind, tag, port, memory: false);
  // One `get` of 20,000 documents overflows the emulator's WebChannel back channel (10,001 pending messages), so
  // the collection is read in 100 queries of the 200 documents of one `a` (no cache index is configured, so the
  // cases below are unaffected).
  int size = 0;
  for (int a = 0; a < 100; a++) {
    final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
        .collection('rb')
        .where('a', isEqualTo: a)
        .get();
    size += snapshot.size;
  }
  result['seed'] = now() - start;
  result['size'] = size;
  result['pendingWrites'] = await firestore.getPendingWriteCount();
  await firestore.terminate();
}

double median(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  final int n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

Future<void> measure(
  String kind,
  String tag,
  int total,
  int port,
  Map<String, Object?> result,
) async {
  final Map<String, Object?> sizes = <String, Object?>{};
  result['sizes'] = sizes;

  double t = now();
  final FirebaseFirestore firestore = open(kind, tag, port, memory: false);
  await firestore.disableNetwork();
  final DocumentSnapshot<Map<String, Object?>> first = await firestore
      .doc('rb/${docId(total ~/ 2)}')
      .get(fromCache);
  result['open_first_read'] = now() - t;
  sizes['open_first_read'] = first.exists ? 1 : 0;

  final CollectionReference<Map<String, Object?>> collection = firestore
      .collection('rb');
  final Random random = Random(7);
  const int pointReads = 100;
  final Map<String, Future<int> Function()> cases =
      <String, Future<int> Function()>{
        'point': () async {
          int found = 0;
          for (int i = 0; i < pointReads; i++) {
            final DocumentSnapshot<Map<String, Object?>> doc = await firestore
                .doc('rb/${docId(random.nextInt(total))}')
                .get(fromCache);
            if (doc.exists) found++;
          }
          return found;
        },
        'whole': () async => (await collection.get(fromCache)).size,
        'eq': () async =>
            (await collection.where('a', isEqualTo: 7).get(fromCache)).size,
        'ord': () async =>
            (await collection
                    .orderBy('order', descending: true)
                    .limit(20)
                    .get(fromCache))
                .size,
      };
  for (final MapEntry<String, Future<int> Function()> entry in cases.entries) {
    final double divisor = entry.key == 'point' ? pointReads.toDouble() : 1;
    t = now();
    sizes[entry.key] = await entry.value();
    result['first_${entry.key}'] = (now() - t) / divisor;
    final List<double> times = <double>[];
    for (int r = 0; r < reps; r++) {
      t = now();
      final int size = await entry.value();
      times.add((now() - t) / divisor);
      if (size != sizes[entry.key]) sizes['${entry.key}_changed'] = size;
    }
    result['read_${entry.key}'] = median(times);
  }
  await firestore.terminate();
}

Future<void> wipe() async {
  try {
    final JSArray<web.IDBDatabaseInfo> databases = await web.window.indexedDB
        .databases()
        .toDart;
    for (final web.IDBDatabaseInfo info in databases.toDart) {
      final web.IDBOpenDBRequest request = web.window.indexedDB.deleteDatabase(
        info.name,
      );
      final Completer<void> done = Completer<void>();
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.complete()).toJS;
      request.onblocked = ((web.Event _) => done.complete()).toJS;
      await done.future;
    }
  } catch (_) {}
  try {
    final web.FileSystemDirectoryHandle root = await web
        .window
        .navigator
        .storage
        .getDirectory()
        .toDart;
    final List<String> names = <String>[];
    final JSObject iterator = root.callMethod<JSObject>('keys'.toJS);
    while (true) {
      final JSObject next = await iterator
          .callMethod<JSPromise<JSObject>>('next'.toJS)
          .toDart;
      if ((next['done'] as JSBoolean?)?.toDart ?? true) break;
      names.add((next['value']! as JSString).toDart);
    }
    for (final String name in names) {
      await root
          .removeEntry(name, web.FileSystemRemoveOptions(recursive: true))
          .toDart;
    }
  } catch (_) {}
}

Future<void> main() async {
  final Map<String, String> query = Uri.base.queryParameters;
  final String kind = query['kind'] ?? 'engine';
  final String phase = query['phase'] ?? 'measure';
  final int total = int.parse(query['n'] ?? '20000');
  final int port = int.parse(query['port'] ?? '8397');
  final String tag = query['tag'] ?? 'local';
  final Map<String, Object?> result = <String, Object?>{
    'page': 'read',
    'kind': kind,
    'phase': phase,
    'n': total,
    'compiler': query['c'],
    'userAgent': web.window.navigator.userAgent,
  };
  try {
    if (phase == 'load') {
      await load(total, port, result);
    } else if (phase == 'seed') {
      await wipe();
      await seed(kind, tag, port, result);
    } else {
      await measure(kind, tag, total, port, result);
    }
  } catch (e, s) {
    result['error'] = '$e\n$s';
  }
  if (phase == 'measure') await wipe();
  web.console.log(jsonEncode(result).toJS);
  final web.Response response = await web.window
      .fetch(
        '/result'.toJS,
        web.RequestInit(method: 'POST', body: jsonEncode(result).toJS),
      )
      .toDart;
  final String next = (await response.text().toDart).toDart;
  if (next.isNotEmpty) {
    web.window.location.href = next;
  }
}
