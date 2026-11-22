/// Temporary declarations of core types that exist only on the seam branch. JS: none; Android:
/// `core/utilities/LogWrapper.java` (the logger).
///
/// Every declaration here is a stand-in for a core type that `rtdb_seam_changes.md` adds in another
/// worktree. Each one carries a `// MERGE:` comment that says what replaces it. After the merge this
/// file is deleted and the file that exports it re-exports the core declaration instead.
library;

// MERGE: rtdb_seam_changes.md section A, item 10 declares both types below in
// `lib/src/core/util/logger.dart`, with the same names, values and parameter list. On merge, delete this
// file and change the export in `lib/src/api/database_logger.dart` to
//   export 'package:firebase_database_dart/src/core/util/logger.dart' show DatabaseLogLevel, DatabaseLogger;

/// The severity of a message passed to a [DatabaseLogger].
enum DatabaseLogLevel {
  /// Detail for debugging the client: requests, responses, state changes.
  debug,

  /// Normal events worth a line in a log, such as a connection being made.
  info,

  /// Something went wrong and the client worked around it, for example persistence falling back to
  /// memory only.
  warning,

  /// Something failed and the client could not recover it.
  error,
}

/// Receives the client's log messages. A message never holds a token or other credential.
///
/// ```dart
/// final FirebaseDatabase db = FirebaseDatabase(
///   app,
///   logger: (DatabaseLogLevel level, String message) {
///     if (level.index >= DatabaseLogLevel.warning.index) print('[$level] $message');
///   },
/// );
/// ```
typedef DatabaseLogger = void Function(DatabaseLogLevel level, String message);
