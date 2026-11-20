// The shared globals cache suite of test/unit/firebase/firestore/local (the list of keyvalue_globals_cache_test.dart) on the
// IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_globals_cache_test.dart

@TestOn('browser')
library;

import 'package:test/test.dart';

import 'indexeddb_test_persistence.dart';

import '../unit/firebase/firestore/local/cases/globals_cache_test_case.dart';

/// Port of the Android `SQLiteGlobalCacheTest`.
void main() {
  defineGlobalsCacheTests(() => newIndexedDbTestPersistence());
}
