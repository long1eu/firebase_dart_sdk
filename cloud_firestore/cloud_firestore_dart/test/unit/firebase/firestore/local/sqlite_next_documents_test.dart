import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// The scans that feed the index backfill: the `getAll(collectionGroup, offset, limit)` cases of
/// SQLiteRemoteDocumentCacheTest of the Android SDK, and own cases for `LocalDocumentsView.getNextDocuments` (upstream
/// covers it through IndexBackfillerTest).
void main() {
  late SQLitePersistence persistence;
  late RemoteDocumentCache remoteDocumentCache;
  late DocumentOverlayCache overlayCache;
  late LocalDocumentsView localDocuments;

  setUp(() async {
    persistence = await createSQLitePersistence(
        'firebase/firestore/local/sqlite_next_documents_test-${const Uuid().v4()}.db');
    remoteDocumentCache = persistence.remoteDocumentCache;
    overlayCache = persistence.getDocumentOverlayCache(User.unauthenticated);
    localDocuments = LocalDocumentsView(
      remoteDocumentCache: remoteDocumentCache,
      mutationQueue: persistence.getMutationQueue(User.unauthenticated),
      documentOverlayCache: overlayCache,
      indexManager: persistence.indexManager,
    );
  });

  tearDown(() => persistence.shutdown());

  Future<void> addTestDocumentAtPath(String path,
      {int updateTime = 42, int readTime = 42}) {
    return persistence.runTransaction('addTestDocumentAtPath', () async {
      await remoteDocumentCache.add(
          doc(path, updateTime, map(<dynamic>['data', 2])), version(readTime));
    });
  }

  Future<Map<DocumentKey, ReadDocument>> getAll(
      String collectionGroup, IndexOffset offset, int limit) {
    return persistence.runTransactionAndReturn(
        'getAll',
        () => remoteDocumentCache.getAllForCollectionGroup(
            collectionGroup, offset, limit));
  }

  // 2^53 - 1 stands in for Integer.MAX_VALUE.
  const int noLimit = 9007199254740991;

  group('RemoteDocumentCache.getAllForCollectionGroup', () {
    test('testNextDocumentsFromCollectionGroup', () async {
      await addTestDocumentAtPath('a/1');
      await addTestDocumentAtPath('a/2');
      await addTestDocumentAtPath('b/3');

      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset.none, noLimit);
      expect(
          results.keys, unorderedEquals(<DocumentKey>[key('a/1'), key('a/2')]));
    });

    test('testNextDocumentsFromCollectionGroupWithLimit', () async {
      await addTestDocumentAtPath('a/1', updateTime: 1, readTime: 11);
      await addTestDocumentAtPath('b/2/a/2', updateTime: 1, readTime: 12);
      await addTestDocumentAtPath('a/3', updateTime: 1, readTime: 13);

      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset.none, 2);
      expect(results.keys,
          unorderedEquals(<DocumentKey>[key('a/1'), key('b/2/a/2')]));
    });

    test('testNextDocumentsFromCollectionGroupWithOffset', () async {
      await addTestDocumentAtPath('a/1', updateTime: 1, readTime: 11);
      await addTestDocumentAtPath('b/2/a/2', updateTime: 2, readTime: 12);
      await addTestDocumentAtPath('a/3', updateTime: 3, readTime: 13);

      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset.createSuccessor(version(11), -1), 2);
      expect(results.keys,
          unorderedEquals(<DocumentKey>[key('b/2/a/2'), key('a/3')]));
    });

    test('testNextDocumentsFromNonExistingCollectionGroup', () async {
      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset.createSuccessor(version(11), -1), 2);
      expect(results, isEmpty);
    });

    test('testNextDocumentsForLargeCollectionGroup', () async {
      const int size = 999 ~/ SQLiteRemoteDocumentCache.bindsPerStatement + 1;
      await persistence.runTransaction('add', () async {
        for (int i = 0; i < size; ++i) {
          await remoteDocumentCache.add(
              doc('a/$i/b/doc', 42, map(<dynamic>['data', 2])), version(42));
        }
      });
      final Map<DocumentKey, ReadDocument> results =
          await getAll('b', IndexOffset.none, size);
      expect(results, hasLength(size));
    });

    // Not upstream.
    test('returns the read times and orders by read time, then key', () async {
      await addTestDocumentAtPath('a/3', updateTime: 1, readTime: 20);
      await addTestDocumentAtPath('a/2', updateTime: 5, readTime: 10);
      await addTestDocumentAtPath('a/1', updateTime: 9, readTime: 10);

      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset.none, noLimit);
      expect(results.keys.toList(),
          <DocumentKey>[key('a/1'), key('a/2'), key('a/3')]);
      expect(results[key('a/1')]!.readTime, version(10));
      expect(results[key('a/3')]!.readTime, version(20));
      // The read time is not the version of the document.
      expect(results[key('a/1')]!.document.version, version(9));
    });

    test('the offset skips the documents up to its key for the same read time',
        () async {
      await addTestDocumentAtPath('a/1', readTime: 10);
      await addTestDocumentAtPath('a/2', readTime: 10);
      await addTestDocumentAtPath('a/3', readTime: 10);

      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset(version(10), key('a/2'), -1), noLimit);
      expect(results.keys.toList(), <DocumentKey>[key('a/3')]);
    });

    test('skips the documents of subcollections and includes deleted documents',
        () async {
      await addTestDocumentAtPath('a/1');
      await addTestDocumentAtPath('a/1/other/2');
      await persistence.runTransaction('add', () async {
        await remoteDocumentCache.add(deletedDoc('a/gone', 3), version(50));
      });

      final Map<DocumentKey, ReadDocument> results =
          await getAll('a', IndexOffset.none, noLimit);
      expect(results.keys.toList(), <DocumentKey>[key('a/1'), key('a/gone')]);
      expect(results[key('a/gone')]!.document, isA<NoDocument>());
    });

    test('is not supported by memory persistence', () async {
      final MemoryPersistence memory = await createEagerGCMemoryPersistence();
      addTearDown(memory.shutdown);
      expect(
          () => memory.remoteDocumentCache
              .getAllForCollectionGroup('a', IndexOffset.none, 1),
          throwsUnsupportedError);
    });
  });

  group('LocalDocumentsView.getNextDocuments', () {
    Future<void> saveOverlays(int batchId, List<Mutation> mutations) {
      return persistence.runTransaction('saveOverlays', () async {
        await overlayCache.saveOverlays(batchId, <DocumentKey, Mutation>{
          for (final Mutation mutation in mutations) mutation.key: mutation,
        });
      });
    }

    Future<LocalDocumentsResult> next(IndexOffset offset, int count) {
      return persistence.runTransactionAndReturn('getNextDocuments',
          () => localDocuments.getNextDocuments('coll', offset, count));
    }

    test('returns remote documents in read time order with their read times',
        () async {
      await addTestDocumentAtPath('coll/b', updateTime: 1, readTime: 20);
      await addTestDocumentAtPath('coll/a', updateTime: 2, readTime: 10);
      await addTestDocumentAtPath('other/c', updateTime: 3, readTime: 5);

      final LocalDocumentsResult result = await next(IndexOffset.none, 10);
      expect(result.documents.keys.toList(),
          <DocumentKey>[key('coll/a'), key('coll/b')]);
      expect(result.readTimes, <DocumentKey, SnapshotVersion>{
        key('coll/a'): version(10),
        key('coll/b'): version(20),
      });
      expect(result.batchId, FieldIndex.initialLargestBatchId);
    });

    test('applies the overlays of the remote documents', () async {
      await addTestDocumentAtPath('coll/a', readTime: 10);
      await saveOverlays(3, <Mutation>[
        patchMutation('coll/a', map(<dynamic>['data', 7]))
      ]);

      final LocalDocumentsResult result = await next(IndexOffset.none, 10);
      final Document local = result.documents[key('coll/a')]! as Document;
      expect(local.getField(field('data'))!.value, 7);
      expect(local.hasLocalMutations, isTrue);
      // The limit left room for overlays, so the overlay of the document was read with them and reports its batch.
      expect(result.batchId, 3);
    });

    test('returns documents that only exist as mutations after the remote ones',
        () async {
      await addTestDocumentAtPath('coll/a', readTime: 10);
      await saveOverlays(5, <Mutation>[
        setMutation('coll/local', map(<dynamic>['data', 1]))
      ]);

      // The limit is used up by the remote document: no overlay is read.
      LocalDocumentsResult result = await next(IndexOffset.none, 1);
      expect(result.documents.keys.toList(), <DocumentKey>[key('coll/a')]);
      expect(result.batchId, FieldIndex.initialLargestBatchId);

      result = await next(IndexOffset.none, 10);
      expect(result.documents.keys.toSet(),
          <DocumentKey>{key('coll/a'), key('coll/local')});
      expect(result.batchId, 5);
      expect(result.readTimes[key('coll/local')], SnapshotVersion.none);
      expect(
          (result.documents[key('coll/local')]! as Document).hasLocalMutations,
          isTrue);
    });

    test('the batch id of the offset skips the overlays that were processed',
        () async {
      await saveOverlays(1, <Mutation>[
        setMutation('coll/one', map(<dynamic>['data', 1]))
      ]);
      await saveOverlays(2, <Mutation>[
        setMutation('coll/two', map(<dynamic>['data', 2]))
      ]);

      LocalDocumentsResult result = await next(
          IndexOffset(SnapshotVersion.none, DocumentKey.empty(), 1), 10);
      expect(result.documents.keys.toList(), <DocumentKey>[key('coll/two')]);
      expect(result.batchId, 2);

      result = await next(
          IndexOffset(SnapshotVersion.none, DocumentKey.empty(), 2), 10);
      expect(result.documents, isEmpty);
      expect(result.batchId, FieldIndex.initialLargestBatchId);
    });

    test('a locally deleted document has no local view', () async {
      await addTestDocumentAtPath('coll/a', readTime: 10);
      await saveOverlays(4, <Mutation>[deleteMutation('coll/a')]);

      final LocalDocumentsResult result = await next(IndexOffset.none, 10);
      expect(result.documents.keys.toList(), <DocumentKey>[key('coll/a')]);
      final MaybeDocument? local = result.documents[key('coll/a')];
      expect(local, isNot(isA<Document>()));
    });
  });
}
