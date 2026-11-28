import 'package:firebase_ai_dart/src/response.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart';
import 'package:meta/meta.dart';

/// Thrown when an AI Logic call fails, and by the accessors of a blocked response.
///
/// It extends [FirebaseException] with the [plugin] `firebase_ai`, so
/// `on FirebaseException catch (e)` catches it too. Branch on [code]; [message] is for people. The
/// codes are in [firebaseAIExceptionCodes]:
///
/// | Code | When |
/// | --- | --- |
/// | `api-not-enabled` | the AI Logic API is not enabled for the project (HTTP 403) |
/// | a canonical code, such as `invalid-argument` | any other non-2xx answer; see [httpStatus] |
/// | `unauthenticated` | the Auth provider failed ([httpStatus] null) |
/// | `failed-precondition` | the Auth token is too long ([httpStatus] null) |
/// | `deadline-exceeded` | the call's timeout passed ([httpStatus] null) |
/// | `unavailable` | the request or its answer did not arrive, or a redirect ([httpStatus] null) |
/// | `cancelled` | the call's `abortTrigger` completed |
/// | `parse-failed` | the answer is not the JSON the client expects |
/// | `response-too-large` | the answer is larger than the client accepts |
/// | `response-error` | a response accessor found a blocked prompt or candidate; see [response] |
/// | `unsupported` | a request field the Gemini Developer API does not accept |
/// | `ai-closed` | the `FirebaseAI` instance was closed |
///
/// When [httpStatus] is null, the failure happened in the client, which tells a local
/// `deadline-exceeded` from the same code answered by the server.
final class FirebaseAIException extends FirebaseException {
  /// Creates an exception with [code] and [message]. The package creates them; you need this only
  /// in tests.
  const FirebaseAIException({
    required String code,
    required String message,
    this.httpStatus,
    this.serverStatus,
    this.serverMessage,
    this.reason,
    this.retryAfter,
    this.response,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_ai', code: code, message: message);

  /// The HTTP status of the answer that caused the error, or null when the failure happened in the
  /// client.
  final int? httpStatus;

  /// The `error.status` of the server's error body, for example `RESOURCE_EXHAUSTED`.
  final String? serverStatus;

  /// The `error.message` of the server's error body, control characters removed, at most 1 KiB. It
  /// is not part of [message] or [toString].
  final String? serverMessage;

  /// The `reason` of the first `google.rpc.ErrorInfo` detail of the error body, for example
  /// `API_KEY_INVALID`.
  final String? reason;

  /// How long the server asked the client to wait before retrying, from a `google.rpc.RetryInfo`
  /// detail or a `Retry-After` header; between zero and 24 hours. The client never waits on it.
  final Duration? retryAfter;

  /// For `response-error`, the blocked response. For a stream that failed after at least one chunk,
  /// the chunks received so far, aggregated. It is never part of [message] or [toString].
  final GenerateContentResponse? response;

  /// The error that caused this one, when it is safe to keep. It is null for token and transport
  /// failures, and never part of [message] or [toString].
  final Object? cause;

  /// A copy with [response] set. Used by the package only.
  @internal
  FirebaseAIException withResponse(GenerateContentResponse response) {
    return FirebaseAIException(
      code: code,
      message: message ?? '',
      httpStatus: httpStatus,
      serverStatus: serverStatus,
      serverMessage: serverMessage,
      reason: reason,
      retryAfter: retryAfter,
      response: response,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() {
    final String status = httpStatus == null ? '' : ' (HTTP $httpStatus)';
    return '[$plugin/$code] $message$status';
  }
}

/// Every [FirebaseAIException.code] the package uses.
const List<String> firebaseAIExceptionCodes = <String>[
  'api-not-enabled',
  'invalid-argument',
  'failed-precondition',
  'out-of-range',
  'unauthenticated',
  'permission-denied',
  'not-found',
  'aborted',
  'already-exists',
  'resource-exhausted',
  'cancelled',
  'deadline-exceeded',
  'unimplemented',
  'internal',
  'unavailable',
  'data-loss',
  'unknown',
  'parse-failed',
  'response-too-large',
  'response-error',
  'unsupported',
  'ai-closed',
];

/// The exception of a call made after `close()`, or aborted by it.
@internal
FirebaseAIException aiClosedException() => const FirebaseAIException(
  code: 'ai-closed',
  message: 'The FirebaseAI instance was closed.',
);
