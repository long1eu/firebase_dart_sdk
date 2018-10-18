// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';

/// The result of a lookup for a given path may be an existing document or a
/// marker that this document does not exist at a given version.
abstract class MaybeDocument {
  /// The key for this document
  final DocumentKey key;

  /// Returns the version of this document if it exists or a version at which
  /// this document was guaranteed to not exist.
  final SnapshotVersion version;

  const MaybeDocument(this.key, this.version);

  /// Whether this document has a local mutation applied that has not yet been
  /// acknowledged by Watch.
  bool get hasPendingWrites;
}
