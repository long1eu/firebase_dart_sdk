// The raw engine benchmark and the transaction lifetime test of
// docs/spikes/indexeddb_cache.md. Run through run.dart, which serves this
// page compiled with dart2js or dart2wasm and collects what it posts.
//
// engine.html?engine=idb          IndexedDB directly (package:web)
// engine.html?engine=sqlite-idb   the SQLite cache's opener, IndexedDB storage
// engine.html?engine=sqlite-opfs  the same opener with the OPFS worker
// engine.html?engine=txtest       whether an IndexedDB transaction survives
//                                 the awaits of point 4
//
// The operations are those the cache does, on records of 1 KB under string
// keys "cNN/dNNNNN" (10 groups of 1,000), each awaited one after the other as
// the cache's Dart code would:
//   insert_tx1     10,000 inserts, one transaction each
//   insert_tx100   10,000 inserts, 100 transactions of 100
//   insert_tx1_strict, insert_tx100_pipelined   IndexedDB only, see below
//   get            1,000 point reads by key, one read-only transaction each
//   scan           an ordered range scan of the 1,000 keys of one prefix (x10)
//   delete_tx1     1,000 deletes by key, one transaction each
// Times are milliseconds for the whole operation (the scan: per scan).

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:web/web.dart' as web;

const int records = 10000;
const int groups = 10;
const int reads = 1000;
const int deletes = 1000;
const int scans = 10;

double now() => web.window.performance.now();

String key(int i) =>
    'c${(i % groups).toString().padLeft(2, '0')}/d${i.toString().padLeft(5, '0')}';

final Random random = Random(7);
final List<Uint8List> values = List<Uint8List>.generate(
  100,
  (_) =>
      Uint8List.fromList(List<int>.generate(1024, (_) => random.nextInt(256))),
);

Future<void> post(Map<String, Object?> result) async {
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

void log(String line) {
  web.console.log(line.toJS);
  (web.document.body!
    ..append(web.document.createElement('pre')..textContent = line));
}

Future<void> main() async {
  final double mainStart = now();
  final Map<String, String> query = Uri.base.queryParameters;
  final String engine = query['engine'] ?? 'idb';
  final int runs = int.tryParse(query['runs'] ?? '') ?? 5;
  final Map<String, Object?> result = <String, Object?>{
    'page': 'engine',
    'engine': engine,
    'compiler': query['c'],
    'mainStart': mainStart,
  };
  try {
    if (engine == 'txtest') {
      result['tx'] = await transactionTests();
    } else {
      final List<Map<String, double>> all = <Map<String, double>>[];
      for (int run = 0; run < runs; run++) {
        final Map<String, double> times = switch (engine) {
          'idb' => await idbRun(run),
          'sqlite-idb' => await sqliteRun(run, opfs: false),
          'sqlite-opfs' => await sqliteRun(run, opfs: true),
          _ => throw ArgumentError(engine),
        };
        log('$engine run $run: $times');
        all.add(times);
      }
      result['runs'] = all;
    }
  } catch (e, s) {
    result['error'] = '$e\n$s';
  }
  log(jsonEncode(result));
  await post(result);
}

// --- IndexedDB -------------------------------------------------------------

Future<T> request<T extends JSAny?>(web.IDBRequest request) {
  final Completer<T> completer = Completer<T>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as T);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error?.name ?? 'request failed');
  }).toJS;
  return completer.future;
}

Future<void> done(web.IDBTransaction tx) {
  final Completer<void> completer = Completer<void>();
  tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
  tx.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(tx.error?.name ?? 'transaction failed');
    }
  }).toJS;
  tx.onabort = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError('abort: ${tx.error?.name}');
    }
  }).toJS;
  return completer.future;
}

Future<web.IDBDatabase> openIdb(String name) {
  final web.IDBOpenDBRequest open = web.window.indexedDB.open(name, 1);
  open.onupgradeneeded = ((web.Event _) {
    (open.result! as web.IDBDatabase).createObjectStore('docs');
  }).toJS;
  return request<web.IDBDatabase>(open);
}

