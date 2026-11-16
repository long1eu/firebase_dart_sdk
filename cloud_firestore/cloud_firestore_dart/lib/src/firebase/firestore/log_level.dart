/// The verbosity of the Cloud Firestore logs, set with
/// `FirebaseFirestore.setLogLevel`, from the most to the least verbose. Each
/// level logs its own messages and those of every level after it. The JS SDK
/// also has `info`; the SDK writes no message at that level, so it is left
/// out.
///
/// The default, before any call, is [warn].
///
/// ```dart
/// FirebaseFirestore.setLogLevel(LogLevel.debug);
/// ```
enum LogLevel {
  /// Everything, including the most detailed messages.
  verbose,

  /// Debug messages and above, primarily for debugging.
  debug,

  /// Warnings and errors. The default.
  warn,

  /// Only errors are logged.
  error,

  /// Nothing is logged.
  silent,
}
