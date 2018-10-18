// File created by
// Lung Razvan <long1eu>
// on 02/10/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/no_document.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';
import 'cases/remote_document_cache_test_case.dart';
import 'persistence_test_helpers.dart';

void main() {
  RemoteDocumentCacheTestCase testCase;
  RemoteDocumentCache remoteDocumentCache;

  setUp(() async {
    print('setUp');

    final MemoryPersistence persistence =
        await createEagerGCMemoryPersistence();

    testCase = RemoteDocumentCacheTestCase(persistence)..setUp();
    remoteDocumentCache = testCase.remoteDocumentCache;

    print('setUpDone');
  });

  tearDown(() => Future<void>.delayed(
      const Duration(milliseconds: 250), () => testCase.tearDown()));

  test('testReadDocumentNotInCache', () async {
    expect(await testCase.get('a/b'), isNull);
  });

  test('testSetAndReadDocument', () async {
    final List<String> paths = <String>['a/b', 'a/b/c/d/e/f'];
    for (String path in paths) {
      final Document written = await testCase.addTestDocumentAtPath(path);
      final MaybeDocument read = await testCase.get(path);
      expect(read, written);
    }
  });

  test('testSetAndReadDeletedDocument', () async {
    const String path = 'a/b';
    final NoDocument deletedDocument = deletedDoc(path, 42);
    await testCase.add(deletedDocument);
    expect(await testCase.get(path), deletedDocument);
  });

  test('testSetDocumentToNewValue', () async {
    const String path = 'a/b';
    final Document written = await testCase.addTestDocumentAtPath(path);

    final Document newDoc = doc(path, 57, map(<dynamic>['data', 5]));
    await testCase.add(newDoc);

    expect(newDoc, isNot(written));
    expect(await testCase.get(path), newDoc);
  });

  test('testRemoveDocument', () async {
    const String path = 'a/b';
    await testCase.addTestDocumentAtPath(path);
    await testCase.remove(path);
    expect(await testCase.get(path), isNull);
  });

  test('testRemoveNonExistentDocument', () async {
    try {
      await testCase.remove('a/b');
      expect(true, true);
    } catch (e) {
      assert(false, 'This should not throw.');
    }
  });

  test('testDocumentsMatchingQuery', () async {
    // TODO: This just verifies that we do a prefix scan against the
    // query path. We'll need more tests once we add index support.
    final Map<String, Object> docData = map(<dynamic>['data', 2]);
    await testCase.addTestDocumentAtPath('a/1');
    await testCase.addTestDocumentAtPath('b/1');
    await testCase.addTestDocumentAtPath('b/2');
    await testCase.addTestDocumentAtPath('c/1');

    final Query query = Query.atPath(path('b'));
    final ImmutableSortedMap<DocumentKey, Document> results =
        await remoteDocumentCache.getAllDocumentsMatchingQuery(query);
    final List<Document> expected = <Document>[
      doc('b/1', 42, docData),
      doc('b/2', 42, docData)
    ];

    expect(values(results), expected);
  });
}
