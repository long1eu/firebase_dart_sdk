import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:meta/meta.dart';

/// The codes of [FirebaseAppCheckException], in the order of its table.
const List<String> firebaseAppCheckExceptionCodes = <String>[
  'fetch-network-error',
  'fetch-timeout',
  'fetch-status-error',
  'fetch-parse-error',
  'throttled',
  'provider-error',
  'provider-timeout',
  'app-check-closed',
];

/// Thrown when getting an App Check token fails.
///
/// It extends [FirebaseException] with the [plugin] `firebase_app_check`, so
/// `on FirebaseException catch (e)` catches it too. Branch on [code]; [message] is a fixed text for
/// people. The codes are in [firebaseAppCheckExceptionCodes]:
///
/// | Code | When |
/// | --- | --- |
/// | `fetch-network-error` | the token request could not be sent or its answer could not be read (a refused redirect too) |
/// | `fetch-timeout` | no complete response in 7 s |
/// | `fetch-status-error` | the server answered with a status other than 200; see [httpStatus], [serverStatus] and [serverMessage] |
/// | `fetch-parse-error` | the answer is not the JSON the client expects, or is too large |
/// | `throttled` | token requests are paused after a failure, until about [retryAfter] |
/// | `provider-error` | the custom provider's callback threw (see [cause]) or returned a token that breaks a rule |
/// | `provider-timeout` | the custom provider's callback did not answer in 7 s |
/// | `app-check-closed` | the instance was closed |
///
/// A missing or malformed option of the app is not one of these: it is a [StateError] or an
/// [ArgumentError].
class FirebaseAppCheckException extends FirebaseException {
  /// Creates an exception with [code] and [message]. The package creates them; you need this only
  /// in tests.
  const FirebaseAppCheckException({
    required String code,
    required String message,
    this.httpStatus,
    this.serverStatus,
    this.serverMessage,
    this.retryAfter,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_app_check', code: code, message: message);

  /// The HTTP status of the response that caused the error. For `throttled`, the status of the
  /// failure that started the pause. Null when there was none.
  final int? httpStatus;

  /// The `error.status` of the server's error body (for example `PERMISSION_DENIED`), when it had
  /// one.
  final String? serverStatus;

  /// The `error.message` of the server's error body, with the debug token replaced by
  /// `<redacted>`, control characters removed, at most 1 KiB. It is the server's text: it is not
  /// part of [message] or [toString].
  final String? serverMessage;

  /// About when token requests are allowed again: the wall-clock time at which the pause that
  /// this failure started, or ran into, was expected to end.
  final DateTime? retryAfter;

  /// What the custom provider's callback threw. It is never part of [message] or [toString]: its
  /// text is the app's and may hold a secret. Do not log it.
  final Object? cause;

  @override
  String toString() {
    final int? status = httpStatus;
    return '[$plugin/$code] $message${status == null ? '' : ' (HTTP $status)'}';
  }
}

/// What is wrong with an answer of the exchange endpoint.
@internal
enum ParseProblem {
  /// A 2xx body over the cap.
  oversizedBody('an oversized body'),

  /// A body that is not UTF-8 JSON, or nests too deeply.
  notJson('a body that is not JSON'),

  /// No `token` string (also a body that is not a JSON object).
  noToken('no token'),

  /// A `token` that is not 1 to 8192 characters in U+0021 to U+007E.
  invalidToken('an invalid token'),

  /// A `ttl` that is missing, malformed or under 60 seconds.
  invalidTtl('an invalid ttl');

  const ParseProblem(this.text);

  /// The end of the exception's message.
  final String text;
}

/// What a custom provider's callback did wrong.
@internal
enum ProviderProblem {
  /// It threw.
  threw('threw'),

  /// Its token is not 1 to 8192 characters in U+0021 to U+007E.
  invalidToken('returned an invalid token'),

  /// Its token expires less than 60 s from now.
  expiresTooSoon('returned a token that expires within 60 s'),

  /// Asked to replace a rejected token, it returned the same one.
  sameToken('returned the token it was asked to replace');

  const ProviderProblem(this.text);

  /// The end of the exception's message.
  final String text;
}

/// `fetch-network-error`: the exchange could not be sent or read.
@internal
FirebaseAppCheckException fetchNetworkError() =>
    const FirebaseAppCheckException(
      code: 'fetch-network-error',
      message: 'The App Check token request could not reach the server.',
    );

/// `fetch-timeout`: no complete response within the deadline.
@internal
FirebaseAppCheckException fetchTimeout() => const FirebaseAppCheckException(
  code: 'fetch-timeout',
  message: 'The App Check token request timed out.',
);

/// `fetch-status-error`: a status other than 200. [serverStatus] and [serverMessage] must already
/// be checked and redacted.
@internal
FirebaseAppCheckException fetchStatusError({
  required int httpStatus,
  String? serverStatus,
  String? serverMessage,
}) => FirebaseAppCheckException(
  code: 'fetch-status-error',
  message: 'The App Check server refused the token request.',
  httpStatus: httpStatus,
  serverStatus: serverStatus,
  serverMessage: serverMessage,
);

/// `fetch-parse-error`: a 200 that breaks a rule, or an oversized 2xx.
@internal
FirebaseAppCheckException fetchParseError(ParseProblem problem) =>
    FirebaseAppCheckException(
      code: 'fetch-parse-error',
      message: 'The App Check server answered with ${problem.text}.',
    );

/// `throttled`: a gate refused the exchange. [retryAfter] is the gate's wall-clock estimate and
/// [httpStatus] the status of the failure that set the window.
@internal
FirebaseAppCheckException throttled({DateTime? retryAfter, int? httpStatus}) =>
    FirebaseAppCheckException(
      code: 'throttled',
      message: 'App Check token requests are paused after a failure.',
      retryAfter: retryAfter,
      httpStatus: httpStatus,
    );

/// `provider-error`: the custom callback threw [cause], or broke a rule.
@internal
FirebaseAppCheckException providerError(
  ProviderProblem problem, {
  Object? cause,
}) => FirebaseAppCheckException(
  code: 'provider-error',
  message: 'The custom App Check provider ${problem.text}.',
  cause: cause,
);

/// `provider-timeout`: the custom callback did not answer within the deadline.
@internal
FirebaseAppCheckException providerTimeout() => const FirebaseAppCheckException(
  code: 'provider-timeout',
  message: 'The custom App Check provider timed out.',
);

/// `app-check-closed`: a call after `close()`, or one that was waiting when it ran.
@internal
FirebaseAppCheckException appCheckClosed() => const FirebaseAppCheckException(
  code: 'app-check-closed',
  message: 'This FirebaseAppCheck was closed.',
);

/// A copy of [error] with [retryAfter] set: the failing call reports the window its failure
/// started.
@internal
FirebaseAppCheckException withRetryAfter(
  FirebaseAppCheckException error,
  DateTime retryAfter,
) => FirebaseAppCheckException(
  code: error.code,
  message: error.message ?? '',
  httpStatus: error.httpStatus,
  serverStatus: error.serverStatus,
  serverMessage: error.serverMessage,
  retryAfter: retryAfter,
  cause: error.cause,
  stackTrace: error.stackTrace,
);

/// True when [error] belongs to the "refused" class of the gates (the server answered, with a
/// status other than 200 or a body that breaks a rule): its windows grow to 4 h. Every other
/// failure is "unreachable", capped at 5 min.
@internal
bool isRefusal(FirebaseAppCheckException error) =>
    error.code == 'fetch-status-error' || error.code == 'fetch-parse-error';
