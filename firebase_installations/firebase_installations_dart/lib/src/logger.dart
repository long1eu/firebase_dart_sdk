/// The severity of a message passed to an [InstallationsLogger].
enum InstallationsLogLevel {
  /// Details of each step, for debugging.
  debug,

  /// Events worth knowing, such as a new installation.
  info,

  /// Something failed and the client recovered or will retry.
  warning,

  /// Something failed and the caller will see an error.
  error,
}

/// Receives the log messages of `FirebaseInstallations` and of the stores.
///
/// Pass one to the constructor; with none the client is silent. Messages never hold a refresh token, an
/// auth token, the API key or a request body.
typedef InstallationsLogger =
    void Function(InstallationsLogLevel level, String message);
