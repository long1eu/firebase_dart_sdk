// A page on the IndexedDB cache engine (IndexedDbCacheSettings, experimental): with the network disabled it sets a
// document, reads it, runs a collection query and listens to it (which stores a target), then reloads itself and
// reads everything again from the cache. The result goes to document.title ("ok: ..." or "error: ..."), and the
// rows of the database are listed at the end, as JSON. Project demo-idb, the database the JS SDK uses for it:
// firestore/[DEFAULT]/demo-idb/main. The network never starts: the client points at a closed local port and its
// network is disabled before the first write.
//
//   cd tool/bench/web_idb && dart pub get
//   dart compile js idb_engine/engine_page.dart -o idb_engine/static/engine_page.js
//   dart compile wasm idb_engine/engine_page.dart -o idb_engine/static/engine_page.wasm
//   rm -rf /tmp/idb_profile; idb_engine/run_page.sh 'index.html'          # dart2js
//   rm -rf /tmp/idb_profile; idb_engine/run_page.sh 'index.html?c=wasm'   # dart2wasm
//
// 'index.html#phase2' skips the writes: it only reads the cache and lists the rows (after engine_check.js).
//
// To check the database against the JS SDK, see js_import/engine_check.js.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

final StringBuffer out = StringBuffer();

void log(String message) {
  out.writeln(message);
  web.document.body!.textContent = out.toString();
}

Future<FirebaseFirestore> open() async {
  final FirebaseApp app = FirebaseApp.withOptions(
    const FirebaseOptions(apiKey: 'fake', appId: 'fake', projectId: 'demo-idb'),
  );
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: app,
    settings: Settings(
      cacheSettings: IndexedDbCacheSettings(),
    ).withEmulator('127.0.0.1', 1),
  );
  await firestore.disableNetwork();
  return firestore;
}

Future<void> readBack(FirebaseFirestore firestore) async {
  final DocumentSnapshot<Map<String, Object?>> doc = await firestore
      .doc('items/a')
      .get(const GetOptions(source: Source.cache));
  log(
    'items/a exists=${doc.exists} pending=${doc.metadata.hasPendingWrites} data=${doc.data()}',
  );
  final QuerySnapshot<Map<String, Object?>> query = await firestore
      .collection('items')
      .where('n', isGreaterThan: 0)
      .get(const GetOptions(source: Source.cache));
  log(
    'items where n > 0: ${query.docs.map((QueryDocumentSnapshot<Map<String, Object?>> d) => d.id).toList()}',
  );
  try {
    final DocumentSnapshot<Map<String, Object?>> fromJs = await firestore
        .doc('items/fromjs')
        .get(const GetOptions(source: Source.cache));
    log(
      'items/fromjs (written by js_import/engine_check.js) exists=${fromJs.exists} data=${fromJs.data()}',
    );
  } on FirestoreException catch (e) {
    log('items/fromjs not in the cache (${e.errorCode.name})');
  }
  log('pending writes: ${await firestore.getPendingWriteCount()}');
}

Future<void> phase1() async {
  final FirebaseFirestore firestore = await open();
  // Not awaited: a write completes when the backend acknowledges it.
  unawaited(
    firestore
        .doc('items/a')
        .set(<String, Object?>{
          'title': 'written offline',
          'n': 1,
          'd': 2.5,
          'ts': Timestamp(1700000000, 123456000),
          'list': <Object?>[1, 'two', null],
          'map': <String, Object?>{'x': true},
          'st': FieldValue.serverTimestamp(),
        })
        .catchError((Object _) {}),
  );
  unawaited(
    firestore
        .doc('items/b')
        .set(<String, Object?>{'n': 2})
        .catchError((Object _) {}),
  );
  unawaited(
    firestore
        .doc('items/b')
        .update(<String, Object?>{'n': FieldValue.increment(5)})
        .catchError((Object _) {}),
  );
  await readBack(firestore);
  // A listener stores a target.
  final QuerySnapshot<Map<String, Object?>> first = await firestore
      .collection('items')
      .snapshots()
      .first;
  log(
    'listener: ${first.docs.length} documents, fromCache=${first.metadata.isFromCache}',
  );
  await firestore.terminate();
  log('terminated, reloading');
  web.window.sessionStorage.setItem('engine_page_log', out.toString());
  web.window.location.replace('${web.window.location.href}#phase2');
  web.window.location.reload();
}

Future<void> phase2() async {
  out.write(web.window.sessionStorage.getItem('engine_page_log') ?? '');
  log('-- after the reload');
  final FirebaseFirestore firestore = await open();
  await readBack(firestore);
  await firestore.terminate();
  log(
    'rows: ${jsonEncode(await dumpDatabase('firestore/[DEFAULT]/demo-idb/main'))}',
  );
  web.document.title = 'ok: ${out.toString().replaceAll('\n', ' | ')}';
}

@JS('JSON.stringify')
external JSString _stringify(JSAny? value);

/// The rows of every store of [name], as JSON (the values as IndexedDB holds them).
Future<Map<String, Object?>> dumpDatabase(String name) async {
  final web.IDBDatabase db =
      (await request(web.window.indexedDB.open(name)))! as web.IDBDatabase;
  final Map<String, Object?> result = <String, Object?>{'version': db.version};
  final web.DOMStringList names = db.objectStoreNames;
  // The small stores first: a page title is cut after a few thousand characters.
  const List<String> first = <String>[
    'targets',
    'targetDocuments',
    'targetGlobal',
    'mutationQueues',
  ];
  final List<String> stores = <String>[
    for (final String store in first)
      if (names.contains(store)) store,
    for (int i = 0; i < names.length; i++)
      if (!first.contains(names.item(i))) names.item(i)!,
  ];
  for (final String store in stores) {
    final web.IDBObjectStore objects = db
        .transaction(store.toJS)
        .objectStore(store);
    final JSAny? keys = await request(objects.getAllKeys());
    final JSAny? values = await request(objects.getAll());
    result[store] = <String, Object?>{
      'keys': jsonDecode(_stringify(keys).toDart),
      'values': jsonDecode(_stringify(values).toDart),
    };
  }
  db.close();
  return result;
}

Future<JSAny?> request(web.IDBRequest request) {
  final Completer<JSAny?> completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => completer.complete(
    request.result,
  )).toJS;
  request.onerror = ((web.Event _) => completer.completeError(
    StateError('${request.error?.message}'),
  )).toJS;
  return completer.future;
}

Future<void> main() async {
  try {
    if (web.window.location.hash == '#phase2') {
      await phase2();
    } else {
      await phase1();
    }
  } catch (e, st) {
    log('ERROR $e\n$st');
    web.document.title = 'error: ${out.toString().replaceAll('\n', ' | ')}';
  }
}