Future<void> deleteIdb(String name) =>
    request<JSAny?>(web.window.indexedDB.deleteDatabase(name));

Future<Map<String, double>> idbRun(int run) async {
  final String name = 'bench-idb-$run-${DateTime.now().microsecondsSinceEpoch}';
  final Map<String, double> times = <String, double>{};
  web.IDBDatabase db = await openIdb(name);

  double t = now();
  for (int i = 0; i < records; i++) {
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readwrite');
    await request<JSAny?>(
      tx.objectStore('docs').put(values[i % 100].toJS, key(i).toJS),
    );
    await done(tx);
  }
  times['insert_tx1'] = now() - t;

  // The same with durability "strict" (the default, in Chrome, is relaxed).
  db.close();
  await deleteIdb(name);
  db = await openIdb(name);
  t = now();
  for (int i = 0; i < records; i++) {
    final web.IDBTransaction tx = db.transaction(
      'docs'.toJS,
      'readwrite',
      web.IDBTransactionOptions(durability: 'strict'),
    );
    await request<JSAny?>(
      tx.objectStore('docs').put(values[i % 100].toJS, key(i).toJS),
    );
    await done(tx);
  }
  times['insert_tx1_strict'] = now() - t;

  db.close();
  await deleteIdb(name);
  db = await openIdb(name);
  t = now();
  for (int b = 0; b < records; b += 100) {
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readwrite');
    final web.IDBObjectStore store = tx.objectStore('docs');
    for (int i = b; i < b + 100; i++) {
      await request<JSAny?>(store.put(values[i % 100].toJS, key(i).toJS));
    }
    await done(tx);
  }
  times['insert_tx100'] = now() - t;

  // The same without awaiting each put: the 100 requests are issued at once
  // and only the transaction is awaited (what the JS SDK's PersistencePromise
  // chains amount to for independent writes).
  db.close();
  await deleteIdb(name);
  db = await openIdb(name);
  t = now();
  for (int b = 0; b < records; b += 100) {
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readwrite');
    final web.IDBObjectStore store = tx.objectStore('docs');
    for (int i = b; i < b + 100; i++) {
      store.put(values[i % 100].toJS, key(i).toJS);
    }
    await done(tx);
  }
  times['insert_tx100_pipelined'] = now() - t;

  t = now();
  int bytes = 0;
  for (int n = 0; n < reads; n++) {
    final int i = (n * 7919) % records;
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readonly');
    final JSUint8Array value = await request<JSUint8Array>(
      tx.objectStore('docs').get(key(i).toJS),
    );
    bytes += value.toDart.length;
  }
  times['get'] = now() - t;
  if (bytes != reads * 1024) throw StateError('read $bytes bytes');

  t = now();
  for (int s = 0; s < scans; s++) {
    final String prefix = 'c${(s % groups).toString().padLeft(2, '0')}/';
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readonly');
    final web.IDBRequest cursorRequest = tx
        .objectStore('docs')
        .openCursor(web.IDBKeyRange.bound(prefix.toJS, '$prefix￿'.toJS));
    final Completer<int> scanned = Completer<int>();
    int count = 0;
    String last = '';
    cursorRequest.onsuccess = ((web.Event _) {
      final web.IDBCursorWithValue? cursor =
          cursorRequest.result as web.IDBCursorWithValue?;
      if (cursor == null) {
        scanned.complete(count);
        return;
      }
      final String k = (cursor.key! as JSString).toDart;
      if (k.compareTo(last) <= 0) throw StateError('out of order');
      last = k;
      count += (cursor.value! as JSUint8Array).toDart.length > 0 ? 1 : 0;
      cursor.continue_();
    }).toJS;
    if (await scanned.future != records ~/ groups) throw StateError('scan');
  }
  times['scan'] = (now() - t) / scans;

  t = now();
  for (int n = 0; n < deletes; n++) {
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readwrite');
    await request<JSAny?>(tx.objectStore('docs').delete(key(n * 10).toJS));
    await done(tx);
  }
  times['delete_tx1'] = now() - t;

  // Opening the database again with 9,000 records and reading one.
  db.close();
  t = now();
  db = await openIdb(name);
  final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readonly');
  await request<JSAny?>(tx.objectStore('docs').get(key(1).toJS));
  times['reopen_and_get'] = now() - t;

  db.close();
  await deleteIdb(name);
  return times;
}

