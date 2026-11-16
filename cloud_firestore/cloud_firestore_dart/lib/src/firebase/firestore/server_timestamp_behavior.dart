// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/field_value.dart';

/// Controls the return value for server timestamps that have not yet been set to their final value.
///
/// A field written with [FieldValue.serverTimestamp] has no value on the
/// client until the server has applied the write. Until then a snapshot with
/// pending writes reads it according to this behavior. Pass it to
/// `DocumentSnapshot.getData`, `get`, `getField`, `getTimestamp` or `getDate`;
/// `data` uses [none].
///
/// ```dart
/// final DocumentReference<Map<String, Object?>> post = firestore.doc('posts/a');
/// final Future<void> written = post.set(<String, Object?>{
///   'createdAt': FieldValue.serverTimestamp(),
/// });
/// final DocumentSnapshot<Map<String, Object?>> local = await post.get(
///   const GetOptions(source: Source.cache),
/// );
/// local.get('createdAt'); // null
/// local.get(
///   'createdAt',
///   serverTimestamps: ServerTimestampBehavior.estimate,
/// ); // now
/// await written;
/// ```
///
/// This is the JS SDK's `serverTimestamps` snapshot option (`'none'`,
/// `'estimate'`, `'previous'`).
enum ServerTimestampBehavior {
  /// Return 'null' for [FieldValue.serverTimestamp] values that have not yet been set to
  /// their final value.
  none,

  /// Return local estimates for [FieldValue.serverTimestamp] values that have not yet been
  /// set to their final value. This estimate will likely differ from the final value and may cause
  /// these pending values to change once the server result becomes available.
  ///
  /// The estimate is the time of the local write, read from this device's
  /// clock.
  estimate,

  /// Return the previous value for [FieldValue.serverTimestamp] values that have not yet
  /// been set to their final value.
  ///
  /// If the field had no value before the write, it is read as `null`.
  previous,
}
