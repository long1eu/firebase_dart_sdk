/// The severity of a message given to a [RemoteConfigLogger].
enum RemoteConfigLogLevel {
  /// Details of normal operation, such as a realtime connection opening.
  debug,

  /// Notable events of normal operation, such as a stored record being replaced.
  info,

  /// Something went wrong and the client recovered, such as a stored record that could not be read.
  warning,

  /// Something went wrong and an operation failed.
  error,
}

/// Receives the log messages of a `FirebaseRemoteConfig`.
///
/// Pass one to the constructor; without it the client is silent. Messages never hold a token, the API
/// key, a request body, a parameter value or the text of a custom signal.
typedef RemoteConfigLogger =
    void Function(RemoteConfigLogLevel level, String message);
