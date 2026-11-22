/// Logging hook of the client. JS: `core/util/util.ts` (`log`, `warn`, `logger`); Android:
/// `logging/LogWrapper.java`, `logging/Logger.java`.
///
/// Passed to Repo, to the connection (through `ServerActionsFactory`) and to the persistence
/// opener. Needed for the persistence lease, degraded (memory-only) mode, the `no_index` warning
/// and failed persisted writes.
library;

/// How important a log message is.
enum DatabaseLogLevel {
  /// Detail for debugging (protocol traffic, state changes).
  debug,

  /// Normal operation worth noting.
  info,

  /// Something the user should fix or know (`no_index`, degraded persistence).
  warning,

  /// A failure the client recovered from or reported.
  error,
}

/// Receives log messages. Messages hold database paths and the texts the server sent, never
/// tokens and never the values you read or write.
typedef DatabaseLogger = void Function(DatabaseLogLevel level, String message);
