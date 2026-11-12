// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_callback.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_loader.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/bundled_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:test/test.dart';

import '../../../../util/test_util.dart';

class _RecordingBundleCallback implements BundleCallback {
  final Set<DocumentKey> lastDocuments = <DocumentKey>{};
  final Map<DocumentKey, MaybeDocument> lastDocumentValues =
      <DocumentKey, MaybeDocument>{};
  final Map<String, ImmutableSortedSet<DocumentKey>> lastQueries =
      <String, ImmutableSortedSet<DocumentKey>>{};
  final Map<String, BundleMetadata> lastBundles = <String, BundleMetadata>{};

  @override
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyBundledDocuments(
      ImmutableSortedMap<DocumentKey, MaybeDocument> documents, String bundleId,
      {Map<DocumentKey, SnapshotVersion>? readTimes}) async {
    for (final MapEntry<DocumentKey, MaybeDocument> entry in documents) {
      lastDocuments.add(entry.key);
      lastDocumentValues[entry.key] = entry.value;
    }
    return ImmutableSortedMap<DocumentKey, MaybeDocument>.emptyMap(
        DocumentKey.comparator);
  }

  @override
  Future<void> saveNamedQuery(NamedQuery namedQuery,
      ImmutableSortedSet<DocumentKey> documentKeys) async {
    lastQueries[namedQuery.name] = documentKeys;
  }

  @override
  Future<void> saveBundle(BundleMetadata bundleMetadata) async {
    lastBundles[bundleMetadata.bundleId] = bundleMetadata;
  }
}

// Port of the Android BundleLoaderTest.
void main() {
  final SnapshotVersion createTime = SnapshotVersion(Timestamp.now());
  late _RecordingBundleCallback bundleCallback;

  BundleMetadata createMetadata(int documents) =>
      BundleMetadata('bundle-1', 1, createTime, documents, 10);

  void assertProgress(LoadBundleTaskProgress? progress, int documentsLoaded,
      int totalDocuments, int bytesLoaded, int totalBytes) {
    expect(progress, isNotNull);
    expect(progress!.documentsLoaded, documentsLoaded);
    expect(progress.totalDocuments, totalDocuments);
    expect(progress.bytesLoaded, bytesLoaded);
    expect(progress.totalBytes, totalBytes);
    expect(progress.taskState, LoadBundleTaskState.running);
  }

  setUp(() {
    bundleCallback = _RecordingBundleCallback();
  });

  test('testLoadsDocuments', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(2));

    LoadBundleTaskProgress? progress = bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc1'), createTime, true, const <String>[]),
        1);
    expect(progress, isNull);

    progress = bundleLoader.addElement(
        BundleDocument(doc('coll/doc1', 1, <String, Object?>{})), 4);
    assertProgress(progress, 1, 2, 5, 10);

    progress = bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc2'), createTime, true, const <String>[]),
        1);
    expect(progress, isNull);

    progress = bundleLoader.addElement(
        BundleDocument(doc('coll/doc2', 1, <String, Object?>{})), 4);
    assertProgress(progress, 2, 2, 10, 10);
  });

  test('testLoadsDeletedDocuments', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(1));

    final LoadBundleTaskProgress? progress = bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc1'), createTime, false, const <String>[]),
        10);
    assertProgress(progress, 1, 1, 10, 10);
  });

  test('testAppliesDocumentChanges', () async {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(1));

    bundleLoader
      ..addElement(
          BundledDocumentMetadata(
              key('coll/doc1'), createTime, true, const <String>[]),
          1)
      ..addElement(BundleDocument(doc('coll/doc1', 1, <String, Object?>{})), 9);

    await bundleLoader.applyChanges();

    expect(bundleCallback.lastDocuments, <DocumentKey>{key('coll/doc1')});
    expect(bundleCallback.lastBundles['bundle-1'], createMetadata(1));
  });

  test('testAppliesDeletedDocumentsAsNoDocuments', () async {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(1));

    bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc1'), createTime, false, const <String>[]),
        10);

    await bundleLoader.applyChanges();

    expect(bundleCallback.lastDocumentValues[key('coll/doc1')],
        NoDocument(key('coll/doc1'), createTime, hasCommittedMutations: false));
  });

  test('testAppliesNamedQueries', () async {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(2));

    bundleLoader
      ..addElement(
          BundledDocumentMetadata(
              key('coll/doc1'), createTime, false, const <String>['query-1']),
          2)
      ..addElement(
          BundledDocumentMetadata(
              key('coll/doc2'), createTime, false, const <String>['query-2']),
          2)
      ..addElement(
          NamedQuery(
              'query-1',
              BundledQuery(query('foo'), BundledQueryLimitType.first),
              createTime),
          2)
      ..addElement(
          NamedQuery(
              'query-2',
              BundledQuery(query('foo'), BundledQueryLimitType.first),
              createTime),
          4);

    await bundleLoader.applyChanges();

    expect(bundleCallback.lastQueries['query-1'],
        keySet(<DocumentKey>[key('coll/doc1')]));
    expect(bundleCallback.lastQueries['query-2'],
        keySet(<DocumentKey>[key('coll/doc2')]));
  });

  test('testVerifiesBundledDocumentMetadataSent', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(1));

    expect(
        () => bundleLoader.addElement(
            BundleDocument(doc('coll/doc1', 1, <String, Object?>{})), 10),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'The document being added does not match the stored metadata.')));
  });

  test('testVerifiesBundledDocumentMetadataMatches', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(1));
    bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc1'), createTime, true, const <String>[]),
        1);

    expect(
        () => bundleLoader.addElement(
            BundleDocument(doc('coll/do2', 1, <String, Object?>{})), 9),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'The document being added does not match the stored metadata.')));
  });

  test('testRejectsMetadataElements', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(1));

    expect(() => bundleLoader.addElement(createMetadata(1), 1),
        throwsA(isA<ArgumentError>()));
  });

  test('testVerifiesDocumentFollowsMetadata', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(0));

    bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc1'), createTime, true, const <String>[]),
        10);

    expect(
        bundleLoader.applyChanges(),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'Bundled documents end with a document metadata element instead of a document.')));
  });

  test('testVerifiesDocumentCount', () {
    final BundleLoader bundleLoader =
        BundleLoader(bundleCallback, createMetadata(2));

    bundleLoader.addElement(
        BundledDocumentMetadata(
            key('coll/doc1'), createTime, false, const <String>[]),
        10);

    expect(
        bundleLoader.applyChanges(),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.message,
            'message', 'Expected 2 documents, but loaded 1.')));
  });
}
