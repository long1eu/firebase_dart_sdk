// File created by
// Lung Razvan <long1eu>
// on 19/09/2018

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

/// A collection of references to a document from some kind of numbered entity (either a target id
/// or batch id). As references are added to or removed from the set corresponding events are
/// emitted to a registered garbage collector.
///
/// Each reference is represented by a [DocumentReference] object. Each of them contains enough
/// information to uniquely identify the reference. They are all stored primarily in a set sorted by
/// key. A document is considered garbage if there's no references in that set (this can be
/// efficiently checked thanks to sorting by key).
///
/// [ReferenceSet] also keeps a secondary set that contains references sorted by ids. This one is
/// used to efficiently implement removal of all references by some target id.
class ReferenceSet {
  ReferenceSet()
      : referencesByKey =
            ImmutableSortedSet<DocumentReference>(<DocumentReference>[], DocumentReference.byKey),
        referencesByTarget = ImmutableSortedSet<DocumentReference>(
            <DocumentReference>[], DocumentReference.byTarget);

  /// A set of outstanding references to a document sorted by key.
  ImmutableSortedSet<DocumentReference> referencesByKey;

  /// A set of outstanding references to a document sorted by target id (or batch id).
  ImmutableSortedSet<DocumentReference> referencesByTarget;

  /// Returns true if the reference set contains no references.
  bool get isEmpty => referencesByKey.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Adds a reference to the given document key for the given id.
  void addReference(DocumentKey key, int targetOrBatchId) {
    final DocumentReference ref = DocumentReference(key, targetOrBatchId);
    referencesByKey = referencesByKey.insert(ref);
    referencesByTarget = referencesByTarget.insert(ref);
  }

  /// Add references to the given document keys for the given id.
  void addReferences(ImmutableSortedSet<DocumentKey> keys, int targetOrBatchId) {
    for (DocumentKey key in keys) {
      addReference(key, targetOrBatchId);
    }
  }

  /// Removes a reference to the given document key for the given id.
  void removeReference(DocumentKey key, int targetOrBatchId) {
    _removeReference(DocumentReference(key, targetOrBatchId));
  }

  /// Removes references to the given document keys for the given ID.
  void removeReferences(ImmutableSortedSet<DocumentKey> keys, int targetOrBatchId) {
    for (DocumentKey key in keys) {
      removeReference(key, targetOrBatchId);
    }
  }

  /// Clears all references with a given Iid. Calls [removeReference] for each key removed.
  ///
  /// Returns the keys of the documents that were removed.
  ImmutableSortedSet<DocumentKey> removeReferencesForId(int targetId) {
    final DocumentKey emptyKey = DocumentKey.empty();
    final DocumentReference startRef = DocumentReference(emptyKey, targetId);
    final Iterator<DocumentReference> it = referencesByTarget.iteratorFrom(startRef);
    ImmutableSortedSet<DocumentKey> keys = DocumentKey.emptyKeySet;
    while (it.moveNext()) {
      final DocumentReference ref = it.current;
      if (ref.id == targetId) {
        keys = keys.insert(ref.key);
        _removeReference(ref);
      } else {
        break;
      }
    }

    return keys;
  }

  /// Clears all references for all ids.
  void removeAllReferences() => referencesByKey.forEach(_removeReference);

  void _removeReference(DocumentReference ref) {
    referencesByKey = referencesByKey.remove(ref);
    referencesByTarget = referencesByTarget.remove(ref);
  }

  /// Returns all of the document keys that have had references added for the given id.
  ImmutableSortedSet<DocumentKey> referencesForId(int target) {
    final DocumentKey emptyKey = DocumentKey.empty();
    final DocumentReference startRef = DocumentReference(emptyKey, target);

    final Iterator<DocumentReference> iterator = referencesByTarget.iteratorFrom(startRef);
    ImmutableSortedSet<DocumentKey> keys = DocumentKey.emptyKeySet;
    while (iterator.moveNext()) {
      final DocumentReference reference = iterator.current;
      if (reference.id == target) {
        keys = keys.insert(reference.key);
      } else {
        break;
      }
    }
    return keys;
  }

  bool containsKey(DocumentKey key) {
    final DocumentReference ref = DocumentReference(key, 0);

    final Iterator<DocumentReference> iterator = referencesByKey.iteratorFrom(ref);

    if (!iterator.moveNext()) {
      return false;
    }

    final DocumentKey firstKey = iterator.current.key;
    return firstKey == key;
  }
}
