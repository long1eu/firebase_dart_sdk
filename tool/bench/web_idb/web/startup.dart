// The start-up measurement of docs/spikes/indexeddb_cache.md: the time from
// the start of the page load (performance.timeOrigin) to the cache being open
// and a first document read from it. Run through run.dart.
//
// startup.html?storage=idb|opfs|memory&phase=seed|measure
//
// seed     opens the cache with the network disabled, writes the document
//          bench/doc (a pending write, so it is in the cache) and closes it.
// measure  opens the cache and reads bench/doc from it (Source.cache).
//          With storage=memory there is no stored document: the read is a
//          query of the empty collection from the cache, which needs the
//          same client start.
//
// The emulator address is a closed port: nothing is ever contacted.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:cloud_firestore_dart_sqlite/web.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

double now() => web.window.performance.now();

Future<void> main() async {
  final double mainStart = now();
  final Map<String, String> query = Uri.base.queryParameters;
  final String storage = query['storage'] ?? 'idb';
  final String phase = query['phase'] ?? 'measure';
  final Map<String, Object?> result = <String, Object?>{
    'page': 'startup',
    'storage': storage,
    'phase': phase,
    'compiler': query['c'],
    'cache': query['cache'],
    'mainStart': mainStart,
  };
  try {
    final FirebaseApp app = FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'key',
        appId: 'appId',
        projectId: 'demo-startup',
      ),
      name: 'startup',
    );
    final Settings settings = Settings(
      cacheSettings: storage == 'memory'
          ? const MemoryCacheSettings()
          : PersistentCacheSettings(),
    ).withEmulator('127.0.0.1', 9);
    final FirebaseFirestore firestore = storage == 'memory'
        ? FirebaseFirestore.instanceFor(app: app, settings: settings)
        : FirebaseFirestore.instanceFor(
            app: app,
            settings: settings,
            openDatabase: sqliteWebOpener(
              sqlite3Wasm: Uri.parse('sqlite3.wasm'),
              opfsWorker: storage == 'opfs'
                  ? Uri.parse('sqlite_opfs_worker.js')
                  : null,
              storagePrefix: 'startup-$storage-${query['c']}',
            ),
          );
    final DocumentReference<Map<String, Object?>> doc = firestore.doc(
      'bench/doc',
    );
    if (phase == 'seed') {
      await firestore.disableNetwork();
      unawaited(doc.set(<String, Object?>{'name': 'seed', 'n': 1}));
      final DocumentSnapshot<Map<String, Object?>> snapshot = await doc.get(
        const GetOptions(source: Source.cache),
      );
      result['seeded'] = snapshot.exists;
    } else if (storage == 'memory') {
      final QuerySnapshot<Map<String, Object?>> snapshot = await firestore
          .collection('bench')
          .get(const GetOptions(source: Source.cache));
      result['read'] = now();
      result['found'] = snapshot.size;
    } else {
      final DocumentSnapshot<Map<String, Object?>> snapshot = await doc.get(
        const GetOptions(source: Source.cache),
      );
      result['read'] = now();
      result['found'] = snapshot.exists;
      result['db'] = firestore.persistentCacheIndexManager != null;
    }
    await firestore.terminate();
  } catch (e, s) {
    result['error'] = '$e\n$s';
  }
  // How long the sqlite3.wasm and worker downloads took, from the resource
  // timing entries.
  final List<Object?> resources = <Object?>[];
  for (final web.PerformanceEntry entry
      in web.window.performance.getEntriesByType('resource').toDart) {
    final web.PerformanceResourceTiming timing =
        entry as web.PerformanceResourceTiming;
    resources.add(<String, Object?>{
      'name': Uri.parse(timing.name).pathSegments.last,
      'start': timing.startTime,
      'end': timing.responseEnd,
      'transfer': timing.transferSize,
    });
  }
  result['resources'] = resources;
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
