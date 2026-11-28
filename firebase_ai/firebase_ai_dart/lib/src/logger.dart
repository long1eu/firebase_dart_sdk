/// The severity of a message given to an [AILogger].
enum AILogLevel {
  /// Details of normal operation, such as a request being sent.
  debug,

  /// Notable events of normal operation.
  info,

  /// Something went wrong and the client went on, such as a token provider that failed.
  warning,

  /// Something went wrong and an operation failed.
  error,
}

/// Receives the log messages of a `FirebaseAI` instance and its models and chats.
///
/// Pass one to the constructor; without it the client is silent. Messages never hold a token, the
/// API key, a request body, a prompt, a response text or a function argument.
typedef AILogger = void Function(AILogLevel level, String message);
