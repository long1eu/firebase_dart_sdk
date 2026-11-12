import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/index_backfiller.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/local_documents_view.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/document_overlay_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// `TestUtil.version(seconds, nanos)` of the Android SDK.
SnapshotVersion versionAt(int seconds, int nanos) =>
    SnapshotVersion(Timestamp(seconds, nanos));

/// Port of IndexBackfillerTest of the Android SDK.
void main() {
  late SQLitePersistence persistence;
  late IndexManager indexManager;
  late RemoteDocumentCache remoteDocumentCache;
  late DocumentOverlayCache documentOverlayCache;
  late IndexBackfiller backfiller;

  setUp(() async {
    persistence = await createSQLitePersistence(
        'firebase/firestore/local/index_backfiller_test-${const Uuid().v4()}.db');
    remoteDocumentCache = persistence.remoteDocumentCache;
    documentOverlayCache =
        persistence.getDocumentOverlayCache(User.unauthenticated);
    indexManager = persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();
    final LocalDocumentsView localDocumentsView = LocalDocumentsView(
      remoteDocumentCache: remoteDocumentCache,
      mutationQueue: persistence.getMutationQueue(User.unauthenticated),
      documentOverlayCache: documentOverlayCache,
      indexManager: indexManager,
    );
    backfiller = IndexBackfiller.forTesting(
        persistence, () => indexManager, () => localDocumentsView);
  });

  tearDown(() => persistence.shutdown());

  Future<void> addFieldIndex(String collectionGroup, String fieldName,
      {SnapshotVersion? readTime, int? sequenceNumber}) {
    final IndexState? indexState = readTime != null
        ? IndexState(0, IndexOffset(readTime, DocumentKey.empty(), -1))
        : sequenceNumber != null
            ? IndexState(sequenceNumber, IndexOffset.none)
            : null;
    return indexManager.addFieldIndex(fieldIndex(collectionGroup,
        indexState: indexState,
        fieldsAndKinds: <Object>[fieldName, SegmentKind.ascending]));
  }

  Future<void> verifyQueryResults(
      Query query, List<String> expectedKeys) async {
    final Target target = query.toTarget();
    final List<DocumentKey>? actualKeys =
        await indexManager.getDocumentsMatchingTarget(target);
    if (actualKeys == null) {
      expect(expectedKeys, isEmpty);
    } else {
      expect(actualKeys, unorderedEquals(expectedKeys.map(key)));
    }
  }

  /// Creates a document and adds it to the RemoteDocumentCache.
  Future<void> addDoc(
      String path, SnapshotVersion readTime, String field, int value) {
    return remoteDocumentCache.add(
        doc(path, 10, map(<dynamic>[field, value])), readTime);
  }

  /// Adds a set mutation to a batch with the specified id for every specified document path.
  Future<void> addSetMutationsToOverlay(int batchId, List<String> paths) {
    return documentOverlayCache.saveOverlays(batchId, <DocumentKey, Mutation>{
      for (final String path in paths)
        key(path): setMutation(path, map(<dynamic>['foo', 'bar'])),
    });
  }

  Future<void> addMutationToOverlay(String path, Mutation mutation) {
    return documentOverlayCache
        .saveOverlays(5, <DocumentKey, Mutation>{key(path): mutation});
  }

  test('testBackfillWritesLatestReadTimeToFieldIndexOnCompletion', () async {
    await addFieldIndex('coll1', 'foo');
    await addFieldIndex('coll2', 'bar');
    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addDoc('coll2/docA', version(20), 'bar', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);

    FieldIndex fieldIndex1 = indexManager.getFieldIndexes('coll1').first;
    FieldIndex fieldIndex2 = indexManager.getFieldIndexes('coll2').first;
    expect(fieldIndex1.indexState.offset.readTime, version(10));
    expect(fieldIndex2.indexState.offset.readTime, version(20));

    await addDoc('coll1/docB', versionAt(50, 10), 'foo', 1);
    await addDoc('coll1/docC', version(50), 'foo', 1);
    await addDoc('coll2/docB', version(60), 'bar', 1);
    await addDoc('coll2/docC', versionAt(60, 10), 'bar', 1);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 4);

    fieldIndex1 = indexManager.getFieldIndexes('coll1').first;
    fieldIndex2 = indexManager.getFieldIndexes('coll2').first;
    expect(fieldIndex1.indexState.offset.readTime, versionAt(50, 10));
    expect(fieldIndex2.indexState.offset.readTime, versionAt(60, 10));
  });

  test('testBackfillFetchesDocumentsAfterEarliestReadTime', () async {
    await addFieldIndex('coll1', 'foo', readTime: version(10));

    // Documents before read time should not be fetched.
    await addDoc('coll1/docA', version(9), 'foo', 1);
    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 0);

    // Read time should be the highest read time from the cache.
    expect(indexManager.getFieldIndexes('coll1').first.indexState.offset,
        IndexOffset(version(10), DocumentKey.empty(), -1));

    // Documents that are after the earliest read time but before field index read time are fetched.
    await addDoc('coll1/docB', version(19), 'boo', 1);
    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    // Field indexes should now hold the latest read time
    expect(
        indexManager.getFieldIndexes('coll1').first.indexState.offset.readTime,
        version(19));
  });

  test('testBackfillWritesIndexEntries', () async {
    await addFieldIndex('coll1', 'foo');
    await addFieldIndex('coll2', 'bar');
    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addDoc('coll1/docB', version(10), 'boo', 1);
    await addDoc('coll2/docA', version(10), 'bar', 1);
    await addDoc('coll2/docB', version(10), 'car', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 4);
  });

  test('testBackfillWritesOldestDocumentFirst', () async {
    backfiller.maxDocumentsToProcess = 2;

    await addFieldIndex('coll1', 'foo');
    await addDoc('coll1/docA', version(5), 'foo', 1);
    await addDoc('coll1/docB', version(3), 'foo', 1);
    await addDoc('coll1/docC', version(10), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);

    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB']);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB', 'coll1/docC']);
  });

  test('testBackfillUsesDocumentKeyOffsetForLargeSnapshots', () async {
    backfiller.maxDocumentsToProcess = 2;

    await addFieldIndex('coll1', 'foo');
    await addDoc('coll1/docA', version(1), 'foo', 1);
    await addDoc('coll1/docB', version(1), 'foo', 1);
    await addDoc('coll1/docC', version(1), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);

    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB']);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB', 'coll1/docC']);
  });

  test('testBackfillUpdatesCollectionGroups', () async {
    backfiller.maxDocumentsToProcess = 2;

    await addFieldIndex('coll1', 'foo');
    await addFieldIndex('coll2', 'foo');

    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addDoc('coll1/docB', version(20), 'foo', 1);
    await addDoc('coll2/docA', version(30), 'foo', 1);

    String? collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect(collectionGroup, 'coll1');

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);

    // Check that coll1 was backfilled and that coll2 is next
    collectionGroup = indexManager.getNextCollectionGroupToUpdate();
    expect(collectionGroup, 'coll2');
  });

  test('testBackfillPrioritizesNewCollectionGroups', () async {
    backfiller.maxDocumentsToProcess = 1;

    // In this test case, `coll3` is a new collection group that hasn't been indexed, so it should
    // be processed ahead of the other collection groups.
    await addFieldIndex('coll1', 'foo',
        sequenceNumber: /* sequenceNumber= */ 1);
    await addFieldIndex('coll2', 'foo',
        sequenceNumber: /* sequenceNumber= */ 2);
    await addFieldIndex('coll3', 'foo',
        sequenceNumber: /* sequenceNumber= */ 0);

    await addDoc('coll1/doc', version(10), 'foo', 1);
    await addDoc('coll2/doc', version(20), 'foo', 1);
    await addDoc('coll3/doc', version(30), 'foo', 1);

    // Check that coll3 is the next collection ID the backfiller should update
    expect(indexManager.getNextCollectionGroupToUpdate(), 'coll3');

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    await verifyQueryResults(
        query('coll3').orderBy(orderBy('foo')), <String>['coll3/doc']);
  });

  test('testBackfillWritesUntilCap', () async {
    backfiller.maxDocumentsToProcess = 3;
    await addFieldIndex('coll1', 'foo');
    await addFieldIndex('coll2', 'foo');
    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addDoc('coll1/docB', version(20), 'foo', 1);
    await addDoc('coll2/docA', version(30), 'foo', 1);
    await addDoc('coll2/docA', version(40), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 3);

    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB']);
    await verifyQueryResults(
        query('coll2').orderBy(orderBy('foo')), <String>['coll2/docA']);
  });

  test('testBackfillUsesLatestReadTimeForEmptyCollections', () async {
    await addFieldIndex('coll', 'foo', readTime: version(1));
    await addDoc('readtime/doc', version(1), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 0);

    await addDoc('coll/ignored', version(2), 'foo', 1);
    await addDoc('coll/added', version(3), 'foo', 1);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
  });

  test('testBackfillHandlesLocalMutationsAfterRemoteDocs', () async {
    backfiller.maxDocumentsToProcess = 2;
    await addFieldIndex('coll1', 'foo');

    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addDoc('coll1/docB', version(20), 'foo', 1);
    await addDoc('coll1/docC', version(30), 'foo', 1);
    await addSetMutationsToOverlay(1, <String>['coll1/docD']);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB']);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB', 'coll1/docC', 'coll1/docD']);
  });

  test('testBackfillMutationsUpToDocumentLimitAndUpdatesBatchIdOnIndex',
      () async {
    backfiller.maxDocumentsToProcess = 2;
    await addFieldIndex('coll1', 'foo');
    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addSetMutationsToOverlay(2, <String>['coll1/docB']);
    await addSetMutationsToOverlay(3, <String>['coll1/docC']);
    await addSetMutationsToOverlay(4, <String>['coll1/docD']);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB']);
    FieldIndex fieldIndex = indexManager.getFieldIndexes('coll1').first;
    expect(fieldIndex.indexState.offset.largestBatchId, 2);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB', 'coll1/docC', 'coll1/docD']);
    fieldIndex = indexManager.getFieldIndexes('coll1').first;
    expect(fieldIndex.indexState.offset.largestBatchId, 4);
  });

  test('testBackfillMutationFinishesMutationBatchEvenIfItExceedsLimit',
      () async {
    backfiller.maxDocumentsToProcess = 2;
    await addFieldIndex('coll1', 'foo');
    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addSetMutationsToOverlay(
        2, <String>['coll1/docB', 'coll1/docC', 'coll1/docD']);
    await addSetMutationsToOverlay(3, <String>['coll1/docE']);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 4);
    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB', 'coll1/docC', 'coll1/docD']);
  });

  test('testBackfillMutationsFromHighWaterMark', () async {
    backfiller.maxDocumentsToProcess = 2;
    await addFieldIndex('coll1', 'foo');
    await addDoc('coll1/docA', version(10), 'foo', 1);
    await addSetMutationsToOverlay(3, <String>['coll1/docB']);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
    await verifyQueryResults(query('coll1').orderBy(orderBy('foo')),
        <String>['coll1/docA', 'coll1/docB']);

    await addSetMutationsToOverlay(1, <String>['coll1/docC']);
    await addSetMutationsToOverlay(2, <String>['coll1/docD']);
    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 0);
  });

  test('testBackfillUpdatesExistingDocToNewValue', () async {
    Query queryA = query('coll').filter(filter('foo', '==', 2));
    await addFieldIndex('coll', 'foo');

    await addDoc('coll/doc', version(10), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);
    await verifyQueryResults(queryA, <String>[]);

    // Update doc to new remote version with new value.
    await addDoc('coll/doc', version(40), 'foo', 2);
    await backfiller.backfill();

    await verifyQueryResults(queryA, <String>['coll/doc']);
  });

  test('testBackfillUpdatesDocsThatNoLongerMatch', () async {
    Query queryA = query('coll').filter(filter('foo', '>', 0));
    await addFieldIndex('coll', 'foo');
    await addDoc('coll/doc', version(10), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);
    await verifyQueryResults(queryA, <String>['coll/doc']);

    // Update doc to new remote version with new value that doesn't match field index.
    await addDoc('coll/doc', version(40), 'foo', -1);

    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);
    await verifyQueryResults(queryA, <String>[]);
  });

  test('testBackfillDoesNotProcessSameDocumentTwice', () async {
    await addFieldIndex('coll', 'foo');
    await addDoc('coll/doc', version(5), 'foo', 1);
    await addSetMutationsToOverlay(1, <String>['coll/doc']);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    FieldIndex fieldIndex = indexManager.getFieldIndexes('coll').first;
    expect(fieldIndex.indexState.offset.readTime, version(5));
    expect(fieldIndex.indexState.offset.largestBatchId, 1);
  });

  test('testBackfillAppliesSetToRemoteDoc', () async {
    await addFieldIndex('coll', 'foo');
    await addDoc('coll/doc', version(5), 'boo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    Mutation patch = patchMutation('coll/doc', map(<dynamic>['foo', 1]));
    await addMutationToOverlay('coll/doc', patch);
    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    await verifyQueryResults(
        query('coll').orderBy(orderBy('foo')), <String>['coll/doc']);
  });

  test('testBackfillAppliesPatchToRemoteDoc', () async {
    Query queryA = query('coll').orderBy(orderBy('a'));
    Query queryB = query('coll').orderBy(orderBy('b'));

    await addFieldIndex('coll', 'a');
    await addFieldIndex('coll', 'b');
    await addDoc('coll/doc', version(5), 'a', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    await verifyQueryResults(queryA, <String>['coll/doc']);
    await verifyQueryResults(queryB, <String>[]);

    Mutation patch = patchMutation('coll/doc', map(<dynamic>['b', 1]));
    await addMutationToOverlay('coll/doc', patch);
    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    await verifyQueryResults(queryA, <String>['coll/doc']);
    await verifyQueryResults(queryB, <String>['coll/doc']);
  });

  test('testBackfillAppliesDeleteToRemoteDoc', () async {
    await addFieldIndex('coll', 'foo');
    await addDoc('coll/doc', version(5), 'foo', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    Mutation deleteM = deleteMutation('coll/doc');
    await addMutationToOverlay('coll/doc', deleteM);
    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 1);

    Target target = query('coll').filter(filter('foo', '==', 2)).toTarget();
    final List<DocumentKey>? matching =
        await indexManager.getDocumentsMatchingTarget(target);
    expect(matching!.isEmpty, isTrue);
  });

  test('testReindexesDocumentsWhenNewIndexIsAdded', () async {
    Query queryA = query('coll').orderBy(orderBy('a'));
    Query queryB = query('coll').orderBy(orderBy('b'));

    await addFieldIndex('coll', 'a');
    await addDoc('coll/doc1', version(1), 'a', 1);
    await addDoc('coll/doc2', version(1), 'b', 1);

    int documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);
    await verifyQueryResults(queryA, <String>['coll/doc1']);
    await verifyQueryResults(queryB, <String>[]);

    await addFieldIndex('coll', 'b');
    documentsProcessed = await backfiller.backfill();
    expect(documentsProcessed, 2);

    await verifyQueryResults(queryA, <String>['coll/doc1']);
    await verifyQueryResults(queryB, <String>['coll/doc2']);
  });
}