// --- SQLite through the cache's opener ---------------------------------------

Future<Map<String, double>> sqliteRun(int run, {required bool opfs}) async {
  final OpenDatabase opener = sqliteWebOpener(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    opfsWorker: opfs ? Uri.parse('sqlite_opfs_worker.js') : null,
    storagePrefix: 'bench',
  );
  final String name = 'run-$run-${DateTime.now().microsecondsSinceEpoch}';
  Future<Database> open() => opener(
    name,
    version: 1,
    onCreate: (Database db, int version) => db.execute(
      'CREATE TABLE docs (path TEXT PRIMARY KEY, contents BLOB) WITHOUT ROWID',
    ),
  );
  final Map<String, double> times = <String, double>{};
  Database db = await open();
  if (opfs && db is! SqliteOpfsDatabase) {
    throw StateError('not on OPFS: ${db.runtimeType}');
  }

  Future<void> insertAll(int batch) async {
    for (int b = 0; b < records; b += batch) {
      await db.execute('BEGIN IMMEDIATE;');
      for (int i = b; i < b + batch; i++) {
        await db.execute(
          'INSERT OR REPLACE INTO docs (path, contents) VALUES (?, ?)',
          <Object?>[key(i), values[i % 100]],
        );
      }
      await db.execute('COMMIT;');
    }
  }

  double t = now();
  await insertAll(1);
  times['insert_tx1'] = now() - t;

  await db.execute('DELETE FROM docs');
  t = now();
  await insertAll(100);
  times['insert_tx100'] = now() - t;

  t = now();
  int bytes = 0;
  for (int n = 0; n < reads; n++) {
    final int i = (n * 7919) % records;
    final List<Map<String, dynamic>> rows = await db.query(
      'SELECT contents FROM docs WHERE path = ?',
      <Object?>[key(i)],
    );
    bytes += (rows.single['contents'] as Uint8List).length;
  }
  times['get'] = now() - t;
  if (bytes != reads * 1024) throw StateError('read $bytes bytes');

  t = now();
  for (int s = 0; s < scans; s++) {
    final String prefix = 'c${(s % groups).toString().padLeft(2, '0')}/';
    final List<Map<String, dynamic>> rows = await db.query(
      'SELECT path, contents FROM docs WHERE path >= ? AND path < ? ORDER BY path',
      <Object?>[prefix, '$prefix￿'],
    );
    if (rows.length != records ~/ groups) throw StateError('scan');
  }
  times['scan'] = (now() - t) / scans;

  t = now();
  for (int n = 0; n < deletes; n++) {
    await db.execute('BEGIN IMMEDIATE;');
    await db.delete('DELETE FROM docs WHERE path = ?', <Object?>[key(n * 10)]);
    await db.execute('COMMIT;');
  }
  times['delete_tx1'] = now() - t;

  // Opening the database again (sqlite3.wasm already loaded) and reading one.
  db.close();
  t = now();
  db = await open();
  await db.query('SELECT contents FROM docs WHERE path = ?', <Object?>[key(1)]);
  times['reopen_and_get'] = now() - t;

  db.close();
  await (db as ClearableDatabase).clearStorage();
  return times;
}

// --- Point 4: does a transaction survive an await? ---------------------------

