import 'package:firebase_app_dart/firebase_app_dart.dart';

/// Every [FirebaseInstallationsException.code] the package throws.
const List<String> firebaseInstallationsExceptionCodes = <String>[
  'invalid-app-config',
  'bad-config',
  'installation-not-found',
  'too-many-requests',
  'unavailable',
  'network-error',
  'invalid-response',
  'storage-error',
  'installations-closed',
];

/// Thrown when an operation of `FirebaseInstallations` or of a store fails.
///
/// It extends [FirebaseException] with the plugin `firebase_installations`. Branch on [code]:
///
/// | Code | When |
/// | --- | --- |
/// | `invalid-app-config` | the app's `apiKey`, `appId` or `projectId` is missing or malformed |
/// | `bad-config` | the server answered 400 or 403 (no request for 24 h), or 401 or 404 to a registration; [retryAfter] |
/// | `installation-not-found` | the server forgot the installation twice in one call (401 or 404 to a token request) |
/// | `too-many-requests` | the server answered 429, or the call fell inside a backoff window opened by a 429, 5xx, 3xx, unexpected 4xx or 409 (windows opened by `bad-config` rethrow it); [retryAfter] |
/// | `unavailable` | the server kept failing (5xx), the call took more than 60 s, or the record kept changing under the call |
/// | `network-error` | the request could not be sent or took more than 10 s |
/// | `invalid-response` | the server's answer could not be used (a bad body, a redirect, an unexpected 4xx status), or it rejected a new installation id twice (409) |
/// | `storage-error` | the store is misconfigured, in use by another process, or could not be written |
/// | `installations-closed` | the instance was closed |
///
/// [message] and [toString] never hold a token, the API key or a request body; text from the server is
/// only in [serverStatus] and [serverMessage].
class FirebaseInstallationsException extends FirebaseException {
  /// Creates an exception with [code] (one of [firebaseInstallationsExceptionCodes]) and [message]. The
  /// package creates them; you need this only in tests.
  const FirebaseInstallationsException({
    required String code,
    required String message,
    this.httpStatus,
    this.serverStatus,
    this.serverMessage,
    this.retryAfter,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_installations', code: code, message: message);

  /// The HTTP status of the response that caused the error, or null when there was none.
  final int? httpStatus;

  /// The `error.status` of the server's error body (for example `PERMISSION_DENIED`), when it had one.
  final String? serverStatus;

  /// The `error.message` of the server's error body, control characters removed, at most 1 KiB.
  final String? serverMessage;

  /// When requests are allowed again, for `bad-config` and `too-many-requests` while the backoff runs.
  final DateTime? retryAfter;

  /// The error that caused this one (for example a transport exception). It is never part of [message] or
  /// [toString]: its text may hold a URL.
  final Object? cause;

  @override
  String toString() {
    final int? status = httpStatus;
    return status == null
        ? '[$plugin/$code] $message'
        : '[$plugin/$code] $message (HTTP $status)';
  }
}
