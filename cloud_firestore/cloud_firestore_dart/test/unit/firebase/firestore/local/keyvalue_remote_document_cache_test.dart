// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/keyvalue/cache_store_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'cases/remote_document_cache_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  late RemoteDocumentCacheTestCase testCase;

  setUp(() async {
    print('setUp');
    final CacheStorePersistence persistence = await createKeyValuePersistence();
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

  // Not in the Android SDK, which has no test that the scan keeps deleted and unknown
  // documents out of the scan: they are not read, so they do not count as scanned documents.
  test(
    'queryScansSkipDeletedAndUnknownDocuments',
    () async {
      final CacheStorePersistence persistence =
          await createKeyValuePersistence();
      try {
        await persistence.runTransaction('add documents', () async {
          await persistence.remoteDocumentCache.add(
            doc('coll/found', 1, map(<dynamic>['a', 1])),
            version(1),
          );
          await persistence.remoteDocumentCache.add(
            deletedDoc('coll/deleted', 1),
            version(1),
          );
          await persistence.remoteDocumentCache.add(
            unknownDoc('coll/unknown', 1),
            version(1),
          );
        });

        final QueryContext context = QueryContext();
        final ImmutableSortedMap<DocumentKey, Document> results =
            await persistence.remoteDocumentCache.getAllDocumentsMatchingQuery(
              query('coll'),
              IndexOffset.none,
              context: context,
            );

        expect(
          results
              .map((MapEntry<DocumentKey, Document> e) => e.key.path.toString())
              .toList(),
          <String>['coll/found'],
        );
        expect(context.documentReadCount, 1);
      } finally {
        await persistence.shutdown();
      }
    },
  );
}