Future<Map<String, String>> transactionTests() async {
  final String name = 'txtest-${DateTime.now().microsecondsSinceEpoch}';
  final web.IDBDatabase db = await openIdb(name);
  final Map<String, String> results = <String, String>{};

  Future<void> check(
    String label,
    Future<void> Function(web.IDBTransaction tx) between,
  ) async {
    final web.IDBTransaction tx = db.transaction('docs'.toJS, 'readwrite');
    final Future<void> finished = done(tx).then((_) {}, onError: (Object _) {});
    final web.IDBObjectStore store = tx.objectStore('docs');
    String outcome;
    try {
      await request<JSAny?>(store.put('a'.toJS, '$label/a'.toJS));
      await between(tx);
      await request<JSAny?>(store.put('b'.toJS, '$label/b'.toJS));
      outcome = 'survives';
    } catch (e) {
      final String text = e.toString();
      outcome =
          text.contains('TransactionInactiveError') ||
              text.contains('not active')
          ? 'closed (TransactionInactiveError)'
          : 'closed ($text)';
    }
    await finished;
    // Whether the second put is in the database.
    final web.IDBTransaction read = db.transaction('docs'.toJS, 'readonly');
    final JSAny? a = await request<JSAny?>(
      read.objectStore('docs').get('$label/a'.toJS),
    );
    final JSAny? b = await request<JSAny?>(
      read.objectStore('docs').get('$label/b'.toJS),
    );
    results[label] =
        '$outcome; first write stored: ${a != null}, second: ${b != null}';
  }

  Future<void> idbRequest(web.IDBTransaction tx) =>
      request<JSAny?>(tx.objectStore('docs').get('x'.toJS));

  await check('a: await an IndexedDB request (Future)', idbRequest);
  await check('b1: await Future.value()', (_) => Future<void>.value());
  await check('b2: await a completed Completer', (_) {
    final Completer<void> c = Completer<void>()..complete();
    return c.future;
  });
  await check(
    'b3: await a sync function result (async fn without awaits)',
    (_) async {},
  );
  await check(
    'c: await Future.microtask',
    (_) => Future<void>.microtask(() {}),
  );
  await check('c2: scheduleMicrotask x1000', (_) {
    final Completer<void> c = Completer<void>();
    int n = 0;
    void step() => ++n == 1000 ? c.complete() : scheduleMicrotask(step);
    scheduleMicrotask(step);
    return c.future;
  });
  await check(
    'c3: await a resolved JS Promise',
    (_) => JSPromise<JSAny?>(
      (JSFunction resolve, JSFunction reject) {
        resolve.callAsFunction();
      }.toJS,
    ).toDart,
  );
  await check(
    'd1: await Future.delayed(Duration.zero)',
    (_) => Future<void>.delayed(Duration.zero),
  );
  await check('d2: await Timer.run', (_) {
    final Completer<void> c = Completer<void>();
    Timer.run(c.complete);
    return c.future;
  });
  await check('d3: await Future(() {})', (_) => Future<void>(() {}));
  await check(
    'e1: chain of request, Future.value, microtask, request, 10 awaits of async fns',
    (web.IDBTransaction tx) async {
      await idbRequest(tx);
      await Future<void>.value();
      await Future<void>.microtask(() {});
      await idbRequest(tx);
      for (int i = 0; i < 10; i++) {
        await (() async => i)();
      }
    },
  );
  await check('e2: chain ending in Future.delayed(Duration.zero)', (
    web.IDBTransaction tx,
  ) async {
    await idbRequest(tx);
    await Future<void>.value();
    await Future<void>.delayed(Duration.zero);
  });
  await check(
    'f: await Stream.fromIterable(...).toList()',
    (_) => Stream<int>.fromIterable(<int>[1, 2, 3]).toList(),
  );
  await check('g: CPU work of 50 ms between requests', (_) async {
    final double start = now();
    while (now() - start < 50) {}
  });
  db.close();
  await deleteIdb(name);
  return results;
}
