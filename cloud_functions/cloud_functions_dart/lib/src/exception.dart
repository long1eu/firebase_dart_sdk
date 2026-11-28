import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:cloud_functions_dart/src/platform.dart';
import 'package:firebase_app_dart/firebase_app_dart.dart'
    show FirebaseException;
import 'package:meta/meta.dart';

/// Thrown when a callable function call or stream fails.
///
/// It extends [FirebaseException] with the plugin `firebase_functions`, as FlutterFire's
/// exception does, so `on FirebaseException catch (e)` catches it too. Branch on [code], one of
/// [firebaseFunctionsExceptionCodes]; [message] is for people.
///
/// The function chose the code when it threw an `HttpsError`; the server's message and [details]
/// are kept for every code. The client makes these codes itself:
///
/// - `unavailable`: the request did not reach the server, or the connection broke (on the web
///   also a response without CORS headers); the auth token provider did not answer within 10 s.
/// - `deadline-exceeded`: the call did not finish within its timeout; a stream got no response,
///   or no bytes, for its timeout.
/// - `cancelled`: the abort trigger completed, or the `FirebaseFunctions` was closed.
/// - `unauthenticated`: the auth token provider failed.
/// - `failed-precondition`: the ID token is longer than 8192 characters; tokens may not be sent
///   to the URL.
/// - `internal`: the response is not a callable response, is too large or holds an invalid value.
///
/// A response without a callable error body takes its code from the HTTP status (404 is
/// `not-found`, 500 is `internal`, and so on); see [httpStatus].
final class FirebaseFunctionsException extends FirebaseException {
  /// Creates an exception with [code] and [message]. The package creates them; you need this only
  /// in tests.
  const FirebaseFunctionsException({
    required String code,
    required String message,
    this.details,
    this.httpStatus,
    this.cause,
    super.stackTrace,
  }) : super(plugin: 'firebase_functions', code: code, message: message);

  /// The decoded `details` of the function's error, or null.
  final Object? details;

  /// The HTTP status of the response, or null when there was none (a network error, a timeout, a
  /// cancel or a token failure).
  final int? httpStatus;

  /// Always null in this version.
  ///
  /// A token failure is described only by the provider error's type name in [message]; a transport
  /// failure carries nothing, since the transport's text can print the request URL.
  final Object? cause;

  /// `[firebase_functions/<code>] <message>`, plus ` (HTTP <n>)` when [httpStatus] is set. It never
  /// holds [details] or [cause].
  @override
  String toString() {
    final int? status = httpStatus;
    final String suffix = status == null ? '' : ' (HTTP $status)';
    return '[$plugin/$code] $message$suffix';
  }
}

/// The codes a [FirebaseFunctionsException] can have: the 16 canonical error codes in kebab case.
const Set<String> firebaseFunctionsExceptionCodes = <String>{
  'cancelled',
  'unknown',
  'invalid-argument',
  'deadline-exceeded',
  'not-found',
  'already-exists',
  'permission-denied',
  'resource-exhausted',
  'failed-precondition',
  'aborted',
  'out-of-range',
  'unimplemented',
  'internal',
  'unavailable',
  'data-loss',
  'unauthenticated',
};

/// The message of a call that was cancelled by its abort trigger or a stream subscription cancel.
@internal
const String cancelledMessage = 'The call was cancelled.';

/// The message of a call that was ended by `FirebaseFunctions.close` or the deletion of its app.
@internal
const String closedMessage = 'This FirebaseFunctions was closed.';

/// The message of a response body over 32 MiB, or of a stream event over 32 MiB.
@internal
const String tooLargeMessage = 'Response is larger than 32 MiB.';

/// The message of a value the decoder refused (§5.6 rule 4).
@internal
const String invalidValueMessage = 'Response contains an invalid value.';

/// An `internal` exception with [message], for a response with [httpStatus].
@internal
FirebaseFunctionsException internalError(
  String message, {
  int? httpStatus,
  Object? details,
}) {
  return FirebaseFunctionsException(
    code: RpcStatus.internal.kebab,
    message: message,
    details: details,
    httpStatus: httpStatus,
  );
}

/// A `cancelled` exception; [closed] picks the message of `close()` over the abort trigger's.
@internal
FirebaseFunctionsException cancelledError({required bool closed}) {
  return FirebaseFunctionsException(
    code: RpcStatus.cancelled.kebab,
    message: closed ? closedMessage : cancelledMessage,
  );
}

/// A `deadline-exceeded` exception with [message].
@internal
FirebaseFunctionsException deadlineError(String message) {
  return FirebaseFunctionsException(
    code: RpcStatus.deadlineExceeded.kebab,
    message: message,
  );
}

/// `<n> s` in whole seconds (rounded), or `<n> ms` below one second, for the deadline messages.
@internal
String describeDuration(Duration duration) {
  final int milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) {
    return '$milliseconds ms';
  }
  return '${(milliseconds / 1000).round()} s';
}

/// The exception a call reports for [error], a failure of the token wait or of a shared send, or
/// null when [error] is not one (a [StateError] of a deleted app, for example), which the caller
/// rethrows unchanged.
///
/// [closed] picks the message of a cancel; [deadlineMessage] is the message of a
/// [TimeoutException]. No exception of the transport is kept, not even as `cause`, and its
/// `causeType` and `detail` are not copied into the message.
@internal
FirebaseFunctionsException? exceptionOfFailure(
  Object error, {
  required bool closed,
  required String deadlineMessage,
}) {
  return switch (error) {
    FirebaseFunctionsException() => error,
    TimeoutException() => deadlineError(deadlineMessage),
    TransportException(failure: TransportFailure.cancelled) => cancelledError(
      closed: closed,
    ),
    TransportException() => _networkError(),
    CapExceededException() => internalError(tooLargeMessage),
    TokenFetchException() => _tokenError(error),
    _ => null,
  };
}

FirebaseFunctionsException _networkError() {
  const String message =
      'The request did not reach the server, or the connection broke.';
  const String web =
      ' On the web this is also how a response without CORS headers appears.';
  return FirebaseFunctionsException(
    code: RpcStatus.unavailable.kebab,
    message: isWeb ? '$message$web' : message,
  );
}

FirebaseFunctionsException _tokenError(TokenFetchException error) {
  final String message = switch (error.failure) {
    TokenFailure.authProviderFailed => _providerFailedMessage(error.causeType),
    TokenFailure.authTimedOut =>
      'The auth token provider did not answer within 10 s.',
    TokenFailure.authTokenTooLong =>
      'The ID token is longer than 8192 characters.',
    TokenFailure.destinationRefused => 'Tokens may not be sent to this URL.',
  };
  return FirebaseFunctionsException(
    code: rpcStatusOfFailure(error).kebab,
    message: message,
  );
}

String _providerFailedMessage(String? causeType) {
  const String base = 'Could not get the ID token of the signed-in user';
  return causeType == null ? '$base.' : '$base ($causeType).';
}
