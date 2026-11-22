/// The exception of the public API. JS: `core/util/util.ts` (`errorForServerCode`); Android:
/// `DatabaseError.java`, `DatabaseException.java`.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:firebase_database_dart/src/core/database_error.dart';
import 'package:meta/meta.dart';

/// Thrown, or passed to a stream's `onError`, when a Realtime Database operation fails.
///
/// It extends [FirebaseException] with the [plugin] `firebase_database`, so `on FirebaseException catch (e)`
/// catches it too. Branch on [code]; [message] is for people, [serverStatus] is for logs. Every error that
/// comes from the server carries a code. Programmer errors (an invalid path, value or query) are not
/// exceptions of this class: they are [ArgumentError]s or [StateError]s thrown at the call.
///
/// | Code | Meaning |
/// | --- | --- |
/// | `permission-denied` | the security rules refused the read or write |
/// | `disconnected` | the connection dropped while a sent transaction or onDisconnect request waited for its answer |
/// | `max-retries` | a transaction ran its handler 25 times and the server still refused the value |
/// | `overridden-by-set` | a later `set` at the location replaced a running transaction |
/// | `unavailable` | the server is unavailable, or `Query.get` found no connection and no cache |
/// | `network-error` | the request failed for a network reason |
/// | `write-canceled` | `FirebaseDatabase.purgeOutstandingWrites` removed the write or transaction |
/// | `index-not-defined` | the query orders by a child that has no `.indexOn` rule (server status `no_index`) |
/// | `operation-failed` | the server reported that the operation failed (server status `failure`) |
/// | `too-big` | the data is larger than the server accepts in one request (server status `too_big`) |
/// | `read-only` | the connection is read only and refused a write or onDisconnect request |
/// | `database-closed` | the `FirebaseDatabase` was closed, or its app deleted |
/// | `unknown` | any other server status (`invalid_parameters`, `internal_error`, ...); the raw status is in [serverStatus] |
///
/// FlutterFire spells `write-canceled` as `write-cancelled`; the FlutterFire shim maps it.
///
/// ```dart
/// try {
///   await db.ref('admin/config').set(<String, Object?>{'open': true});
/// } on FirebaseDatabaseException catch (e) {
///   if (e.code == 'permission-denied') {
///     print('Not allowed.');
///   } else {
///     rethrow;
///   }
/// }
/// ```
final class FirebaseDatabaseException extends FirebaseException {
  /// Creates an exception with the [code] (for example `permission-denied`) and a [message]. The package
  /// creates them; you need this only in tests.
  const FirebaseDatabaseException({
    required String code,
    required String message,
    this.serverStatus,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_database', code: code, message: message);

  /// The raw status and reason the server sent, for example `permission_denied: Permission denied`, or null
  /// when the error did not come from the server. It never holds a token.
  final String? serverStatus;

  /// The error that caused this one, when it came from outside the package. It is never part of [message]
  /// or [toString]: its text may hold credentials.
  final Object? cause;

  @override
  String toString() {
    final String? status = serverStatus;
    final String base = '[$plugin/$code] $message';
    return status == null ? base : '$base ($status)';
  }
}

/// The codes a [FirebaseDatabaseException] can carry, in the order of its documentation table.
/// `data-stale` and `user-code-exception` are internal: a stale transaction is run again, and a throwing
/// transaction handler fails with its own error object.
@internal
const List<String> firebaseDatabaseExceptionCodes = <String>[
  'permission-denied',
  'disconnected',
  'max-retries',
  'overridden-by-set',
  'unavailable',
  'network-error',
  'write-canceled',
  'index-not-defined',
  'operation-failed',
  'too-big',
  'read-only',
  'database-closed',
  'unknown',
];

/// The public exception for a core [error]: the kebab-case code of [DatabaseError.code], its message, and
/// the wire status followed by the server's reason as [FirebaseDatabaseException.serverStatus] (none for
/// [DatabaseErrorCode.databaseClosed], which is local).
@internal
FirebaseDatabaseException exceptionFromDatabaseError(
  DatabaseError error, {
  StackTrace? stackTrace,
}) {
  final String? details = error.details;
  final String status = error.code.wireStatus;
  return FirebaseDatabaseException(
    code: error.code.code,
    message: error.message,
    serverStatus: error.code == DatabaseErrorCode.databaseClosed
        ? null
        : details == null
        ? status
        : '$status: $details',
    stackTrace: stackTrace,
  );
}

/// The public code for a server [status]: `no_index` is `index-not-defined`, `too_big` is `too-big`,
/// `failure` is `operation-failed`, the other statuses the client knows map to their own code, and any
/// other status (`invalid_parameters`, `internal_error`, `unknown`, ...) is `unknown`; the caller keeps
/// the raw status in [FirebaseDatabaseException.serverStatus].
@internal
String publicCodeForServerStatus(String status) {
  for (final DatabaseErrorCode code in DatabaseErrorCode.values) {
    if (code.wireStatus == status &&
        firebaseDatabaseExceptionCodes.contains(code.code)) {
      return code.code;
    }
  }
  return 'unknown';
}

/// The public exception for a failed server request with [status] and the server's optional [reason]:
/// the code of [publicCodeForServerStatus], and `status: reason` as
/// [FirebaseDatabaseException.serverStatus].
@internal
FirebaseDatabaseException exceptionFromServerStatus(
  String status, [
  String? reason,
  StackTrace? stackTrace,
]) => FirebaseDatabaseException(
  code: publicCodeForServerStatus(status),
  message: reason ?? status,
  serverStatus: reason == null ? status : '$status: $reason',
  stackTrace: stackTrace,
);
