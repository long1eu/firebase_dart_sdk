// The start-up page of the web CPU benchmark (run.dart starts it): what the
// playground does when it opens (a client on a memory cache, its network
// disabled, one listener), timed from the start of the navigation. The HTML
// page that loads it (written by run.dart) records when the program was
// loaded, compiled and instantiated in `window.benchMarks`.
//
// Reports to the server, then loads itself again (`load=2`, `load=3`) so that
// the second and third loads come from Chrome's HTTP cache and code caches.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore_dart/cloud_firestore_dart.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:web/web.dart' as web;

const bool isWasm = bool.fromEnvironment('dart.tool.dart2wasm');

Future<void> main() async {
  final double mainStart = web.window.performance.now();
  final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
    app: FirebaseApp.withOptions(
      const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:1234567890:web:startup',
        projectId: 'demo-startup',
      ),
    ),
    settings: Settings().copyWith(cacheSettings: const MemoryCacheSettings()),
  );
  await firestore.disableNetwork();
  final double ready = web.window.performance.now();
  final QuerySnapshot<Map<String, Object?>> first = await firestore
      .collection('cities')
      .snapshots()
      .first;
  final double firstSnapshot = web.window.performance.now();
  if (first.size != 0 || !first.metadata.isFromCache) {
    throw StateError('unexpected first snapshot');
  }

  final Map<String, String> query = Uri.base.queryParameters;
  final int load = int.parse(query['load'] ?? '1');
  final JSObject marks =
      web.window.getProperty<JSObject?>('benchMarks'.toJS) ?? JSObject();
  final Map<String, Object?> body = <String, Object?>{
    'compiler': isWasm ? 'dart2wasm' : 'dart2js',
    'load': load,
    'mainStart': mainStart,
    'ready': ready,
    'firstSnapshot': firstSnapshot,
    for (final String key in <String>[
      'bootStart',
      'moduleImported',
      'compiled',
      'instantiated',
    ])
      if (marks.has(key)) key: (marks[key]! as JSNumber).toDartDouble,
    'program': programTiming(),
  };
  await web.window
      .fetch(
        '/startup'.toJS,
        web.RequestInit(method: 'POST', body: jsonEncode(body).toJS),
      )
      .toDart;
  if (load < 3) {
    web.window.location.replace(
      Uri.base
          .replace(
            queryParameters: <String, String>{...query, 'load': '${load + 1}'},
          )
          .toString(),
    );
  }
}

/// The resource timing of the program file (`.dart.js` or `.wasm`): when its
/// download started and ended, and how many bytes came over the network (0
/// from the HTTP cache).
Map<String, Object?> programTiming() {
  final String suffix = isWasm ? '.wasm' : '.dart.js';
  for (final web.PerformanceEntry entry
      in web.window.performance.getEntriesByType('resource').toDart) {
    if (entry.name.endsWith(suffix)) {
      final web.PerformanceResourceTiming timing =
          entry as web.PerformanceResourceTiming;
      return <String, Object?>{
        'fetchStart': timing.fetchStart,
        'responseEnd': timing.responseEnd,
        'transferSize': timing.transferSize,
        'decodedBodySize': timing.decodedBodySize,
      };
    }
  }
  return <String, Object?>{};
}
