/// Placeholders the server replaces with a value. JS: `api/ServerValue.ts`; Android: `ServerValue.java`.
library;

/// Values the server fills in when it applies a write.
///
/// Use them anywhere in a value passed to `DatabaseReference.set`, `DatabaseReference.update`, a
/// transaction or an `OnDisconnect` write, and as a priority. Until the server answers, local events show
/// an estimate made from the client's clock and the server time offset.
///
/// ```dart
/// await db.ref('posts/1').update(<String, Object?>{
///   'updatedAt': ServerValue.timestamp,
///   'views': ServerValue.increment(1),
/// });
/// ```
abstract final class ServerValue {
  /// The time the server applied the write, in milliseconds since the epoch: the placeholder
  /// `{'.sv': 'timestamp'}`.
  static const Object timestamp = <String, Object?>{'.sv': 'timestamp'};

  /// Adds [delta] to the number stored at the location when the server applies the write: the placeholder
  /// `{'.sv': {'increment': delta}}`. A location that holds no number is treated as 0. A NaN or infinite
  /// [delta] is not checked here: the write that holds it throws an [ArgumentError].
  ///
  /// Writes are at least once: when the acknowledgement of a write is lost and the client sends it again
  /// after reconnecting, the increment is applied twice.
  static Object increment(num delta) => <String, Object?>{
    '.sv': <String, Object?>{'increment': delta},
  };
}
