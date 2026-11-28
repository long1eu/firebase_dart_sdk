import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_app_check_dart/src/exception.dart';
import 'package:meta/meta.dart';

/// The severity of a message given to an [AppCheckLogger].
enum AppCheckLogLevel {
  /// Details of normal operation, such as a token being received.
  debug,

  /// Notable events of normal operation, such as a stored token being ignored.
  info,

  /// Something went wrong and the client recovered or will try again, such as a failed token
  /// request.
  warning,

  /// Something went wrong and an operation failed.
  error,
}

/// Receives the log messages of a `FirebaseAppCheck`.
///
/// Pass one to the constructor; without it the package logs and prints nothing. Messages never
/// hold a debug token, an App Check token, the API key, a URL, a request or response body, or the
/// server's or a custom provider's own text.
typedef AppCheckLogger = void Function(AppCheckLogLevel level, String message);

/// A store operation that can fail (the line L6).
@internal
enum StoreOperation {
  /// Reading the record.
  read,

  /// Writing the record.
  write,

  /// Removing a record that was refused.
  remove,
}

/// Seconds of [wait], rounded up and never negative: a wait that is not over never reads "0 s".
int _wholeSeconds(Duration wait) {
  if (wait <= Duration.zero) {
    return 0;
  }
  return (wait.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
}

/// L1 (warning): a debug provider is in use for the app named [app].
@internal
String debugProviderInUseText(String app) =>
    'App Check debug provider in use for app $app. A debug token is a secret: '
    'do not ship it in a distributed build.';

/// L2 (debug): a token arrived from this instance's own exchange; the refresher runs in
/// [nextRefresh].
@internal
String tokenReceivedText(String app, Duration nextRefresh) =>
    'App Check token received for app $app; next refresh in '
    '${_wholeSeconds(nextRefresh)} s.';

/// L3 (warning): an exchange failed with [error]; the gate allows the next one in [nextAttempt].
///
/// Only the code, the HTTP status and the checked `serverStatus` of [error] are printed; never its
/// `serverMessage` or `cause`.
@internal
String requestFailedText(
  String app,
  FirebaseAppCheckException error,
  Duration nextAttempt,
) {
  final int? status = error.httpStatus;
  final String? serverStatus = error.serverStatus;
  final String detail = status == null
      ? ''
      : serverStatus == null
      ? ' (HTTP $status)'
      : ' (HTTP $status, $serverStatus)';
  return 'App Check token request failed for app $app: ${error.code}$detail; '
      'next attempt in ${_wholeSeconds(nextAttempt)} s.';
}

/// L4 (warning, once per window): a gate refused a call; its window ends in [remaining].
@internal
String requestsPausedText(String app, Duration remaining) =>
    'App Check token requests for app $app are paused for '
    '${_wholeSeconds(remaining)} s.';

/// L5 (warning, on the first seam call after each unbinding).
@internal
String closedText(String app) =>
    'FirebaseAppCheck for app $app was closed; services that were created '
    'before this close now send no App Check token.';

/// L6 (warning, once per instance and operation): the store failed in [operation].
@internal
String storeFailedText(String app, StoreOperation operation) =>
    'App Check token store failed for app $app (${operation.name}); '
    'continuing in memory.';

/// L7 (info, once per instance and reason): a stored record was ignored for [reason], one of the
/// fixed reasons of the record rules (never a stored value).
@internal
String storedTokenIgnoredText(String app, String reason) =>
    'Stored App Check token for app $app ignored: $reason.';

/// A [LogOnce] that writes to [logger] at [level]: for the lines that are written once. With no
/// logger it drops everything.
@internal
LogOnce logOnceAt(AppCheckLogger? logger, AppCheckLogLevel level) =>
    LogOnce(logger == null ? null : (String message) => logger(level, message));
