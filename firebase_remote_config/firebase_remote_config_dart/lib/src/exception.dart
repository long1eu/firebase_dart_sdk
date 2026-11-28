import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:meta/meta.dart';

/// Thrown when a Remote Config operation fails, and added to `onConfigUpdated` for realtime errors.
///
/// It extends [FirebaseException] with the [plugin] `firebase_remote_config`, so `on FirebaseException
/// catch (e)` catches it too. Branch on [code]; [message] is for people. The codes are in
/// [firebaseRemoteConfigExceptionCodes]:
///
/// | Code | When |
/// | --- | --- |
/// | `invalid-app-config` | the app options lack `projectId`, `apiKey` or `appId` |
/// | `installations-error` | getting the installation id or its token failed; [cause] is the Installations exception |
/// | `fetch-client-network` | the request did not reach the server or its answer did not arrive (a refused redirect on the web too) |
/// | `fetch-timeout` | the call took longer than its timeout |
/// | `fetch-throttle` | inside a throttle window, or the server answered 429; see [throttledUntil] |
/// | `fetch-client-parse` | the answer is not the JSON the client expects, or is too large |
/// | `fetch-status` | another HTTP status; see [httpStatus] and [serverMessage] |
/// | `storage-error` | the store refused to start, or a write that must persist failed |
/// | `stream-error` | realtime: eight failures in a row, a status that will not change by retrying, or a configuration error |
/// | `realtime-unavailable` | the server disabled realtime for this app |
/// | `update-message-invalid` | a realtime message could not be read |
/// | `update-not-fetched` | the fetch after a realtime update failed or did not get the new template |
/// | `remote-config-closed` | the instance was closed |
final class FirebaseRemoteConfigException extends FirebaseException {
  /// Creates an exception with [code] and [message]. The package creates them; you need this only in
  /// tests.
  const FirebaseRemoteConfigException({
    required String code,
    required String message,
    this.httpStatus,
    this.serverStatus,
    this.serverMessage,
    this.throttledUntil,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_remote_config', code: code, message: message);

  /// The HTTP status of the response that caused the error, or null when there was none.
  final int? httpStatus;

  /// The `error.status` of the server's error body (for example `PERMISSION_DENIED`), when it had one.
  final String? serverStatus;

  /// The `error.message` of the server's error body, control characters removed, at most 1 KiB. It is
  /// not part of [message] or [toString].
  final String? serverMessage;

  /// The end of the throttle window that this error started, extended or ran into.
  final DateTime? throttledUntil;

  /// The error that caused this one (an Installations exception, a transport error). It is never part
  /// of [message] or [toString]: its text may hold a URL or request data, such as a header value
  /// (an ETag, the API key or the installation token). Do not log it.
  final Object? cause;

  /// A copy with [throttledUntil] set and, when given, another [code]. Used by the package only.
  @internal
  FirebaseRemoteConfigException withThrottle(
    DateTime throttledUntil, {
    String? code,
  }) {
    return FirebaseRemoteConfigException(
      code: code ?? this.code,
      message: message ?? '',
      httpStatus: httpStatus,
      serverStatus: serverStatus,
      serverMessage: serverMessage,
      throttledUntil: throttledUntil,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() {
    final String status = httpStatus == null ? '' : ' (HTTP $httpStatus)';
    final DateTime? until = throttledUntil;
    final String throttle = until == null
        ? ''
        : ' Throttled until ${until.toUtc().toIso8601String()}.';
    return '[$plugin/$code] $message$status$throttle';
  }
}

/// Every [FirebaseRemoteConfigException.code] the package uses.
const List<String> firebaseRemoteConfigExceptionCodes = <String>[
  'invalid-app-config',
  'installations-error',
  'fetch-client-network',
  'fetch-timeout',
  'fetch-throttle',
  'fetch-client-parse',
  'fetch-status',
  'storage-error',
  'stream-error',
  'realtime-unavailable',
  'update-message-invalid',
  'update-not-fetched',
  'remote-config-closed',
];

/// The exception of a call made after `close()`.
FirebaseRemoteConfigException closedException() =>
    const FirebaseRemoteConfigException(
      code: 'remote-config-closed',
      message: 'The FirebaseRemoteConfig instance was closed.',
    );
