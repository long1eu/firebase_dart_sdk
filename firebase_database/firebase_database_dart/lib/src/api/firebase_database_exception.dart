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
/// | `overridden-by-set` | a write that overlaps a running transaction overrode it (`DatabaseReference.runTransaction` says when) |
/// | `unavailable` | the server is unavailable, or `Query.get` found no connection and no cache |
/// | `network-error` | the request failed for a network reason |
/// | `write-canceled` | `FirebaseDatabase.purgeOutstandingWrites` removed the write or transaction |
/// | `index-not-defined` | the query orders by a child that has no `.indexOn` rule (server status `no_index`) |
/// | `operation-failed` | the server reported that the operation failed (server status `failure`) |
/// | `too-big` | the data is larger than the server accepts in one request (server status `too_big`) |
/// | `database-closed` | a Future of a `FirebaseDatabase` that was closed, or whose app was deleted (streams end with done instead) |
/// | `data-stale` | the server answered `datastale` to a request other than a transaction's (a fake server can) |
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

  /// The error that caused this one, when there is one (an error from outside the package, or the
  /// error behind a failure the client raised itself). It is never part of [message] or [toString]: its
  /// text may hold credentials. Where it was thrown, when the client knows, is [stackTrace].
  final Object? cause;

  @override
  String toString() {
    final String? status = serverStatus;
    final String base = '[$plugin/$code] $message';
    return status == null ? base : '$base ($status)';
  }
}

/// The codes a [FirebaseDatabaseException] can carry, in the order of its documentation table.
/// `user-code-exception` is internal: a throwing transaction handler fails with its own error object. A
/// transaction answered `datastale` is run again; `data-stale` reaches a caller only for another request.
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
  'database-closed',
  'data-stale',
  'unknown',
];

/// The public exception for a core [error]: the kebab-case code of [DatabaseError.code], its message, and
/// the wire status followed by the server's reason as [FirebaseDatabaseException.serverStatus]. There is
/// none for [DatabaseErrorCode.databaseClosed] and for a [DatabaseError.isLocal] error, which did not come
/// from the server; the cause of a local error is [FirebaseDatabaseException.cause], and where it was
/// thrown ([DatabaseError.causeStackTrace]) is [FirebaseException.stackTrace] unless [stackTrace] is
/// given. For a status the client does not know, the details already hold `status: reason` and are the
/// [FirebaseDatabaseException.serverStatus] as they are.
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
    serverStatus:
        error.code == DatabaseErrorCode.databaseClosed || error.isLocal
        ? null
        : error.rawStatus != null
        ? details
        : details == null
        ? status
        : '$status: $details',
    cause: error.cause,
    stackTrace: stackTrace ?? error.causeStackTrace,
  );
}
