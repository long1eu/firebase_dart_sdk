// File created by
// Lung Razvan <long1eu>
// on 26/09/2018
import 'package:cloud_firestore_dart/src/firebase/firestore/document_reference.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/query_snapshot.dart';

/// Configures the behavior of [DocumentReference.get] and [Query.get]. By providing a [Source]
/// value, these methods can be configured to fetch results only from the server, only from the
/// local cache, or attempt to fetch results from the server and fall back to the cache (which is
/// the default).
///
/// This replaces the separate `getDocFromCache` / `getDocFromServer` functions of the JS SDK.
///
/// ```dart
/// // Only the server; fails with FirestoreErrorCode.unavailable when offline.
/// final DocumentSnapshot<Map<String, Object?>> fresh = await firestore
///     .doc('cities/SF')
///     .get(Source.server);
///
/// // Only the cache; never contacts the backend.
/// final QuerySnapshot<Map<String, Object?>> cached = await firestore
///     .collection('cities')
///     .get(Source.cache);
/// ```
enum Source {
  /// Causes Firestore to try to retrieve an up-to-date (server-retrieved) snapshot, but fall back
  /// to returning cached data if the server can't be reached: the default of
  /// [DocumentReference.get] and [Query.get].
  serverAndCache,

  /// Causes Firestore to avoid the cache, generating an error (`FirestoreErrorCode.unavailable`) if
  /// the server cannot be reached. Note
  /// that the cache will still be updated if the server request succeeds. Also note that
  /// latency-compensation still takes effect, so any pending write operations will be visible in
  /// the returned data (merged into the server-provided data).
  server,

  /// Causes Firestore to immediately return a value from the cache, ignoring the server completely
  /// (implying that the returned value may be stale with respect to the value on the server). If
  /// there is no data in the cache to satisfy the `get` call, [DocumentReference.get] fails with
  /// `FirestoreErrorCode.unavailable` and [Query.get] returns a [QuerySnapshot] with the documents
  /// the cache has, possibly none. A document that the cache knows to be missing gives a snapshot
  /// whose `exists` is false.
  cache,
}
