// File created by
// Lung Razvan <long1eu>
// on 21/09/2018

import 'package:firebase_firestore/src/firebase/firestore/auth/user.dart';
import 'package:firebase_firestore/src/firebase/firestore/core/index_range.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/index_cursor.dart';
import 'package:firebase_firestore/src/firebase/firestore/local/sqlite_persistence.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/resource_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// A persisted 'collection index' of all documents in the local cache (with mutations overlaid on
/// top of remote documents).
///
/// NOTE: There is no in-memory implementation at this time.
class SQLiteCollectionIndex {
  SQLiteCollectionIndex(this.db, User user) : uid = user.isAuthenticated ? user.uid : '';

  final SQLitePersistence db;
  final String uid;

  /// Adds the specified entry to the index.
  void addEntry(FieldPath fieldPath, FieldValue fieldValue, DocumentKey documentKey) {
    throw StateError('Not yet implemented.');
  }

  /// Adds the specified entry to the index.
  void removeEntry(FieldPath fieldPath, FieldValue fieldValue, DocumentKey documentKey) {
    throw StateError('Not yet implemented.');
  }

  /// Gets a forward or reverse cursor for the specified range of the index. Since index entries are
  /// lossy, some cursor results may not match the specified range, so the consumer must always
  /// post-filter the results.
  IndexCursor getCursor(ResourcePath collectionPath, IndexRange indexRange) {
    throw StateError('Not yet implemented.');
  }
}
