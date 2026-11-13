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
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../../util/test_util.dart';

class RemoteDocumentCacheTestCase {
  RemoteDocumentCacheTestCase(this._persistence);

  final Persistence _persistence;

  late RemoteDocumentCache _remoteDocumentCache;

  final Map<String, Object> _docData = map(<dynamic>['data', 2]);

  SnapshotVersion _versionAt(int seconds, int nanos) =>
      SnapshotVersion(Timestamp(seconds, nanos));

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
      written[DocumentKey.fromPathString(path)] = await _addTestDocumentAtPath(
        path,
      );
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
      written[DocumentKey.fromPathString(path)] = await _addTestDocumentAtPath(
        path,
      );
    }
    written[DocumentKey.fromPathString('foo/nonexistent')] = null;

    final List<String> keys = <String>[...paths, 'foo/nonexistent'];

    final Map<DocumentKey, MaybeDocument?> read = await _getAll(keys);
    expect(read, written);
  }

  /// Port of the JS SDK's `can set and read several documents with overlapping keys` (remote_document_cache.test.ts).
  @testMethod
  Future<void> testSetAndReadSeveralDocumentsWithOverlappingKeys() async {
    final List<String> paths = <String>[
      'a/b',
      'a/b/c/d',
      'a/b/c/d/e/f',
      'a/c',
      'c/b/d/e',
      'f/g',
    ];
    for (final String path in paths) {
      await _addTestDocumentAtPath(path);
    }
    final Map<DocumentKey, MaybeDocument?> read = await _getAll(paths);
    expect(read.values.whereType<Document>(), hasLength(paths.length));
  }

  /// Port of the JS SDK's `can set and read several documents with deeply nested keys`
  /// (remote_document_cache.test.ts).
  @testMethod
  Future<void> testSetAndReadSeveralDocumentsWithDeeplyNestedKeys() async {
    final List<String> paths = <String>[
      'a/a/a/a/a/a/a/a',
      'b/b/b/b/a/a',
      'c/c/a/a',
      'd/d',
    ];
    for (final String path in paths) {
      await _addTestDocumentAtPath(path);
    }
    final Map<DocumentKey, MaybeDocument?> read = await _getAll(paths);
    expect(read.values.whereType<Document>(), hasLength(paths.length));
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
  Future<void> testGetAllFromCollection() async {
    await _addTestDocumentAtPath('a/1');
    await _addTestDocumentAtPath('b/1');
    await _addTestDocumentAtPath('b/2');
    await _addTestDocumentAtPath('c/1');

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('b'),
          IndexOffset.none,
        );
    expect(values(results), <Document>[
      doc('b/1', 42, _docData),
      doc('b/2', 42, _docData),
    ]);
  }

  @testMethod
  Future<void> testGetAllFromExcludesSubcollections() async {
    await _addTestDocumentAtPath('a/1');
    await _addTestDocumentAtPath('a/1/b/1');
    await _addTestDocumentAtPath('a/2');

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('a'),
          IndexOffset.none,
        );
    expect(values(results), <Document>[
      doc('a/1', 42, _docData),
      doc('a/2', 42, _docData),
    ]);
  }

  @testMethod
  Future<void> testGetAllFromSinceReadTimeAndSeconds() async {
    await _addTestDocumentAtPath('b/old', updateTime: 1, readTime: 11);
    await _addTestDocumentAtPath('b/current', updateTime: 2, readTime: 12);
    await _addTestDocumentAtPath('b/new', updateTime: 3, readTime: 13);

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('b'),
          IndexOffset.createSuccessor(version(12), -1),
        );
    expect(values(results), <Document>[doc('b/new', 3, _docData)]);
  }

  @testMethod
  Future<void> testGetAllFromSinceReadTimeAndNanoseconds() async {
    await _add(doc('b/old', 1, _docData), _versionAt(1, 1));
    await _add(doc('b/current', 1, _docData), _versionAt(1, 2));
    await _add(doc('b/new', 1, _docData), _versionAt(1, 3));

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('b'),
          IndexOffset.createSuccessor(_versionAt(1, 2), -1),
        );
    expect(values(results), <Document>[doc('b/new', 1, _docData)]);
  }

  @testMethod
  Future<void> testGetAllFromSinceReadTimeAndDocumentKey() async {
    await _addTestDocumentAtPath('b/a', updateTime: 1, readTime: 11);
    await _addTestDocumentAtPath('b/b', updateTime: 2, readTime: 11);
    await _addTestDocumentAtPath('b/c', updateTime: 3, readTime: 11);
    await _addTestDocumentAtPath('b/d', updateTime: 4, readTime: 12);

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('b'),
          IndexOffset(version(11), key('b/b'), -1),
        );
    expect(values(results), <Document>[
      doc('b/c', 3, _docData),
      doc('b/d', 4, _docData),
    ]);
  }

  @testMethod
  Future<void> testGetAllFromUsesReadTimeNotUpdateTime() async {
    await _addTestDocumentAtPath('b/old', updateTime: 1, readTime: 2);
    await _addTestDocumentAtPath('b/new', updateTime: 2, readTime: 1);

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('b'),
          IndexOffset.createSuccessor(version(1), -1),
        );
    expect(values(results), <Document>[doc('b/old', 1, _docData)]);
  }

  @testMethod
  Future<void> testGetMatchingDocsAppliesQueryCheck() async {
    await _addTestDocumentAtPath(
      'a/1',
      updateTime: 1,
      readTime: 1,
      data: map(<dynamic>['matches', true]),
    );
    await _addTestDocumentAtPath(
      'a/2',
      updateTime: 1,
      readTime: 2,
      data: map(<dynamic>['matches', true]),
    );
    await _addTestDocumentAtPath(
      'a/3',
      updateTime: 1,
      readTime: 3,
      data: map(<dynamic>['matches', false]),
    );

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('a').filter(filter('matches', '==', true)),
          IndexOffset.createSuccessor(version(1), -1),
        );
    expect(values(results), <Document>[
      doc('a/2', 1, map(<dynamic>['matches', true])),
    ]);
  }

  @testMethod
  Future<void> testGetMatchingDocsRespectsMutatedDocs() async {
    await _addTestDocumentAtPath(
      'a/1',
      updateTime: 1,
      readTime: 1,
      data: map(<dynamic>['matches', true]),
    );
    await _addTestDocumentAtPath(
      'a/2',
      updateTime: 1,
      readTime: 2,
      data: map(<dynamic>['matches', false]),
    );

    final ImmutableSortedMap<DocumentKey, Document> results =
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query('a').filter(filter('matches', '==', true)),
          IndexOffset.createSuccessor(version(1), -1),
          mutatedKeys: <DocumentKey>{key('a/2')},
        );
    expect(values(results), <Document>[
      doc('a/2', 1, map(<dynamic>['matches', false])),
    ]);
  }

  @testMethod
  Future<void> testRemoveAllDocuments() async {
    // More keys than one SQLite statement takes (LongQuery splits at 900).
    final List<String> removed = <String>[
      for (int i = 0; i < 1000; i++) 'a/${i.toString().padLeft(4, '0')}',
    ];
    await _persistence.runTransaction('add entries', () async {
      for (String path in <String>[...removed, 'a/kept', 'b/kept']) {
        await _remoteDocumentCache.add(
          doc(path, 42, map(<dynamic>['data', 2])),
          version(42),
        );
      }
    });

    await _persistence.runTransaction(
      'remove entries',
      () => _remoteDocumentCache.removeAll(<DocumentKey>[
        for (String path in removed) key(path),
        key('a/missing'),
      ]),
    );

    final Map<DocumentKey, MaybeDocument?> read = await _getAll(<String>[
      ...removed,
      'a/kept',
      'b/kept',
    ]);
    expect(
      read.values.whereType<MaybeDocument>().map((MaybeDocument d) => d.key),
      <DocumentKey>[key('a/kept'), key('b/kept')],
    );
    await _persistence.runTransaction(
      'remove nothing',
      () => _remoteDocumentCache.removeAll(<DocumentKey>[]),
    );
    expect(await _get('a/kept'), isNotNull);
  }

  @testMethod
  Future<void> testDocumentsMatchingQueryExcludesSubcollections() async {
    final Map<String, Object> docData = map(<dynamic>['data', 2]);
    await _addTestDocumentAtPath('a/1');
    await _addTestDocumentAtPath('a/1/b/1');
    await _addTestDocumentAtPath('a/2/b/2/c/1');
    await _addTestDocumentAtPath('a/3', readTime: 50);
    await _addTestDocumentAtPath('a/3/b/3', readTime: 50);
    await _addTestDocumentAtPath('ab/1');

    final Query query = Query(path('a'));
    expect(
      values(
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query,
          IndexOffset.none,
        ),
      ),
      <Document>[doc('a/1', 42, docData), doc('a/3', 42, docData)],
    );
    expect(
      values(
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          query,
          IndexOffset.createSuccessor(version(42), -1),
        ),
      ),
      <Document>[doc('a/3', 42, docData)],
    );
    expect(
      values(
        await _remoteDocumentCache.getAllDocumentsMatchingQuery(
          Query(path('a/1/b')),
          IndexOffset.none,
        ),
      ),
      <Document>[doc('a/1/b/1', 42, docData)],
    );
  }

  @testMethod
  Future<void> testAddingDocumentWithReadTimeOfZeroFails() async {
    await expectLater(
      _add(doc('a/b', 1, map(<dynamic>['data', 2])), SnapshotVersion.none),
      throwsA(anything),
    );
  }

  Future<Document> _addTestDocumentAtPath(
    String path, {
    int updateTime = 42,
    int readTime = 42,
    Map<String, Object>? data,
  }) async {
    final Document document = doc(path, updateTime, data ?? _docData);
    await _add(document, version(readTime));
    return document;
  }

  Future<void> _add(MaybeDocument doc, SnapshotVersion readTime) async {
    await _persistence.runTransaction(
      'add entry',
      () => _remoteDocumentCache.add(doc, readTime),
    );
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
      'remove entry',
      () => _remoteDocumentCache.remove(key(path)),
    );
  }
}
