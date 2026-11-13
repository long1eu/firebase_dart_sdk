import 'package:cloud_firestore_dart/cloud_firestore_dart.dart' show VectorValue;
import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/sqlite/sqlite_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'persistence_test_helpers.dart';

/// The cases of index_manager.test.ts of the JS SDK ("IndexedDbIndexManager") that have no counterpart in
/// SQLiteIndexManagerTest of the Android SDK (sqlite_field_index_manager_test.dart). The JS cases that do have one
/// are listed in notes/parity/index_engine_test_map.md.
///
/// PORTING NOTE: IndexedDB numbers the indexes from 1 (an auto-increment key); SQLiteIndexManager, here as on
/// Android, from 0 (the largest id plus one). The expected ids are shifted by one.
void main() {
  late SQLitePersistence persistence;
  late IndexManager indexManager;

  setUp(() async {
    persistence = await createSQLitePersistence(
        'firebase/firestore/local/sqlite_field_index_manager_js_test-${const Uuid().v4()}.db');
    indexManager = persistence.getIndexManager(User.unauthenticated);
    await indexManager.start();
  });

  tearDown(() => persistence.shutdown());

  Future<void> addDoc(String path, Map<String, Object?> data) {
    return indexManager.updateIndexEntries(
        <DocumentKey, MaybeDocument?>{key(path): doc(path, 1, data)});
  }

  Future<void> verifyResults(Query query, List<String> documents) async {
    final Target target = query.toTarget();
    final List<DocumentKey>? results =
        await indexManager.getDocumentsMatchingTarget(target);
    expect(results, isNotNull, reason: 'Target cannot be served from index.');
    expect(results, documents.map(key).toList(), reason: 'Result for $query');
  }

  void validateIndexType(Query query, IndexType expected) {
    expect(indexManager.getIndexType(query.toTarget()), expected);
  }

  test('can add indexes', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1'));

    final List<FieldIndex> fieldIndexes = indexManager.getFieldIndexes();
    expect(fieldIndexes, hasLength(1));
    expect(fieldIndexes[0], fieldIndex('coll1', indexId: 0));
  });

  test('uses auto-incrementing index id', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1'));
    await indexManager.addFieldIndex(fieldIndex('coll2'));

    final List<FieldIndex> fieldIndexes = indexManager.getFieldIndexes();
    expect(fieldIndexes, hasLength(2));
    expect(fieldIndexes[0], fieldIndex('coll1', indexId: 0));
    expect(fieldIndexes[1], fieldIndex('coll2', indexId: 1));
  });

  test('can get indexes', () async {
    List<FieldIndex> fieldIndexes = indexManager.getFieldIndexes('coll1');
    expect(fieldIndexes, isEmpty);

    await indexManager.addFieldIndex(fieldIndex('coll1',
        fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    await indexManager.addFieldIndex(fieldIndex('coll2',
        fieldsAndKinds: <Object>['value', SegmentKind.contains]));

    fieldIndexes = indexManager.getFieldIndexes('coll1');
    expect(fieldIndexes, hasLength(1));
    expect(
        fieldIndexes[0],
        fieldIndex('coll1',
            indexId: 0,
            fieldsAndKinds: <Object>['value', SegmentKind.ascending]));

    await indexManager.addFieldIndex(fieldIndex('coll1',
        fieldsAndKinds: <Object>['newValue', SegmentKind.contains]));

    fieldIndexes = indexManager.getFieldIndexes('coll1');
    expect(fieldIndexes, hasLength(2));
    expect(
        fieldIndexes[0],
        fieldIndex('coll1',
            indexId: 0,
            fieldsAndKinds: <Object>['value', SegmentKind.ascending]));
    expect(
        fieldIndexes[1],
        fieldIndex('coll1',
            indexId: 2,
            fieldsAndKinds: <Object>['newValue', SegmentKind.contains]));
  });

  test('can update collection group', () async {
    await indexManager.addFieldIndex(fieldIndex('coll1'));
    await indexManager.addFieldIndex(fieldIndex('coll1'));
    await indexManager.addFieldIndex(fieldIndex('coll2'));

    List<FieldIndex> fieldIndexes = indexManager.getFieldIndexes();
    expect(fieldIndexes[0].indexState, IndexState(0, IndexOffset.none));
    expect(fieldIndexes[1].indexState, IndexState(0, IndexOffset.none));
    expect(fieldIndexes[2].indexState, IndexState(0, IndexOffset.none));

    final IndexOffset newOffset =
        IndexOffset(version(1337), key('coll1/doc'), 42);
    await indexManager.updateCollectionGroup('coll1', newOffset);

    fieldIndexes = indexManager.getFieldIndexes();
    expect(fieldIndexes[0].indexState, IndexState(1, newOffset));
    expect(fieldIndexes[1].indexState, IndexState(1, newOffset));
    expect(fieldIndexes[2].indexState, IndexState(0, IndexOffset.none));
  });

  test('can get next collection group to update', () async {
    expect(indexManager.getNextCollectionGroupToUpdate(), isNull);

    await indexManager.addFieldIndex(fieldIndex('coll1'));
    await indexManager.addFieldIndex(fieldIndex('coll2'));

    expect(indexManager.getNextCollectionGroupToUpdate(), 'coll1');

    await indexManager.updateCollectionGroup('coll1', IndexOffset.none);
    expect(indexManager.getNextCollectionGroupToUpdate(), 'coll2');

    await indexManager.updateCollectionGroup('coll2', IndexOffset.none);
    expect(indexManager.getNextCollectionGroupToUpdate(), 'coll1');
  });

  test(
      'deleting field index removes entry from getNextCollectionGroupToUpdate()',
      () async {
    await indexManager.addFieldIndex(fieldIndex('coll1'));
    expect(indexManager.getNextCollectionGroupToUpdate(), 'coll1');

    final FieldIndex actualIndex = indexManager.getFieldIndexes()[0];
    await indexManager.deleteFieldIndex(actualIndex);

    expect(indexManager.getNextCollectionGroupToUpdate(), isNull);
  });

  test('adds string', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['exists', SegmentKind.ascending]));
    await addDoc('coll/doc1', <String, Object?>{'exists': 'a'});
    await addDoc('coll/doc2', <String, Object?>{'exists': 'b'});
  });

  test('returns empty result when no index exists', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['count', SegmentKind.ascending]));
    await addDoc('coll/val1', <String, Object?>{'count': 1});
    await addDoc('coll/val2', <String, Object?>{'count': 2});
    await addDoc('coll/val3', <String, Object?>{'count': 3});
    final Query q = query('coll').filter(filter('unknown', '==', true));
    expect(indexManager.getIndexType(q.toTarget()), IndexType.none);
    expect(await indexManager.getDocumentsMatchingTarget(q.toTarget()), isNull);
  });

  test('can index VectorValue fields', () async {
    await indexManager.addFieldIndex(fieldIndex('coll',
        fieldsAndKinds: <Object>['embedding', SegmentKind.ascending]));

    await addDoc('coll/arr1', <String, Object?>{
      'embedding': <Object?>[1, 2, 3]
    });
    await addDoc('coll/map2', <String, Object?>{'embedding': <String, Object?>{}});
    await addDoc('coll/doc3', <String, Object?>{
      'embedding': VectorValue(<double>[4, 5, 6])
    });
    await addDoc('coll/doc4', <String, Object?>{
      'embedding': VectorValue(<double>[5])
    });

    Query q = query('coll').orderBy(orderBy('embedding'));
    await verifyResults(
        q, <String>['coll/arr1', 'coll/doc4', 'coll/doc3', 'coll/map2']);

    q = query('coll')
        .filter(filter('embedding', '==', VectorValue(<double>[4, 5, 6])));
    await verifyResults(q, <String>['coll/doc3']);

    q = query('coll')
        .filter(filter('embedding', '>', VectorValue(<double>[4, 5, 6])));
    await verifyResults(q, <String>[]);

    q = query('coll')
        .filter(filter('embedding', '>=', VectorValue(<double>[4])));
    await verifyResults(q, <String>['coll/doc4', 'coll/doc3']);
  });

  test('createTargetIndexes() does nothing if a full index already exists',
      () async {
    final Query q = query('coll');
    await indexManager.createTargetIndexes(q.toTarget());
    validateIndexType(q, IndexType.full);
    await indexManager.createTargetIndexes(q.toTarget());
    validateIndexType(q, IndexType.full);
    expect(indexManager.getFieldIndexes('coll'), hasLength(1));
  });

  test('deleteAllFieldIndexes() deletes all indexes', () async {
    // Create some indexes.
    final Query query1 = query('coll').filter(filter('a', '==', 42));
    await indexManager.createTargetIndexes(query1.toTarget());
    validateIndexType(query1, IndexType.full);
    final Query query2 = query('coll').filter(filter('b', '==', 42));
    await indexManager.createTargetIndexes(query2.toTarget());
    validateIndexType(query2, IndexType.full);

    // Verify that deleteAllFieldIndexes() deletes the indexes.
    await indexManager.deleteAllFieldIndexes();
    validateIndexType(query1, IndexType.none);
    validateIndexType(query2, IndexType.none);
  });
}
