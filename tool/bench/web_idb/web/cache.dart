// Reads over a large cache, through the public SDK API, for the three web caches: the IndexedDB engine
// (IndexedDbCacheSettings, experimental) and the SQLite cache (PersistentCacheSettings) on IndexedDB and on OPFS.
// Run through run.dart (`dart run.dart cache --sizes=2000,20000`).
//
// cache.html?kind=engine|sqlite-idb|sqlite-opfs&n=N&phase=seed|measure&tag=T
//
// seed     opens an empty cache with the network disabled and writes N documents as pending writes, in batches
//          of 500 (WriteBatch.commit, not awaited: a commit completes when the backend acknowledges it). 80% go
//          to the collection `big` (big/d00000...), 20% to subcollections of 10 documents each under the first
//          documents of `big` (big/d00000/small/s0...). Each document is about 300 bytes: n (int), group
//          (g00..g99, n % 100) and text. Timed until a cache read of the last document written returns, which
//          comes after every write in the client's queue. Then the client is terminated.
// measure  a new page load (a fresh client on the stored cache): open and read one document from the cache,
//          100 single document reads, four queries from the cache, then one write and the limit query again.
//          Then the client is terminated and the origin's databases and OPFS files are deleted.
//
// The emulator address is a closed port and the network is disabled before the first write: nothing is ever
// contacted.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

double now() => web.window.performance.now();

const int batchSize = 500;
const int perSubcollection = 10;

String text(int i) {
  final String base = 'document $i of the cache benchmark, ';
  return (base * (260 ~/ base.length + 1)).substring(0, 260);
}

Map<String, Object?> data(int n) => <String, Object?>{
  'n': n,
  'group': 'g${(n % 100).toString().padLeft(2, '0')}',
  'text': text(n),
};

String bigId(int i) => 'big/d${i.toString().padLeft(6, '0')}';

/// The paths of the N documents, in write order.
List<String> paths(int total) {
  final int small = total ~/ 5;
  final int big = total - small;
  return <String>[
    for (int i = 0; i < big; i++) bigId(i),
    for (int i = 0; i < small; i++) '${bigId(i ~/ perSubcollection)}/small/s${i % perSubcollection}',
  ];
}

FirebaseFirestore open(String kind, String tag) {
  final FirebaseApp app = FirebaseApp.withOptions(
    FirebaseOptions(apiKey: 'key', appId: 'appId', projectId: 'demo-cache-$tag'),
    name: 'cache',
  );
  if (kind == 'engine') {
    return FirebaseFirestore.instanceFor(
      app: app,
      settings: Settings(cacheSettings: IndexedDbCacheSettings()).withEmulator('127.0.0.1', 1),
    );
  }
  return FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(cacheSettings: PersistentCacheSettings()).withEmulator('127.0.0.1', 1),
    openDatabase: sqliteWebOpener(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      opfsWorker: kind == 'sqlite-opfs' ? Uri.parse('sqlite_opfs_worker.js') : null,
      storagePrefix: 'cache-$tag',
    ),
  );
}

const GetOptions fromCache = GetOptions(source: Source.cache);

Future<void> seed(String kind, String tag, int total, Map<String, Object?> result) async {
  final double start = now();
  final FirebaseFirestore firestore = open(kind, tag);
  await firestore.disableNetwork();
  final double opened = now();
  final List<String> all = paths(total);
  for (int from = 0; from < all.length; from += batchSize) {
    final WriteBatch batch = firestore.batch();
    for (int i = from; i < min(from + batchSize, all.length); i++) {
      batch.set(firestore.doc(all[i]), data(i));
    }
    unawaited(batch.commit().catchError((Object _) {}));
  }
  final DocumentSnapshot<Map<String, Object?>> last = await firestore.doc(all.last).get(fromCache);
  final double done = now();
  result['open'] = opened - start;
  result['seed'] = done - opened;
  result['lastFound'] = last.exists;
  result['pendingWrites'] = await firestore.getPendingWriteCount();
  await firestore.terminate();
}

