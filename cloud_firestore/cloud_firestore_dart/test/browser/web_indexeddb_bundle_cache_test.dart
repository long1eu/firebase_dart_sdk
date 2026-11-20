// The shared bundle cache suite of test/unit/firebase/firestore/local (the list of keyvalue_bundle_cache_test.dart) on the
// IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_bundle_cache_test.dart

@TestOn('browser')
library;

import 'package:test/test.dart';

import 'indexeddb_test_persistence.dart';

import '../unit/firebase/firestore/local/cases/bundle_cache_test_case.dart';

void main() {
  defineBundleCacheTests(() => newIndexedDbTestPersistence());
}
