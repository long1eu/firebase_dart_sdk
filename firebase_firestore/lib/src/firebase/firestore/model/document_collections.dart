// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:collection';

import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';

/// Provides static helpers around document collections.
class DocumentCollections {
  /** Returns an empty, immutable document map */
  static SplayTreeMap<DocumentKey, Document> emptyDocumentMap() {
    return SplayTreeMap<DocumentKey, Document>();
  }

  /** Returns an empty, immutable "maybe" document map */
  static SplayTreeMap<DocumentKey, MaybeDocument> emptyMaybeDocumentMap() {
    return SplayTreeMap<DocumentKey, MaybeDocument>();
  }

  /** Returns an empty, immutable versions map */
  static SplayTreeMap<DocumentKey, SnapshotVersion> emptyVersionMap() {
    return SplayTreeMap<DocumentKey, SnapshotVersion>();
  }
}
