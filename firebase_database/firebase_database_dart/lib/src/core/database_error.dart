/// Error codes and the internal error value. JS: `core/util/util.ts` (`errorForServerCode`),
/// `core/Repo.ts` (`repoCallOnCompleteCallback`); Android: `DatabaseError.java`.
///
/// The one error vocabulary of the client: the realtime half maps wire status strings to
/// [DatabaseErrorCode] and declares no exception class of its own for server statuses; the public
/// `FirebaseDatabaseException` is defined once, in the public API layer.
library;

/// A Realtime Database error code: the public kebab-case [code] and the [wireStatus] the server or
/// the connection uses for it.
enum DatabaseErrorCode {
  /// The transaction needs to be run again with current data.
  dataStale('data-stale', 'datastale'),

  /// The server indicated that this operation failed.
  operationFailed('operation-failed', 'failure'),

  /// The client does not have permission to perform this operation.
  permissionDenied('permission-denied', 'permission_denied'),

  /// The operation had to be aborted due to a network disconnect.
  disconnected('disconnected', 'disconnected'),

  /// The transaction had too many retries.
  maxRetries('max-retries', 'maxretries'),

  /// The transaction was overridden by a subsequent set.
  overriddenBySet('overridden-by-set', 'overriddenbyset'),

  /// The service is unavailable.
  unavailable('unavailable', 'unavailable'),

  /// The requested data exceeds the maximum size of a single request.
  tooBig('too-big', 'too_big'),

  /// An exception occurred in user code (a transaction handler).
  userCodeException('user-code-exception', 'user_code_exception'),

  /// The operation could not be performed due to a network error.
  networkError('network-error', 'network_error'),

  /// The write was canceled by the user (purgeOutstandingWrites).
  writeCanceled('write-canceled', 'write_canceled'),

  /// The query orders by a child the security rules give no `.indexOn` (the server's `no_index`).
  indexNotDefined('index-not-defined', 'no_index'),

  /// The database instance was closed (or its app deleted); every later asynchronous call fails with
  /// this code. Local only: the server never sends it.
  databaseClosed('database-closed', 'database_closed'),

  /// An unknown error occurred.
  unknown('unknown', 'unknown');

  const DatabaseErrorCode(this.code, this.wireStatus);

  /// The public kebab-case code.
  final String code;

  /// The status string the server sends (or the connection synthesises) for this code.
  final String wireStatus;

  /// The code for a wire [status]; JS-only local statuses map as follows: `disconnect` to
  /// [disconnected], `maxretry` to [maxRetries], `set` to [overriddenBySet], anything else to
  /// [unknown].
  ///
  /// Matching ignores case, as Android `DatabaseError.fromStatus` lower-cases the status, so
  /// Android's local `overriddenBySet` also maps to [overriddenBySet]. JS: `errorForServerCode`;
  /// Android: `DatabaseError.fromStatus`.
  static DatabaseErrorCode fromWireStatus(String status) {
    final String lower = status.toLowerCase();
    switch (lower) {
      case 'disconnect':
        return disconnected;
      case 'maxretry':
        return maxRetries;
      case 'set':
        return overriddenBySet;
    }
    for (final DatabaseErrorCode code in values) {
      if (code.wireStatus == lower) {
        return code;
      }
    }
    return unknown;
  }
}

/// An error raised by the database core: a [code], a human-readable [message] and optional
/// [details] (for example the server's reason text).
final class DatabaseError {
  /// Creates an error.
  const DatabaseError(this.code, this.message, {this.details, this.rawStatus});

  /// Creates the error for a wire [status] with the server's optional [reason], as Repo does for
  /// a failed request.
  ///
  /// The code comes from [DatabaseErrorCode.fromWireStatus], the message from the code. [details]
  /// is [reason]. For a status the client does not know (mapped to [DatabaseErrorCode.unknown]),
  /// [rawStatus] is that status, [details] is the status followed by the reason
  /// (`invalid_parameters: ...`), so the public `serverStatus` keeps it, and the message is the
  /// reason when there is one (as Android). JS: `errorForServerCode`; Android:
  /// `DatabaseError.fromStatus`.
  factory DatabaseError.fromStatus(String status, [String? reason]) {
    final DatabaseErrorCode code = DatabaseErrorCode.fromWireStatus(status);
    if (code == DatabaseErrorCode.unknown &&
        status.toLowerCase() != 'unknown') {
      return DatabaseError(
        code,
        reason ?? _messageFor(code),
        details: reason == null ? status : '$status: $reason',
        rawStatus: status,
      );
    }
    return DatabaseError(code, _messageFor(code), details: reason);
  }

  /// The error code.
  final DatabaseErrorCode code;

  /// The message.
  final String message;

  /// Extra details, never containing tokens.
  final String? details;

  /// The status the server sent when the client does not know it (the code is then
  /// [DatabaseErrorCode.unknown] and [details] starts with this status); null otherwise.
  final String? rawStatus;

  /// The code, message and details; never a token (Android `DatabaseError.toString`).
  @override
  String toString() =>
      'DatabaseError(${code.code}): $message'
      '${details == null ? '' : ' ($details)'}';
}

/// The human-readable message of this code (Android `DatabaseError.errorReasons`, JS
/// `errorForServerCode`).
String _messageFor(DatabaseErrorCode code) => switch (code) {
  DatabaseErrorCode.dataStale =>
    'The transaction needs to be run again with current data.',
  DatabaseErrorCode.operationFailed =>
    'The server indicated that this operation failed.',
  DatabaseErrorCode.permissionDenied =>
    'This client does not have permission to perform this operation.',
  DatabaseErrorCode.disconnected =>
    'The operation had to be aborted due to a network disconnect.',
  DatabaseErrorCode.maxRetries => 'The transaction had too many retries.',
  DatabaseErrorCode.overriddenBySet =>
    'The transaction was overridden by a subsequent set.',
  DatabaseErrorCode.unavailable => 'The service is unavailable.',
  DatabaseErrorCode.tooBig =>
    'The data requested exceeds the maximum size that can be accessed with '
        'a single request.',
  DatabaseErrorCode.userCodeException =>
    'User code called from the database threw an exception.',
  DatabaseErrorCode.networkError =>
    'The operation could not be performed due to a network error.',
  DatabaseErrorCode.writeCanceled => 'The write was canceled by the user.',
  DatabaseErrorCode.indexNotDefined =>
    'Index not defined: add ".indexOn" to the security rules for this query.',
  DatabaseErrorCode.databaseClosed => 'The database was closed.',
  DatabaseErrorCode.unknown => 'An unknown error occurred.',
};
