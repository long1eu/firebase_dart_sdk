// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/index_manager.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/resource_path.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

class IndexManagerTestCase {
  IndexManagerTestCase(this._persistence);

  final Persistence _persistence;
  IndexManager _indexManager;

  void setUp() {
    _indexManager = _persistence.indexManager;
  }

  Future<void> tearDown() async => _persistence.shutdown();

  @testMethod
  Future<void> testCanAddAndReadCollectionParentIndexEntries() async {
    await _indexManager.addToCollectionParentIndex(path('messages'));
    await _indexManager.addToCollectionParentIndex(path('messages'));
    await _indexManager.addToCollectionParentIndex(path('rooms/foo/messages'));
    await _indexManager.addToCollectionParentIndex(path('rooms/bar/messages'));
    await _indexManager.addToCollectionParentIndex(path('rooms/foo/messages2'));

    await _assertParents(
        _indexManager, 'messages', <String>['', 'rooms/bar', 'rooms/foo']);
    await _assertParents(_indexManager, 'messages2', <String>['rooms/foo']);
    await _assertParents(_indexManager, 'messages3', <String>[]);
  }

  Future<void> _assertParents(IndexManager indexManager, String collectionId,
      List<String> expected) async {
    final List<ResourcePath> actualPaths =
        await _indexManager.getCollectionParents(collectionId);
    final List<String> actual = <String>[];
    for (ResourcePath actualPath in actualPaths) {
      actual.add(actualPath.toString());
    }
    expected.sort();
    actual.sort();
    expect(actual, expected);
  }
}
