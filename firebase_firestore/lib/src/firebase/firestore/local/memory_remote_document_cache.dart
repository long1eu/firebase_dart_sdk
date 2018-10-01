// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'dart:async';

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/query.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/memory_lru_reference_delegate.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/remote_document_cache.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_collections.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';

/// In-memory cache of remote documents.
class MemoryRemoteDocumentCache implements RemoteDocumentCache {
  /// Underlying cache of documents.
  ImmutableSortedMap<DocumentKey, MaybeDocument> docs;

  MemoryRemoteDocumentCache()
      : docs = DocumentCollections.emptyMaybeDocumentMap();

  @override
  Future<void> add(MaybeDocument document) async {
    docs = docs.insert(document.key, document);
  }

  @override
  Future<void> remove(DocumentKey key) async {
    docs = docs.remove(key);
  }

  @override
  Future<MaybeDocument> get(DocumentKey key) async => docs[key];

  @override
  Future<ImmutableSortedMap<DocumentKey, Document>>
      getAllDocumentsMatchingQuery(Query query) async {
    ImmutableSortedMap<DocumentKey, Document> result =
        DocumentCollections.emptyDocumentMap();

    // Documents are ordered by key, so we can use a prefix scan to narrow down
    // the documents we need to match the query against.
    final ResourcePath queryPath = query.path;
    final DocumentKey prefix =
        DocumentKey.fromPath(queryPath.appendSegment(''));
    final Iterator<MapEntry<DocumentKey, MaybeDocument>> iterator =
        docs.iteratorFrom(prefix);
    while (iterator.moveNext()) {
      final MapEntry<DocumentKey, MaybeDocument> entry = iterator.current;
      final DocumentKey key = entry.key;
      if (!queryPath.isPrefixOf(key.path)) {
        break;
      }

      final MaybeDocument maybeDoc = entry.value;
      if (!(maybeDoc is Document)) {
        continue;
      }

      final Document doc = maybeDoc;
      if (query.matches(doc)) {
        result = result.insert(doc.key, doc);
      }
    }

    return result;
  }

  /// Remove any documents that the delegate reports as not pinned at the given
  /// upper bound.
  Future<int> removeOrphanedDocuments(
      MemoryLruReferenceDelegate delegate, int upperBound) async {
    int count = 0;
    ImmutableSortedMap<DocumentKey, MaybeDocument> updated = docs;
    for (MapEntry<DocumentKey, MaybeDocument> entry in docs) {
      if (!(await delegate.isPinned(entry.key, upperBound))) {
        updated = updated.remove(entry.key);
        count++;
      }
    }
    docs = updated;
    return count;
  }
}
