/// Stand-ins for the decided seam changes that the core commit has not landed yet (owner: the
/// lead; temporary).
///
/// Every entry names its item of `rtdb_seam_changes.md`. When the core commit with section A
/// lands, delete this file and fix the imports and `with` clauses that the analyzer then reports:
/// each entry says what replaces it.
library;

import 'package:firebase_database_dart/src/core/connection/listen_spec.dart';

/// A.1: `ServerActions` still declares `refreshAuthToken` and `refreshAppCheckToken`; the decided
/// seam removes them (the connection subscribes to its `RealtimeTokenSource` itself). Mixed into
/// `PersistentConnection` and `RestClient` only so they implement today's interface. Replacement:
/// nothing; remove the `with SeamPendingTokenRefresh` clauses.
mixin SeamPendingTokenRefresh {
  /// Not part of the decided seam: tokens reach the connection through its token source.
  void refreshAuthToken(String? token) {
    throw UnsupportedError(
      'Tokens reach the connection through its RealtimeTokenSource.',
    );
  }

  /// Not part of the decided seam: tokens reach the connection through its token source.
  void refreshAppCheckToken(String? token) {
    throw UnsupportedError(
      'Tokens reach the connection through its RealtimeTokenSource.',
    );
  }
}

/// A.2: the typed failure of `ServerActions.get`, decided as
/// `final class ServerActionsException implements Exception` in `server_actions.dart`.
/// Replacement: the core's class of the same name and shape.
final class ServerActionsException implements Exception {
  /// Creates the failure with the wire [status] and the server's [reason].
  const ServerActionsException(this.status, [this.reason]);

  /// The wire status, for example `permission_denied`.
  final String status;

  /// The server's reason text, if any.
  final String? reason;

  @override
  String toString() => reason == null
      ? 'ServerActionsException($status)'
      : 'ServerActionsException($status: $reason)';
}

/// A.4: `ListenSpec` gains `final Map<String, String> restParams` (from
/// `QueryParams.toRestQueryStringParameters()`). Once the field exists it shadows this extension.
/// Replacement: the field.
extension SeamPendingRestParams on ListenSpec {
  /// The REST query parameters of the query (`rtdb_protocol.md` 6.4).
  Map<String, String> get restParams => throw UnimplementedError();
}

/// A.7: the status a read-only `ServerActions` completes writes and onDisconnects with, decided
/// as `DatabaseErrorCode.readOnly('read-only', 'read_only')`. Replacement:
/// `DatabaseErrorCode.readOnly.wireStatus`.
const String statusReadOnly = 'read_only';

/// A.10: `core/util/logger.dart`, decided as
/// `enum DatabaseLogLevel { debug, info, warning, error }`. Replacement: the core's enum.
enum DatabaseLogLevel {
  /// Wire-level detail; may hold user data, never tokens.
  debug,

  /// State changes (connected, disconnected).
  info,

  /// Something the developer should fix (`no_index`, repeated invalid tokens).
  warning,

  /// A failure the client could not handle.
  error,
}

/// A.10: decided as
/// `typedef DatabaseLogger = void Function(DatabaseLogLevel level, String message);` in
/// `core/util/logger.dart`. Replacement: the core's typedef.
typedef DatabaseLogger = void Function(DatabaseLogLevel level, String message);
