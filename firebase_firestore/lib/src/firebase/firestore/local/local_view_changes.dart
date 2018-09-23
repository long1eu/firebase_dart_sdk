// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_database_collection/firebase_database_collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/document_view_change.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/sync_engine.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/view_snapshot.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

/// A set of changes to what documents are currently in view and out of view for
/// a given query. These changes are sent to the [LocalStore] by the [View]
/// (via the [SyncEngine]) and are used to pin / unpin documents as appropriate.
class LocalViewChanges {
  final int targetId;
  final ImmutableSortedSet<DocumentKey> added;
  final ImmutableSortedSet<DocumentKey> removed;

  LocalViewChanges(this.targetId, this.added, this.removed);

  factory LocalViewChanges.fromViewSnapshot(
      int targetId, ViewSnapshot snapshot) {
    ImmutableSortedSet<DocumentKey> addedKeys =
        new ImmutableSortedSet<DocumentKey>([], DocumentKey.comparator);
    ImmutableSortedSet<DocumentKey> removedKeys =
        new ImmutableSortedSet<DocumentKey>([], DocumentKey.comparator);

    for (DocumentViewChange docChange in snapshot.changes) {
      switch (docChange.type) {
        case DocumentViewChangeType.added:
          addedKeys = addedKeys.insert(docChange.document.key);
          break;

        case DocumentViewChangeType.removed:
          removedKeys = removedKeys.insert(docChange.document.key);
          break;

        default:
          // Do nothing.
          break;
      }
    }

    return new LocalViewChanges(targetId, addedKeys, removedKeys);
  }
}
