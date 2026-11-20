// The shared document overlay cache suite (cases/document_overlay_cache_test_case.dart) on the IndexedDB engine, in a
// browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_document_overlay_cache_test.dart

@TestOn('browser')
library;

import 'package:test/test.dart';

import '../unit/firebase/firestore/local/cases/document_overlay_cache_test_case.dart';
import 'indexeddb_test_persistence.dart';

void main() {
  defineDocumentOverlayCacheTests('indexeddb', newIndexedDbTestPersistence);
}
