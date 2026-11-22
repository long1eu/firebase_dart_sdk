/// The exception of the package and the mapping of wire status strings to it (owner K):
/// `rtdb_protocol.md` 9; threat model T7, T8.
library;

import 'package:firebase_app_dart/firebase_app_dart.dart';

/// The status strings of `rtdb_protocol.md` 9.
abstract final class RealtimeStatus {
  /// Success.
  static const String ok = 'ok';

  /// Rules deny; also the status of a `c` push and of REST 401.
  static const String permissionDenied = 'permission_denied';

  /// The data exceeds the size of one request.
  static const String tooBig = 'too_big';

  /// The service is unavailable.
  static const String unavailable = 'unavailable';

  /// A transaction put whose hash no longer matches: rerun.
  static const String datastale = 'datastale';

  /// The token was rejected (`auth`, `ac`, `apc`).
  static const String invalidToken = 'invalid_token';

  /// Local only: a sent transaction put lost its connection.
  static const String disconnect = 'disconnect';

  /// Local only: a transaction ran out of retries.
  static const String maxRetry = 'maxretry';

  /// Local only: a `set` overwrote the transaction's location.
  static const String set = 'set';

  /// Local only: the transaction had no data.
  static const String noData = 'nodata';

  /// Warning inside a listen response `d.w`: the query has no index rule.
  static const String noIndex = 'no_index';

  /// Prefix of the synthesised REST status `rest_error:<code>` (10).
  static const String restErrorPrefix = 'rest_error:';
}

/// Thrown when a Realtime Database operation fails.
///
/// Extends [FirebaseException] with the [plugin] `firebase_database` (Storage precedent). Neither
/// [message] nor [toString] holds a URL query, a request body or a token-provider message
/// (threat model T8); server text in [message] is cut at 1 KiB with control characters escaped
/// (T7).
final class FirebaseDatabaseException extends FirebaseException {
  /// Creates an exception with [code] (kebab case, for example `permission-denied`) and a
  /// [message].
  const FirebaseDatabaseException({
    required String code,
    required String message,
    this.status,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_database', code: code, message: message);

  /// The wire status that caused it (for example `permission_denied`), when it came from the
  /// server.
  final String? status;

  /// The error that caused this one when it came from outside the package (a token provider, the
  /// HTTP client). Never part of [message] or [toString]: it may hold credentials.
  final Object? cause;

  @override
  String toString() => '[$plugin/$code] $message';
}

/// The exception of a failed request with wire [status] and the server's [reason], at [path]
/// (9; core/util/util.ts:473-491, core/Repo.ts:892-917).
///
/// The code is [status] in kebab case (`permission_denied` -> `permission-denied`); the message is
/// `<STATUS> at <path>: <text>` with the standard text of 9 when [reason] is null.
FirebaseDatabaseException statusToError(
  String status,
  String? reason, {
  String? path,
}) {
  throw UnimplementedError();
}
