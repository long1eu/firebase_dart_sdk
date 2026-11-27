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

/// Receives log messages. Messages hold database paths, the shape of a query (its index, which
/// bounds are set, its limit), the type of a client-side error, a fixed reason, and the texts the
/// server sent (status reasons, shutdown reasons, security debug output), also inside a database
/// error.
///
/// The client never logs values it holds or sends: no token, no value read or written, no query
/// bound. A message from the server is logged as the server sent it (control characters escaped,
/// cut at 1 KiB) and, with rules debug output on (emulator), may quote data.
typedef DatabaseLogger = void Function(DatabaseLogLevel level, String message);
