// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/encoded_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_context.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import 'cases/remote_document_cache_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  late RemoteDocumentCacheTestCase testCase;

  setUp(() async {
    print('setUp');
    final SQLitePersistence persistence = await createSQLitePersistence(
      'firebase/firestore/local/sqlite_remote_document_cache_test-${const Uuid().v4()}.db',
    );
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

  // Not in the Android SDK, which has no test that the "document_type" filter (#7295) keeps deleted and unknown
  // documents out of the scan: they are not read, so they do not count as scanned documents.
  test('queryScansSkipDeletedAndUnknownDocuments', () async {
    final SQLitePersistence persistence = await createSQLitePersistence(
      'firebase/firestore/local/sqlite_remote_document_cache_test-${const Uuid().v4()}.db',
    );
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
  });

  // The same through the `read_time` index, which reads the few documents changed after an offset: rows with a null
  // "document_type" are read and backfilled, and from then on only the found document is read.
  test('readTimeIndexReadsSkipDeletedAndUnknownDocumentsAndBackfill', () async {
    final SQLitePersistence persistence = await createSQLitePersistence(
      'firebase/firestore/local/sqlite_remote_document_cache_test-${const Uuid().v4()}.db',
    );
    try {
      await persistence.runTransaction('add documents', () async {
        await persistence.remoteDocumentCache.add(
          doc('coll/old', 1, map(<dynamic>['a', 1])),
          version(1),
        );
        await persistence.remoteDocumentCache.add(
          doc('coll/found', 2, map(<dynamic>['a', 1])),
          version(2),
        );
        await persistence.remoteDocumentCache.add(
          deletedDoc('coll/deleted', 2),
          version(2),
        );
        await persistence.remoteDocumentCache.add(
          unknownDoc('coll/unknown', 2),
          version(2),
        );
      });
      await persistence.execute(
        'UPDATE remote_documents SET document_type = NULL',
      );

      Future<(List<String>, int)> readSinceVersion1() async {
        final QueryContext context = QueryContext();
        final ImmutableSortedMap<DocumentKey, Document> results =
            await persistence.remoteDocumentCache.getAllDocumentsMatchingQuery(
              query('coll'),
              IndexOffset.createSuccessor(version(1), -1),
              context: context,
            );
        return (
          results
              .map((MapEntry<DocumentKey, Document> e) => e.key.path.toString())
              .toList(),
          context.documentReadCount,
        );
      }

      // Every changed row has a null type: all three are read.
      final (List<String> paths3, int read3) = await readSinceVersion1();
      expect(paths3, <String>['coll/found']);
      expect(read3, 3);

      final List<Map<String, dynamic>> types = await persistence.query(
        'SELECT path, document_type FROM remote_documents ORDER BY path',
      );
      expect(
        <String, Object?>{
          for (final Map<String, dynamic> row in types)
            EncodedPath.decodeResourcePath(row['path'] as String).toString():
                row['document_type'],
        },
        <String, Object?>{
          'coll/deleted': 1,
          'coll/found': 2,
          // Not changed after the offset, so not read and not backfilled.
          'coll/old': null,
          'coll/unknown': 3,
        },
      );

      // Backfilled: only the found document is read.
      final (List<String> paths1, int read1) = await readSinceVersion1();
      expect(paths1, <String>['coll/found']);
      expect(read1, 1);
    } finally {
      await persistence.shutdown();
    }
  });
}
