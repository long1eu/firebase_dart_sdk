/// The verbosity of the Cloud Firestore logs, set with
/// `Firestore.setLogLevel`: the levels of `setLogLevel` of the JS SDK, from
/// the most to the least verbose. Each level logs its own messages and those
/// of every level after it.
///
/// The default, before any call, is [warn].
enum LogLevel {
  /// Everything, including the most detailed messages.
  verbose,

  /// Debug messages and above, primarily for debugging.
  debug,

  /// Informational messages and above.
  info,

  /// Warnings and errors. The default.
  warn,

  /// Only errors are logged.
  error,

  /// Nothing is logged.
  silent,
}
