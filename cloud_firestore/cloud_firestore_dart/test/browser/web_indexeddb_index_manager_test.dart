// The shared index manager suite of test/unit/firebase/firestore/local (the list of keyvalue_index_manager_test.dart) on the
// IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_index_manager_test.dart

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/indexeddb_persistence_web.dart'
    show WebIndexedDbPersistence;
import 'dart:async';

import 'package:test/test.dart';

import 'indexeddb_test_persistence.dart';

import '../unit/firebase/firestore/local/cases/index_manager_test_case.dart';

void main() {
  late IndexManagerTestCase testCase;

  setUp(() async {
    print('setUp');
    final WebIndexedDbPersistence persistence =
        await newIndexedDbTestPersistence();
    testCase = IndexManagerTestCase(persistence);
    await testCase.setUp();
    print('setUpDone');
  });

  tearDown(
    () => Future<void>.delayed(
      const Duration(milliseconds: 250),
      () => testCase.tearDown(),
    ),
  );

  test(
    'testCanAddAndReadCollectionParentIndexEntries',
    () => testCase.testCanAddAndReadCollectionParentIndexEntries(),
  );
}