Future<void> measure(String kind, String tag, int total, Map<String, Object?> result) async {
  final int big = total - total ~/ 5;
  final Map<String, Object?> sizes = <String, Object?>{};
  result['sizes'] = sizes;

  double t = now();
  final FirebaseFirestore firestore = open(kind, tag);
  await firestore.disableNetwork();
  final DocumentSnapshot<Map<String, Object?>> first = await firestore.doc(bigId(big ~/ 2)).get(fromCache);
  result['open_first_read'] = now() - t;
  result['firstRead'] = now();
  sizes['open_first_read'] = first.exists ? 1 : 0;

  final Random random = Random(42);
  int found = 0;
  t = now();
  for (int i = 0; i < 100; i++) {
    final DocumentSnapshot<Map<String, Object?>> doc = await firestore.doc(bigId(random.nextInt(big))).get(fromCache);
    if (doc.exists) found++;
  }
  result['doc_reads_100'] = now() - t;
  sizes['doc_reads_100'] = found;

  final CollectionReference<Map<String, Object?>> collection = firestore.collection('big');
  final Query<Map<String, Object?>> limit = collection.orderBy('n').limit(20);
  final Map<String, Query<Map<String, Object?>>> queries = <String, Query<Map<String, Object?>>>{
    'query_all': collection,
    'query_group_1pct': collection.where('group', isEqualTo: 'g42'),
    'query_orderBy_limit20': limit,
    'query_collection_group': firestore.collectionGroup('small'),
  };
  for (final MapEntry<String, Query<Map<String, Object?>>> entry in queries.entries) {
    t = now();
    final QuerySnapshot<Map<String, Object?>> snapshot = await entry.value.get(fromCache);
    result[entry.key] = now() - t;
    sizes[entry.key] = snapshot.size;
  }

  t = now();
  unawaited(firestore.doc('big/new').set(data(-1)).catchError((Object _) {}));
  final QuerySnapshot<Map<String, Object?>> afterWrite = await limit.get(fromCache);
  result['write_then_limit_query'] = now() - t;
  sizes['write_then_limit_query'] = afterWrite.size;
  // The new document has the lowest n: it must be the first result.
  result['writeSeen'] = afterWrite.docs.isNotEmpty && afterWrite.docs.first.id == 'new';

  await firestore.terminate();
}

/// Deletes every IndexedDB database and OPFS entry of the origin, so the next run (and Safari's profile, which is
/// the user's) keeps nothing.
Future<void> wipe() async {
  try {
    final JSArray<web.IDBDatabaseInfo> databases = await web.window.indexedDB.databases().toDart;
    for (final web.IDBDatabaseInfo info in databases.toDart) {
      final web.IDBOpenDBRequest request = web.window.indexedDB.deleteDatabase(info.name);
      final Completer<void> done = Completer<void>();
      request.onsuccess = ((web.Event _) => done.complete()).toJS;
      request.onerror = ((web.Event _) => done.complete()).toJS;
      request.onblocked = ((web.Event _) => done.complete()).toJS;
      await done.future;
    }
  } catch (_) {}
  try {
    final web.FileSystemDirectoryHandle root = await web.window.navigator.storage.getDirectory().toDart;
    final List<String> names = <String>[];
    final JSObject iterator = root.callMethod<JSObject>('keys'.toJS);
    while (true) {
      final JSObject next = await iterator.callMethod<JSPromise<JSObject>>('next'.toJS).toDart;
      if ((next['done'] as JSBoolean?)?.toDart ?? true) break;
      names.add((next['value']! as JSString).toDart);
    }
    for (final String name in names) {
      await root.removeEntry(name, web.FileSystemRemoveOptions(recursive: true)).toDart;
    }
  } catch (_) {}
}

Future<void> main() async {
  final double mainStart = now();
  final Map<String, String> query = Uri.base.queryParameters;
  final String kind = query['kind'] ?? 'engine';
  final String phase = query['phase'] ?? 'measure';
  final int total = int.parse(query['n'] ?? '2000');
  final String tag = query['tag'] ?? 'local';
  final Map<String, Object?> result = <String, Object?>{
    'page': 'cache',
    'kind': kind,
    'phase': phase,
    'n': total,
    'compiler': query['c'],
    'mainStart': mainStart,
    'userAgent': web.window.navigator.userAgent,
  };
  try {
    if (phase == 'seed') {
      await wipe();
      await seed(kind, tag, total, result);
    } else {
      await measure(kind, tag, total, result);
    }
  } catch (e, s) {
    result['error'] = '$e\n$s';
  }
  if (phase != 'seed') await wipe();
  web.console.log(jsonEncode(result).toJS);
  final web.Response response = await web.window
      .fetch('/result'.toJS, web.RequestInit(method: 'POST', body: jsonEncode(result).toJS))
      .toDart;
  final String next = (await response.text().toDart).toDart;
  if (next.isNotEmpty) {
    web.window.location.href = next;
  }
}
