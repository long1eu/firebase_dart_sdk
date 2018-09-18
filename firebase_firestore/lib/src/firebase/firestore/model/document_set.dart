// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/model/document_collections.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

import 'document.dart';

/// An immutable set of documents (unique by key) ordered by the given
/// comparator or ordered by key by default if no document is present.
class DocumentSet extends Iterable<Document> {
  final SplayTreeMap<DocumentKey, Document> _keyIndex;
  final SplayTreeSet<Document> _sortedSet;

  const DocumentSet._(this._keyIndex, this._sortedSet);

  factory DocumentSet.emptySet(Comparator<Document> comparator) {
    // We have to add the document key comparator to the passed in comparator,
    // as it's the only guaranteed unique property of a document.
    Comparator<Document> adjustedComparator = (Document left, Document right) {
      int comparison = comparator(left, right);
      if (comparison == 0) {
        return Document.keyComparator(left, right);
      } else {
        return comparison;
      }
    };

    return new DocumentSet._(
      DocumentCollections.emptyDocumentMap(),
      SplayTreeSet<Document>(adjustedComparator),
    );
  }

  @override
  int get length => _keyIndex.length;

  @override
  bool get isEmpty => _keyIndex.isEmpty;

  @override
  bool get isNotEmpty => _keyIndex.isNotEmpty;

  /// Returns true iff this set contains a document with the given key.
  @override
  bool contains(Object key) => _keyIndex.containsKey(key);

  /// Returns the document from this set with the given key if it exists or
  /// null if it doesn't.
  Document getDocument(DocumentKey key) => _keyIndex[key];

  /// Returns the first document in the set according to the set's ordering, or
  /// null if the set is empty.
  @override
  Document get first => isNotEmpty ? _sortedSet.first : null;

  /// Returns the last document in the set according to the set's ordering, or
  /// null if the set is empty.
  @override
  Document get last => isNotEmpty ? _sortedSet.last : null;

  /// Returns the document previous to the document associated with the given
  /// key in the set according to the set's ordering. Returns null if the
  /// document associated with the given key is the first document.
  ///
  /// Throws ArgumentError if the set does not contain the key
  Document getPredecessor(DocumentKey key) {
    if (!_keyIndex.containsKey(key)) {
      throw new ArgumentError("Key not contained in DocumentSet: $key");
    }

    key = _keyIndex.lastKeyBefore(key);
    return _keyIndex[key];
  }

  /// Returns the index of the provided key in the document set, or -1 if the
  /// document key is not present in the set;
  int indexOf(DocumentKey key) {
    Document document = _keyIndex[key];
    if (document == null) {
      return -1;
    }

    return _keyIndex.keys.toList(growable: false).indexOf(key);
  }

  /// Returns a new DocumentSet that contains the given document, replacing any
  /// old document with the same key.
  DocumentSet add(Document document) {
    // Remove any prior mapping of the document's key before adding, preventing
    // sortedSet from accumulating values that aren't in the index.
    DocumentSet removed = remove(document.key);

    removed._keyIndex[document.key] = document;
    removed._sortedSet.add(document);

    return DocumentSet._(
      SplayTreeMap.from<DocumentKey, Document>(removed._keyIndex),
      SplayTreeSet.from(removed._sortedSet),
    );
  }

  /// Returns a new DocumentSet with the document for the provided key removed.
  DocumentSet remove(DocumentKey key) {
    Document document = _keyIndex[key];
    if (document == null) {
      return this;
    }

    _keyIndex.remove(key);
    _sortedSet.remove(document);

    return DocumentSet._(
      SplayTreeMap.from<DocumentKey, Document>(_keyIndex),
      SplayTreeSet.from(_sortedSet),
    );
  }

  /**
   * Returns a copy of the documents in this set as array. This is O(n) in the size of the set TODO:
   * Consider making this backed by the set instead to achieve O(1)?
   */
  @override
  List<Document> toList({bool growable: true}) {
    return _sortedSet.toList(growable: growable);
  }

  @override
  bool operator ==(Object other) {
    if (this == other) {
      return true;
    }

    if (other == null || runtimeType != other.runtimeType) {
      return false;
    }

    if (other is DocumentSet) {
      final Iterator<Document> thisList = toList(growable: false).iterator;
      final Iterator<Document> otherList =
          other.toList(growable: false).iterator;

      while (thisList.moveNext()) {
        final Document thisDoc = thisList.current;
        final Document otherDoc = otherList.current;
        if (thisDoc != otherDoc) {
          return false;
        }
      }

      return true;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => _keyIndex.hashCode ^ _sortedSet.hashCode;

  @override
  Iterator<Document> get iterator => _sortedSet.iterator;
}
