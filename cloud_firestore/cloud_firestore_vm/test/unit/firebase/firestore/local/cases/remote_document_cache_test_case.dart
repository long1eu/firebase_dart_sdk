// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/persistence.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/persistence/remote_document_cache.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

class RemoteDocumentCacheTestCase {
  RemoteDocumentCacheTestCase(this._persistence);

  final Persistence _persistence;

  RemoteDocumentCache _remoteDocumentCache;

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
      final MaybeDocument read = await _get(path);
      expect(read, written);
    }
  }

  @testMethod
  Future<void> testSetAndReadSeveralDocuments() async {
    final List<String> paths = <String>['a/b', 'a/b/c/d/e/f'];

    final Map<DocumentKey, MaybeDocument> written =
        <DocumentKey, MaybeDocument>{};
    for (String path in paths) {
      written[DocumentKey.fromPathString(path)] =
          await _addTestDocumentAtPath(path);
    }

    final Map<DocumentKey, MaybeDocument> read = await _getAll(paths);
    expect(read, written);
  }

  @testMethod
  Future<void> testReadSeveralDocumentsIncludingMissingDocument() async {
    final List<String> paths = <String>['foo/1', 'foo/2'];
    final Map<DocumentKey, MaybeDocument> written =
        <DocumentKey, MaybeDocument>{};
    for (String path in paths) {
      written[DocumentKey.fromPathString(path)] =
          await _addTestDocumentAtPath(path);
    }
    written[DocumentKey.fromPathString('foo/nonexistent')] = null;

    final List<String> keys = <String>[...paths, 'foo/nonexistent'];

    final Map<DocumentKey, MaybeDocument> read = await _getAll(keys);
    expect(read, written);
  }

  @testMethod
  Future<void> testSetAndReadLotsOfDocuments() async {
    // Make sure to force SQLite implementation to split the large query into several smaller ones.
    const int lotsOfDocuments = 2000;
    final List<String> paths = <String>[];
    final Map<DocumentKey, MaybeDocument> expected =
        <DocumentKey, MaybeDocument>{};
    for (int i = 0; i < lotsOfDocuments; i++) {
      final String path = 'foo/$i';
      paths.add(path);
      expected[DocumentKey.fromPathString(path)] =
          await _addTestDocumentAtPath(path);
    }

    final Map<DocumentKey, MaybeDocument> read = await _getAll(paths);
    expect(read, expected);
  }

  @testMethod
  Future<void> testSetAndReadDeletedDocument() async {
    const String path = 'a/b';
    final NoDocument deletedDocument = deletedDoc(path, 42);
    await _add(deletedDocument);
    expect(await _get(path), deletedDocument);
  }

  @testMethod
  Future<void> testSetDocumentToNewValue() async {
    const String path = 'a/b';
    final Document written = await _addTestDocumentAtPath(path);

    final Document newDoc = doc(path, 57, map(<dynamic>['data', 5]));
    await _add(newDoc);

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
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(query);
    final List<Document> expected = <Document>[
      doc('b/1', 42, docData),
      doc('b/2', 42, docData)
    ];

    expect(values(results), expected);
  }

  Future<Document> _addTestDocumentAtPath(String path) async {
    final Document document = doc(path, 42, map(<dynamic>['data', 2]));
    await _add(document);
    return document;
  }

  Future<void> _add(MaybeDocument doc) async {
    await _persistence.runTransaction(
        'add entry', () => _remoteDocumentCache.add(doc));
  }

  Future<MaybeDocument> _get(String path) {
    return _remoteDocumentCache.get(key(path));
  }

  Future<Map<DocumentKey, MaybeDocument>> _getAll(Iterable<String> paths) {
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
