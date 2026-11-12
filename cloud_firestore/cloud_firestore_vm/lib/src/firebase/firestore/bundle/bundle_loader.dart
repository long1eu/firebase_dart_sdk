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

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_callback.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_element.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundle_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/bundled_document_metadata.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/bundle/named_query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/load_bundle_task_progress.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';

/// A class to process the elements from a bundle, load them into local storage and provide progress update while
/// loading.
class BundleLoader {
  BundleLoader(this._bundleCallback, this._bundleMetadata);

  final BundleCallback _bundleCallback;
  final BundleMetadata _bundleMetadata;
  final List<NamedQuery> _queries = <NamedQuery>[];
  final Map<DocumentKey, BundledDocumentMetadata> _documentsMetadata =
      <DocumentKey, BundledDocumentMetadata>{};

  ImmutableSortedMap<DocumentKey, MaybeDocument> _documents =
      DocumentCollections.emptyMaybeDocumentMap();
  int _bytesLoaded = 0;
  DocumentKey? _currentDocument;

  /// Adds an element from the bundle to the loader.
  ///
  /// Returns a new progress if adding the element leads to a new progress, otherwise returns null.
  LoadBundleTaskProgress? addElement(
      BundleElement bundleElement, int byteSize) {
    if (bundleElement is BundleMetadata) {
      throw ArgumentError('Unexpected bundle metadata element.');
    }

    final int beforeDocumentCount = _documents.length;

    if (bundleElement is NamedQuery) {
      _queries.add(bundleElement);
    } else if (bundleElement is BundledDocumentMetadata) {
      _documentsMetadata[bundleElement.key] = bundleElement;
      _currentDocument = bundleElement.key;
      if (!bundleElement.exists) {
        _documents = _documents.insert(
          bundleElement.key,
          NoDocument(bundleElement.key, bundleElement.readTime,
              hasCommittedMutations: false),
        );
        _currentDocument = null;
      }
    } else if (bundleElement is BundleDocument) {
      if (bundleElement.key != _currentDocument) {
        throw ArgumentError(
            'The document being added does not match the stored metadata.');
      }
      _documents = _documents.insert(bundleElement.key, bundleElement.document);
      _currentDocument = null;
    }

    _bytesLoaded += byteSize;

    return beforeDocumentCount != _documents.length
        ? LoadBundleTaskProgress(
            _documents.length,
            _bundleMetadata.totalDocuments,
            _bytesLoaded,
            _bundleMetadata.totalBytes,
            null,
            LoadBundleTaskState.running,
          )
        : null;
  }

  /// Applies the loaded documents and queries to local store. Returns the document view changes.
  Future<ImmutableSortedMap<DocumentKey, MaybeDocument>> applyChanges() async {
    if (_currentDocument != null) {
      throw ArgumentError(
          'Bundled documents end with a document metadata element instead of a document.');
    }
    if (_documents.length != _bundleMetadata.totalDocuments) {
      throw ArgumentError(
          'Expected ${_bundleMetadata.totalDocuments} documents, but loaded ${_documents.length}.');
    }

    final ImmutableSortedMap<DocumentKey, MaybeDocument> changes =
        await _bundleCallback.applyBundledDocuments(
            _documents, _bundleMetadata.bundleId);

    final Map<String, ImmutableSortedSet<DocumentKey>> queryDocumentMap =
        _getQueryDocumentMapping();
    for (final NamedQuery namedQuery in _queries) {
      await _bundleCallback.saveNamedQuery(
          namedQuery, queryDocumentMap[namedQuery.name]!);
    }

    await _bundleCallback.saveBundle(_bundleMetadata);

    return changes;
  }

  Map<String, ImmutableSortedSet<DocumentKey>> _getQueryDocumentMapping() {
    final Map<String, ImmutableSortedSet<DocumentKey>> queryDocumentMap =
        <String, ImmutableSortedSet<DocumentKey>>{};
    for (final NamedQuery namedQuery in _queries) {
      queryDocumentMap[namedQuery.name] = DocumentKey.emptyKeySet;
    }
    for (final BundledDocumentMetadata metadata in _documentsMetadata.values) {
      for (final String query in metadata.queries) {
        // A document may reference a query that is not part of the bundle: ignore it, as the Android SDK would fail
        // with a NullPointerException here, which makes the whole bundle fail to load.
        final ImmutableSortedSet<DocumentKey>? matchingKeys =
            queryDocumentMap[query];
        if (matchingKeys != null) {
          queryDocumentMap[query] = matchingKeys.insert(metadata.key);
        }
      }
    }

    return queryDocumentMap;
  }
}
