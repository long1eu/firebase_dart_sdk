/// The verbosity of the Cloud Firestore logs, set with
/// `Firestore.setLogLevel`.
///
/// Three of the levels of `setLogLevel` of the JS SDK, which also has
/// `verbose`, `info` and `warn`. The default, before any call, logs warnings
/// and errors; no value of this enum selects it again, but
/// `Firestore.setLoggingEnabled(loggingEnabled: false)` does.
enum LogLevel {
  /// The most verbose level, primarily for debugging.
  debug,

  /// Only errors are logged.
  error,

  /// Nothing is logged.
  silent,
}
