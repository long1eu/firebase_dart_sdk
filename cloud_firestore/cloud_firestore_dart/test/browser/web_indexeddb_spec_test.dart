// The upstream JSON spec tests (test/res/json, the runner of test/unit/firebase/firestore/spec) on the IndexedDB engine,
// in a browser. A client that restarts opens the database of its spec again, so the durable-persistence specs run; the
// multi-client specs are skipped (one tab at a time, spec_skip_list.dart).
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_spec_test.dart

@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/indexeddb_persistence_web.dart';

import '../unit/firebase/firestore/spec/spec_runner_core.dart';
import '../unit/firebase/firestore/spec/spec_skip_list.dart';
import 'indexeddb_test_persistence.dart';

/// The files of test/res/json, without the extension. A browser can not list a directory: a file added there has to be
/// added here (the VM runner reads the directory).
const List<String> specFiles = <String>[
  'bundle_spec_test',
  'collection_spec_test',
  'existence_filter_spec_test',
  'garbage_collection_spec_test',
  'index_spec_test',
  'limbo_spec_test',
  'limit_spec_test',
  'listen_source_spec_test',
  'listen_spec_test',
  'offline_spec_test',
  'orderby_spec_test',
  'perf_spec_test',
  'persistence_spec_test',
  'query_spec_test',
  'recovery_spec_test',
  'remote_store_spec_test',
  'removed_since_sync_point_spec_test',
  'resume_token_spec_test',
  'write_spec_test',
];

Future<Map<String, dynamic>> _fetchJson(String name) async {
  // The runner serves the package: the test is test/browser/<file>, the specs are in test/res/json.
  final Uri uri = Uri.base.resolve('../res/json/$name.json');
  final web.Response response = await web.window
      .fetch(uri.toString().toJS)
      .toDart;
  if (!response.ok) {
    throw StateError('Fetching $uri failed: HTTP ${response.status}');
  }
  return jsonDecode((await response.text().toDart).toDart)
      as Map<String, dynamic>;
}

/// The persistences of the running spec: the ones not shut down yet.
final List<WebIndexedDbPersistence> _open = <WebIndexedDbPersistence>[];

/// Waits until the work a spec step started is done: the IndexedDB requests complete in tasks of the browser, not in
/// microtasks, so one turn of the event loop (the VM runner's wait) is not enough. Done when every persistence of the
/// spec was idle for three turns in a row.
Future<void> _settle() async {
  int idleTurns = 0;
  for (int turn = 0; idleTurns < 3; turn++) {
    if (turn > 100000) {
      throw StateError('The IndexedDB persistence did not become idle.');
    }
    await Future<void>.delayed(Duration.zero);
    _open.removeWhere((WebIndexedDbPersistence p) => !p.started && p.isIdle);
    idleTurns = _open.every((WebIndexedDbPersistence p) => p.isIdle)
        ? idleTurns + 1
        : 0;
  }
}

Future<void> main() async {
  final Map<String, Map<String, dynamic>> files =
      <String, Map<String, dynamic>>{
        for (final String name in specFiles) name: await _fetchJson(name),
      };
  // One database per spec (the name is the spec's, stable across the restarts of that spec) and per run of the page.
  final String run = newIndexedDbPersistenceKey('spec');
  registerSpecTestFiles(
    files: files,
    variant: 'indexeddb',
    // The bundle specs carry documents of project 'test-project', which the persistence must be able to decode.
    getPersistence: (_, String name) async {
      final WebIndexedDbPersistence persistence =
          await newIndexedDbTestPersistence(
            persistenceKey: '$run-$name',
            projectId: 'test-project',
          );
      _open.add(persistence);
      return persistence;
    },
    excludedTags: indexedDbExcludedTags,
    settle: _settle,
  );
}
