// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/firebase/firestore/auth/user.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/memory/memory_persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../util/index_helpers.dart';
import '../../../../util/test_util.dart';
import 'cases/index_manager_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  late IndexManagerTestCase testCase;

  setUp(() async {
    print('setUp');
    final MemoryPersistence persistence =
        await createEagerGCMemoryPersistence();
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

  // Port of the JS SDK's "MemoryIndexManager" tests (index_manager.test.ts): the parents come back sorted, and the
  // memory cache has no field indexes.
  group('JS MemoryIndexManager', () {
    late MemoryPersistence persistence;
    late IndexManager indexManager;

    setUp(() async {
      persistence = await createEagerGCMemoryPersistence();
      indexManager = persistence.getIndexManager(User.unauthenticated);
      await indexManager.start();
    });

    tearDown(() => persistence.shutdown());

    test('can add and read collection=>parent index entries', () async {
      await indexManager.addToCollectionParentIndex(path('rooms/foo/messages'));
      await indexManager.addToCollectionParentIndex(path('messages'));
      await indexManager.addToCollectionParentIndex(path('messages'));
      await indexManager.addToCollectionParentIndex(path('rooms/bar/messages'));
      await indexManager.addToCollectionParentIndex(
        path('rooms/foo/messages2'),
      );

      expect(
        await indexManager.getCollectionParents('messages'),
        <ResourcePath>[path(''), path('rooms/bar'), path('rooms/foo')],
      );
      expect(
        await indexManager.getCollectionParents('messages2'),
        <ResourcePath>[path('rooms/foo')],
      );
      expect(
        await indexManager.getCollectionParents('messages3'),
        <ResourcePath>[],
      );
    });

    test('field index methods are no-ops', () async {
      final FieldIndex index = fieldIndex(
        'coll',
        fieldsAndKinds: <Object>['a', SegmentKind.ascending],
      );
      final Target target = query(
        'coll',
      ).filter(filter('a', '==', 1)).toTarget();

      await indexManager.addFieldIndex(index);
      await indexManager.createTargetIndexes(target);
      await indexManager.updateIndexEntries(<DocumentKey, MaybeDocument?>{
        key('coll/a'): doc('coll/a', 1, map(<dynamic>['a', 1])),
      });
      await indexManager.updateCollectionGroup('coll', IndexOffset.none);

      expect(indexManager.getFieldIndexes(), isEmpty);
      expect(indexManager.getFieldIndexes('coll'), isEmpty);
      expect(indexManager.getIndexType(target), IndexType.none);
      expect(await indexManager.getDocumentsMatchingTarget(target), isNull);
      expect(indexManager.getNextCollectionGroupToUpdate(), isNull);
      expect(indexManager.getMinOffset('coll'), IndexOffset.none);

      await indexManager.deleteFieldIndex(index);
      await indexManager.deleteAllFieldIndexes();
    });
  });
}
