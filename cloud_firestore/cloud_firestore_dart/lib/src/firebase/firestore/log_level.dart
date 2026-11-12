/// The verbosity of the Cloud Firestore logs, set with
/// `Firestore.setLogLevel`. Same levels as `setLogLevel` of the JS SDK.
enum LogLevel {
  /// The most verbose level, primarily for debugging.
  debug,

  /// Only errors are logged.
  error,

  /// Nothing is logged.
  silent,
}
