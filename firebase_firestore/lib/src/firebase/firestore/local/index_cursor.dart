// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';

/// A cursor used to iterate through entries in an index. Each entry is returned
/// merely as a DocumentKey (and a separate lookup must be done to read the
/// document contents), since the actual index entries may be lossy and should
/// not be relied upon.
///
/// * TODO: We could probably avoid one final document lookup for most queries
/// by exposing the (lossy) index entry, or at least the typeOrder for it (since
/// the type itself will never be lossy).
class IndexCursor {
  /// Advances the cursor (to the first result if this is the first call),
  /// returning false if there are no more items.
  bool get next => throw StateError('Not yet implemented.');

  /// Returns the DocumentKey for the current index entry (throws if there are
  /// no more entries).
  DocumentKey get documentKey => throw StateError('Not yet implemented.');

  void close() => throw StateError('Not yet implemented.');
}
