// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_collections.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';

import 'document.dart';

/// An immutable set of documents (unique by key) ordered by the given comparator or ordered by key
/// by default if no document is present.
class DocumentSet extends Iterable<Document> {
  const DocumentSet._(this._keyIndex, this.sortedSet);

  factory DocumentSet.emptySet(Comparator<Document> comparator) {
    return DocumentSet._(
      DocumentCollections.emptyDocumentMap(),
      ImmutableSortedSet<Document>(<Document>[], _adjusted(comparator)),
    );
  }

  /// Memoized per comparator so that sets created from the same comparator
  /// share one (identical) adjusted comparator, which sorted collections need
  /// in order to compare equal.
  static final Expando<Comparator<Document>> _adjustedComparators =
      Expando<Comparator<Document>>('adjustedComparator');

  static Comparator<Document> _adjusted(Comparator<Document> comparator) {
    return _adjustedComparators[comparator] ??= (Document left, Document right) {
      // We have to add the document key comparator to the passed in comparator, as it's the only
      // guaranteed unique property of a document.
      final int comparison = comparator(left, right);
      if (comparison == 0) {
        return Document.keyComparator(left, right);
      } else {
        return comparison;
      }
    };
  }

  final ImmutableSortedMap<DocumentKey, Document> _keyIndex;
  final ImmutableSortedSet<Document> sortedSet;

  @override
  int get length => _keyIndex.length;

  @override
  bool get isEmpty => _keyIndex.isEmpty;

  @override
  bool get isNotEmpty => _keyIndex.isNotEmpty;

  /// Returns true iff this set contains a document with the given key.
  @override
  bool contains(Object? key) {
    return key is DocumentKey && _keyIndex.containsKey(key);
  }

  /// Returns the document from this set with the given key if it exists or null if it doesn't.
  Document? getDocument(DocumentKey key) => _keyIndex[key];

  /// Returns the first document in the set according to the set's ordering, or null if the set is
  /// empty.
  Document? getFirstDocument() => sortedSet.minEntry;

  /// Returns the last document in the set according to the set's ordering, or null if the set is
  /// empty.
  Document? getLastDocument() => sortedSet.maxEntry;

  /// Prefer [getFirstDocument]; throws a [StateError] if the set is empty.
  @override
  Document get first => getFirstDocument()!;

  /// Prefer [getLastDocument]; throws a [StateError] if the set is empty.
  @override
  Document get last => getLastDocument()!;

  /// Returns the document previous to the document associated with the given key in the set
  /// according to the set's ordering. Returns null if the document associated with the given key is
  /// the first document.
  ///
  /// Throws ArgumentError if the set does not contain the key
  Document? getPredecessor(DocumentKey key) {
    final Document? document = _keyIndex[key];
    if (document == null) {
      throw ArgumentError('Key not contained in DocumentSet: ${key.path}');
    }
    return sortedSet.getPredecessorEntry(document);
  }

  /// Returns the index of the provided key in the document set, or -1 if the document key is not
  /// present in the set;
  int indexOf(DocumentKey key) {
    final Document? document = _keyIndex[key];
    if (document == null) {
      return -1;
    }

    return sortedSet.indexOf(document);
  }

  /// Returns a new DocumentSet that contains the given document, replacing any old document with
  /// the same key.
  DocumentSet add(Document document) {
    // Remove any prior mapping of the document's key before adding, preventing sortedSet from
    // accumulating values that aren't in the index.
    final DocumentSet removed = remove(document.key);

    final ImmutableSortedMap<DocumentKey, Document> newKeyIndex = removed
        ._keyIndex
        .insert(document.key, document);
    final ImmutableSortedSet<Document> newSortedSet = removed.sortedSet.insert(
      document,
    );
    return DocumentSet._(newKeyIndex, newSortedSet);
  }

  /// Returns a new DocumentSet with the document for the provided key removed.
  DocumentSet remove(DocumentKey key) {
    final Document? document = _keyIndex[key];
    if (document == null) {
      return this;
    }

    _keyIndex.remove(key);
    sortedSet.remove(document);

    final ImmutableSortedMap<DocumentKey, Document> newKeyIndex = _keyIndex
        .remove(key);
    final ImmutableSortedSet<Document> newSortedSet = sortedSet.remove(
      document,
    );
    return DocumentSet._(newKeyIndex, newSortedSet);
  }

  /// Returns a copy of the documents in this set as array. This is O(n) in the size of the set.
  // TODO(long1eu): Consider making this backed by the set instead to achieve O(1)?
  @override
  List<Document> toList({bool growable = true}) {
    final List<Document> documents = <Document>[];
    forEach(documents.add);
    return documents;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (runtimeType != other.runtimeType) {
      return false;
    }

    if (other is DocumentSet) {
      final Iterator<Document> thisList = toList(growable: false).iterator;
      final Iterator<Document> otherList = other
          .toList(growable: false)
          .iterator;

      while (thisList.moveNext()) {
        if (!otherList.moveNext()) {
          return false;
        }
        final Document thisDoc = thisList.current;
        final Document otherDoc = otherList.current;
        if (thisDoc != otherDoc) {
          return false;
        }
      }

      // Equal only if the other set has no extra documents.
      return !otherList.moveNext();
    } else {
      return false;
    }
  }

  @override
  int get hashCode {
    return _keyIndex.hashCode ^ sortedSet.hashCode;
  }

  @override
  Iterator<Document> get iterator => sortedSet.iterator;
}
