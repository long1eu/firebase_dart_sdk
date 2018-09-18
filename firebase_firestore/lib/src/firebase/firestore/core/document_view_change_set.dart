// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/** A set of changes to documents with respect to a view. This set is mutable. */
class DocumentViewChangeSet {
  // This map is sorted to make the unit tests simpler.
  final SplayTreeMap<DocumentKey, DocumentViewChange> changes =
      SplayTreeMap<DocumentKey, DocumentViewChange>();

  DocumentViewChangeSet();

  void addChange(DocumentViewChange change) {
    final DocumentKey key = change.document.key;
    DocumentViewChange old = changes[key];
    if (old == null) {
      changes[key] = change;
      return;
    }

    final DocumentViewChangeType oldType = old.type;
    final DocumentViewChangeType newType = change.type;
    if (newType != DocumentViewChangeType.added &&
        oldType == DocumentViewChangeType.metadata) {
      changes[key] = change;
    } else if (newType == DocumentViewChangeType.metadata &&
        oldType != DocumentViewChangeType.removed) {
      final DocumentViewChange newChange =
          DocumentViewChange(oldType, change.document);
      changes[key] = newChange;
    } else if (newType == DocumentViewChangeType.modified &&
        oldType == DocumentViewChangeType.modified) {
      final DocumentViewChange newChange =
          DocumentViewChange(DocumentViewChangeType.modified, change.document);
      changes[key] = newChange;
    } else if (newType == DocumentViewChangeType.modified &&
        oldType == DocumentViewChangeType.added) {
      final DocumentViewChange newChange =
          DocumentViewChange(DocumentViewChangeType.added, change.document);
      changes[key] = newChange;
    } else if (newType == DocumentViewChangeType.removed &&
        oldType == DocumentViewChangeType.added) {
      changes.remove(key);
    } else if (newType == DocumentViewChangeType.removed &&
        oldType == DocumentViewChangeType.modified) {
      final DocumentViewChange newChange =
          DocumentViewChange(DocumentViewChangeType.removed, old.document);
      changes[key] = newChange;
    } else if (newType == DocumentViewChangeType.added &&
        oldType == DocumentViewChangeType.removed) {
      final DocumentViewChange newChange =
          DocumentViewChange(DocumentViewChangeType.modified, change.document);

      changes[key] = newChange;
    } else {
      // This includes these cases, which don't make sense:
      // Added -> Added
      // Removed -> Removed
      // Modified -> Added
      // Removed -> Modified
      // Metadata -> Added
      // Removed -> Metadata
      throw Assert.fail(
          'Unsupported combination of changes $newType after $oldType');
    }
  }

  List<DocumentViewChange> getChanges() => changes.values.toList();
}
