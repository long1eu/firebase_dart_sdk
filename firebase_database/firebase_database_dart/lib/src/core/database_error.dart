/// Error codes and the internal error value. JS: `core/util/util.ts` (`errorForServerCode`),
/// `core/Repo.ts` (`repoCallOnCompleteCallback`); Android: `DatabaseError.java`.
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

  /// The supplied auth token has expired.
  expiredToken('expired-token', 'expired_token'),

  /// The supplied auth token was invalid.
  invalidToken('invalid-token', 'invalid_token'),

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
  static DatabaseErrorCode fromWireStatus(String status) => throw UnimplementedError();
}

/// An error raised by the database core: a [code], a human-readable [message] and optional
/// [details] (for example the server's reason text).
final class DatabaseError {
  /// Creates an error.
  const DatabaseError(this.code, this.message, {this.details});

  /// Creates the error for a wire [status] with the server's optional [reason], as Repo does for
  /// a failed request.
  factory DatabaseError.fromStatus(String status, [String? reason]) => throw UnimplementedError();

  /// The error code.
  final DatabaseErrorCode code;

  /// The message.
  final String message;

  /// Extra details, never containing tokens.
  final String? details;

  @override
  String toString() => throw UnimplementedError();
}
