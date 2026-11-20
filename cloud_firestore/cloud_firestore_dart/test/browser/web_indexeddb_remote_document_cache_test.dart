// The shared remote document cache suite of test/unit/firebase/firestore/local (the list of keyvalue_remote_document_cache_test.dart) on the
// IndexedDB engine, in a browser.
//
//   dart test -p chrome -c dart2wasm test/browser/web_indexeddb_remote_document_cache_test.dart

@TestOn('browser')
library;

import 'package:cloud_firestore_dart/src/firebase/firestore/local/indexeddb/web/indexeddb_persistence_web.dart'
    show WebIndexedDbPersistence;
import 'dart:async';

import 'package:test/test.dart';

import 'indexeddb_test_persistence.dart';

import '../unit/firebase/firestore/local/cases/remote_document_cache_test_case.dart';

void main() {
  late RemoteDocumentCacheTestCase testCase;

  setUp(() async {
    print('setUp');
    final WebIndexedDbPersistence persistence =
        await newIndexedDbTestPersistence();
    testCase = RemoteDocumentCacheTestCase(persistence)..setUp();
    print('setUpDone');
  });

  tearDown(
    () => Future<void>.delayed(
      const Duration(milliseconds: 250),
      () => testCase.tearDown(),
    ),
  );

  test(
    'testReadDocumentNotInCache',
    () => testCase.testReadDocumentNotInCache(),
  );
  test('testSetAndReadDocument', () => testCase.testSetAndReadDocument());
  test(
    'testSetAndReadSeveralDocuments',
    () => testCase.testSetAndReadSeveralDocuments(),
  );
  test(
    'testReadSeveralDocumentsIncludingMissingDocument',
    () => testCase.testReadSeveralDocumentsIncludingMissingDocument(),
  );
  test(
    'testSetAndReadSeveralDocumentsWithOverlappingKeys',
    () => testCase.testSetAndReadSeveralDocumentsWithOverlappingKeys(),
  );
  test(
    'testSetAndReadSeveralDocumentsWithDeeplyNestedKeys',
    () => testCase.testSetAndReadSeveralDocumentsWithDeeplyNestedKeys(),
  );
  test(
    'testSetAndReadDeletedDocument',
    () => testCase.testSetAndReadDeletedDocument(),
  );
  test('testSetDocumentToNewValue', () => testCase.testSetDocumentToNewValue());
  test('testRemoveDocument', () => testCase.testRemoveDocument());
  test(
    'testRemoveNonExistentDocument',
    () => testCase.testRemoveNonExistentDocument(),
  );
  test('testGetAllFromCollection', () => testCase.testGetAllFromCollection());
  test(
    'testGetAllFromExcludesSubcollections',
    () => testCase.testGetAllFromExcludesSubcollections(),
  );
  test(
    'testGetAllFromSinceReadTimeAndSeconds',
    () => testCase.testGetAllFromSinceReadTimeAndSeconds(),
  );
  test(
    'testGetAllFromSinceReadTimeAndNanoseconds',
    () => testCase.testGetAllFromSinceReadTimeAndNanoseconds(),
  );
  test(
    'testGetAllFromSinceReadTimeAndDocumentKey',
    () => testCase.testGetAllFromSinceReadTimeAndDocumentKey(),
  );
  test(
    'testGetAllFromUsesReadTimeNotUpdateTime',
    () => testCase.testGetAllFromUsesReadTimeNotUpdateTime(),
  );
  test(
    'testGetMatchingDocsAppliesQueryCheck',
    () => testCase.testGetMatchingDocsAppliesQueryCheck(),
  );
  test(
    'testGetMatchingDocsRespectsMutatedDocs',
    () => testCase.testGetMatchingDocsRespectsMutatedDocs(),
  );
  test('testRemoveAllDocuments', () => testCase.testRemoveAllDocuments());
  test(
    'testDocumentsMatchingQueryExcludesSubcollections',
    () => testCase.testDocumentsMatchingQueryExcludesSubcollections(),
  );
  test(
    'testAddingDocumentWithReadTimeOfZeroFails',
    () => testCase.testAddingDocumentWithReadTimeOfZeroFails(),
  );
}
