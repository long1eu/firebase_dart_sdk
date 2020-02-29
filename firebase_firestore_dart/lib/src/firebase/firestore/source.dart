// File created by
// Lung Razvan <long1eu>
// on 26/09/2018
import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/document_reference.dart';
import 'package:firebase_firestore/src/firebase/firestore/query.dart';

/// Configures the behavior of [DocumentReference.get] and [Query.get]. By providing a [Source]
/// value, these methods can be configured to fetch results only from the server, only from the
/// local cache, or attempt to fetch results from the server and fall back to the cache (which is
/// the default).
@publicApi
enum Source {
  /// Causes Firestore to try to retrieve an up-to-date (server-retrieved) snapshot, but fall back
  /// to  returning cached data if the server can't be reached.
  defaultSource,

  /// Causes Firestore to avoid the cache, generating an error if the server cannot be reached. Note
  /// that the cache will still be updated if the server request succeeds. Also note that
  /// latency-compensation still takes effect, so any pending write operations will be visible in
  /// the returned data (merged into the server-provided data).
  server,

  /// Causes Firestore to immediately return a value from the cache, ignoring the server completely
  /// (implying that the returned value may be stale with respect to the value on the server). If
  /// there is no data in the cache to satisfy the [get] call, [DocumentReference.get] will return
  /// can error and [Query.get] will return an empty [QuerySnapshot] with no documents.
  cache
}
