// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/persistence.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/persistance/remote_document_cache.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

class RemoteDocumentCacheTestCase {
  RemoteDocumentCacheTestCase(this._persistence);

  final Persistence _persistence;

  late RemoteDocumentCache _remoteDocumentCache;

  void setUp() {
    _remoteDocumentCache = _persistence.remoteDocumentCache;
  }

  Future<void> tearDown() async => _persistence.shutdown();

  @testMethod
  Future<void> testReadDocumentNotInCache() async {
    expect(await _get('a/b'), isNull);
  }

  @testMethod
  Future<void> testSetAndReadDocument() async {
    final List<String> paths = <String>['a/b', 'a/b/c/d/e/f'];
    for (String path in paths) {
      final Document written = await _addTestDocumentAtPath(path);
      final MaybeDocument? read = await _get(path);
      expect(read, written);
    }
  }

  @testMethod
  Future<void> testSetAndReadSeveralDocuments() async {
    final List<String> paths = <String>['a/b', 'a/b/c/d/e/f'];

    final Map<DocumentKey, MaybeDocument?> written =
        <DocumentKey, MaybeDocument?>{};
    for (String path in paths) {
      written[DocumentKey.fromPathString(path)] =
          await _addTestDocumentAtPath(path);
    }

    final Map<DocumentKey, MaybeDocument?> read = await _getAll(paths);
    expect(read, written);
  }

  @testMethod
  Future<void> testReadSeveralDocumentsIncludingMissingDocument() async {
    final List<String> paths = <String>['foo/1', 'foo/2'];
    final Map<DocumentKey, MaybeDocument?> written =
        <DocumentKey, MaybeDocument?>{};
    for (String path in paths) {
      written[DocumentKey.fromPathString(path)] =
          await _addTestDocumentAtPath(path);
    }
    written[DocumentKey.fromPathString('foo/nonexistent')] = null;

    final List<String> keys = <String>[...paths, 'foo/nonexistent'];

    final Map<DocumentKey, MaybeDocument?> read = await _getAll(keys);
    expect(read, written);
  }

  @testMethod
  Future<void> testSetAndReadLotsOfDocuments() async {
    // Make sure to force SQLite implementation to split the large query into several smaller ones.
    const int lotsOfDocuments = 2000;
    final List<String> paths = <String>[];
    final Map<DocumentKey, MaybeDocument?> expected =
        <DocumentKey, MaybeDocument?>{};
    for (int i = 0; i < lotsOfDocuments; i++) {
      final String path = 'foo/$i';
      paths.add(path);
      expected[DocumentKey.fromPathString(path)] =
          await _addTestDocumentAtPath(path);
    }

    final Map<DocumentKey, MaybeDocument?> read = await _getAll(paths);
    expect(read, expected);
  }

  @testMethod
  Future<void> testSetAndReadDeletedDocument() async {
    const String path = 'a/b';
    final NoDocument deletedDocument = deletedDoc(path, 42);
    await _add(deletedDocument, version(42));
    expect(await _get(path), deletedDocument);
  }

  @testMethod
  Future<void> testSetDocumentToNewValue() async {
    const String path = 'a/b';
    final Document written = await _addTestDocumentAtPath(path);

    final Document newDoc = doc(path, 57, map(<dynamic>['data', 5]));
    await _add(newDoc, version(57));

    expect(newDoc, isNot(written));
    expect(await _get(path), newDoc);
  }

  @testMethod
  Future<void> testRemoveDocument() async {
    const String path = 'a/b';
    await _addTestDocumentAtPath(path);
    await _remove(path);
    expect(await _get(path), isNull);
  }

  @testMethod
  Future<void> testRemoveNonExistentDocument() async {
    try {
      await _remove('a/b');
      expect(true, true);
    } catch (e) {
      assert(false, 'This should not throw.');
    }
  }

  @testMethod
  Future<void> testDocumentsMatchingQuery() async {
    // TODO(long1eu): This just verifies that we do a prefix scan against the query path. We'll need more tests once we
    //  add index support.
    final Map<String, Object> docData = map(<dynamic>['data', 2]);
    await _addTestDocumentAtPath('a/1');
    await _addTestDocumentAtPath('b/1');
    await _addTestDocumentAtPath('b/2');
    await _addTestDocumentAtPath('c/1');

    final Query query = Query(path('b'));
    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
            query, IndexOffset.none);
    final List<Document> expected = <Document>[
      doc('b/1', 42, docData),
      doc('b/2', 42, docData)
    ];

    expect(values(results), expected);
  }

  @testMethod
  Future<void> testDocumentsMatchingQuerySinceReadTime() async {
    final Map<String, Object> docData = map(<dynamic>['data', 2]);
    await _addTestDocumentAtPath('b/old', updateTime: 1, readTime: 11);
    await _addTestDocumentAtPath('b/current', updateTime: 2, readTime: 12);
    await _addTestDocumentAtPath('b/new', updateTime: 3, readTime: 13);

    final Query query = Query(path('b'));
    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
            query, IndexOffset.createSuccessor(version(12), -1));
    expect(values(results), <Document>[doc('b/new', 3, docData)]);
  }

  @testMethod
  Future<void> testDocumentsMatchingUsesReadTimeNotUpdateTime() async {
    final Map<String, Object> docData = map(<dynamic>['data', 2]);
    await _addTestDocumentAtPath('b/old', updateTime: 1, readTime: 2);
    await _addTestDocumentAtPath('b/new', updateTime: 2, readTime: 1);

    final Query query = Query(path('b'));
    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
            query, IndexOffset.createSuccessor(version(1), -1));
    expect(values(results), <Document>[doc('b/old', 1, docData)]);
  }

  @testMethod
  Future<void> testAddingDocumentWithReadTimeOfZeroFails() async {
    await expectLater(
        _add(doc('a/b', 1, map(<dynamic>['data', 2])), SnapshotVersion.none),
        throwsA(anything));
  }

  Future<Document> _addTestDocumentAtPath(String path,
      {int updateTime = 42, int readTime = 42}) async {
    final Document document =
        doc(path, updateTime, map(<dynamic>['data', 2]));
    await _add(document, version(readTime));
    return document;
  }

  Future<void> _add(MaybeDocument doc, SnapshotVersion readTime) async {
    await _persistence.runTransaction(
        'add entry', () => _remoteDocumentCache.add(doc, readTime));
  }

  Future<MaybeDocument?> _get(String path) {
    return _remoteDocumentCache.get(key(path));
  }

  Future<Map<DocumentKey, MaybeDocument?>> _getAll(Iterable<String> paths) {
    final List<DocumentKey> keys = <DocumentKey>[];

    for (String path in paths) {
      keys.add(key(path));
    }

    return _remoteDocumentCache.getAll(keys);
  }

  Future<void> _remove(String path) async {
    await _persistence.runTransaction(
        'remove entry', () => _remoteDocumentCache.remove(key(path)));
  }
}
