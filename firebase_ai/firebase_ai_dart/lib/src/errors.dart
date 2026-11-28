import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/exception.dart';

/// The deepest JSON nesting accepted in any body: function arguments and structured output nest
/// deeper than the shared default of 32.
const int maxAiJsonDepth = 128;

/// What completed the `cancel` future of a send.
///
/// The request layer records it before it completes `cancel`, and passes it to
/// [errorFromFailure] with the `TransportException(cancelled)` that follows.
enum CancelSource {
  /// `FirebaseAI.close()`: reported as `ai-closed`.
  close,

  /// The call's `abortTrigger`: reported as `cancelled`.
  abortTrigger,

  /// The stream's event timer: no SSE event within `streamIdleTimeout`, reported as
  /// `deadline-exceeded`.
  eventTimer,
}

/// What the error mapping needs to know about the call that failed.
final class ErrorContext {
  /// The context of a call to [projectId] (null when the app has none) on Agent Platform when
  /// [isAgentPlatform] is true, else on the Gemini Developer API.
  const ErrorContext({required this.projectId, required this.isAgentPlatform});

  /// The project the call went to; named in the `api-not-enabled` message.
  final String? projectId;

  /// True for Agent Platform, whose 404 with a non-JSON body gets a hint about the location.
  final bool isAgentPlatform;
}

const String _errorInfoType = 'type.googleapis.com/google.rpc.ErrorInfo';
const String _retryInfoType = 'type.googleapis.com/google.rpc.RetryInfo';
const String _aiService = 'firebasevertexai.googleapis.com';
const Duration _maxRetryAfter = Duration(hours: 24);
final RegExp _retryDelay = RegExp(r'^([0-9]{1,6})(?:\.([0-9]{1,9}))?s$');
final RegExp _retryAfterHeader = RegExp(r'^[0-9]{1,6}$');

/// The exception for a non-2xx answer whose body was read with the 64 KiB error cap.
///
/// The code is `api-not-enabled` for a 403 that names the AI Logic service as disabled; otherwise
/// the envelope's `error.status` when it is a known name, else the HTTP status through the default
/// table. A body that was cut, or is not a JSON error envelope, keeps the status's code; the fields
/// read from the envelope are then null. [appCheckOutcome] (the name of the attempt's
/// `AppCheckOutcome`) is named in the message of a 401 or 403.
FirebaseAIException errorFromResponse(
  CappedResponse response,
  ErrorContext context, {
  String? appCheckOutcome,
}) {
  final Object? decoded = _decodeOrNull(response.body);
  final _Envelope? envelope = _Envelope.of(decoded);
  final int status = response.statusCode;
  final bool apiNotEnabled = status == 403 && _namesAiServiceDisabled(envelope);
  final String code = apiNotEnabled
      ? 'api-not-enabled'
      : _codeOf(envelope?.body.status, status);
  final List<String> notes = <String>[
    if (apiNotEnabled) _enableHint(context.projectId),
    if (context.isAgentPlatform && status == 404 && decoded == null)
      'The body is not JSON; check the location.',
    if (appCheckOutcome != null && (status == 401 || status == 403))
      'App Check: $appCheckOutcome.',
    if (response.truncated) 'The error body was cut at 64 KiB.',
  ];
  return FirebaseAIException(
    code: code,
    message: _serverAnswerMessage(status, envelope, notes),
    httpStatus: status,
    serverStatus: envelope?.serverStatus,
    serverMessage: envelope?.body.message,
    reason: envelope?.reason,
    retryAfter:
        envelope?.retryInfoDelay ?? _retryAfterOfHeader(response.headers),
  );
}

/// The exception for an SSE event whose JSON object has a top-level `error` key.
///
/// `error.code` is the status when it is an integer from 100 to 599; the code follows the rules of
/// [errorFromResponse], and is `unknown` when neither the status name nor the number gives one.
FirebaseAIException errorFromEvent(
  Map<String, Object?> event,
  ErrorContext context,
) {
  final _Envelope? envelope = _Envelope.of(event);
  final int? status = envelope?.body.httpCode;
  final bool apiNotEnabled = status == 403 && _namesAiServiceDisabled(envelope);
  final String code = apiNotEnabled
      ? 'api-not-enabled'
      : _codeOf(envelope?.body.status, status);
  return FirebaseAIException(
    code: code,
    message: _serverAnswerMessage(status, envelope, <String>[
      'The stream carried an error event.',
      if (apiNotEnabled) _enableHint(context.projectId),
    ]),
    httpStatus: status,
    serverStatus: envelope?.serverStatus,
    serverMessage: envelope?.body.message,
    reason: envelope?.reason,
    retryAfter: envelope?.retryInfoDelay,
  );
}

/// The exception for a failure in the client: nothing usable came from the server.
///
/// Handles the failures the shared send helpers and decoders let through:
/// - `TokenFetchException`: `unauthenticated`, `unavailable` or `failed-precondition`, the message
///   naming the failure and its `causeType`;
/// - `TimeoutException`: `deadline-exceeded`;
/// - `TransportException`: `cancelled` failures by [cancelledBy] (`ai-closed`, `cancelled`, or
///   `deadline-exceeded` for the event timer; `cancelled` when null), `network` and `redirected`
///   as `unavailable`;
/// - `CapExceededException`, `SseEventTooLarge` and `SseStreamTooLarge`: `response-too-large`;
/// - `FormatException` (from the guarded decoders) and `SseMalformed`: `parse-failed`.
///
/// A [FirebaseAIException] is returned as it is. Anything else is `unknown`, named by its runtime
/// type. The message never holds the failure's own text, which can quote a body or a URL, and
/// `cause` is null.
FirebaseAIException errorFromFailure(
  Object error, {
  CancelSource? cancelledBy,
}) {
  if (error is FirebaseAIException) {
    return error;
  }
  final (String code, String message) = switch (error) {
    TokenFetchException() => _ofTokenFailure(error),
    TimeoutException() => (
      'deadline-exceeded',
      'The call took longer than its deadline.',
    ),
    TransportException() => _ofTransportFailure(error, cancelledBy),
    CapExceededException(:final int cap) => (
      'response-too-large',
      'The response body is longer than its cap of $cap bytes.',
    ),
    SseEventTooLarge() => (
      'response-too-large',
      'A stream event is longer than its cap of 64 MiB.',
    ),
    SseStreamTooLarge() => (
      'response-too-large',
      'The stream is longer than its cap of 256 MiB.',
    ),
    SseMalformed() => (
      'parse-failed',
      'The stream ended inside an event or is not valid UTF-8.',
    ),
    FormatException() => (
      'parse-failed',
      'The response is not a JSON object within $maxAiJsonDepth levels of nesting, '
          'or is not valid UTF-8.',
    ),
    _ => ('unknown', 'The call failed with ${error.runtimeType}.'),
  };
  return FirebaseAIException(code: code, message: message);
}

/// The exception for a success body or SSE event that decoded to something other than a JSON
/// object.
FirebaseAIException notAnObjectError() => const FirebaseAIException(
  code: 'parse-failed',
  message: 'The response is not a JSON object.',
);

/// The exception for a call on a closed `FirebaseAI`, its models and its chats, and for a request
/// that `close()` aborted.
FirebaseAIException closedError() => aiClosedException();

(String, String) _ofTokenFailure(TokenFetchException error) {
  final String code = rpcStatusOfFailure(error).kebab;
  final String type = error.causeType == null ? '' : ' (${error.causeType})';
  final String message = switch (error.failure) {
    TokenFailure.authProviderFailed =>
      'The Auth provider failed or gave a token that is not token text$type; nothing was sent.',
    TokenFailure.authTimedOut =>
      'The Auth provider did not answer within 10 s; nothing was sent.',
    TokenFailure.authTokenTooLong =>
      'The Auth token is longer than 8192 characters; nothing was sent.',
    TokenFailure.destinationRefused =>
      'Tokens may not be sent to this destination; nothing was sent.',
  };
  return (code, message);
}

(String, String) _ofTransportFailure(
  TransportException error,
  CancelSource? cancelledBy,
) {
  final String type = error.causeType == null ? '' : ' (${error.causeType})';
  return switch (error.failure) {
    TransportFailure.cancelled => switch (cancelledBy) {
      CancelSource.close => ('ai-closed', aiClosedException().message!),
      CancelSource.eventTimer => (
        'deadline-exceeded',
        'No stream event arrived within streamIdleTimeout.',
      ),
      CancelSource.abortTrigger ||
      null => ('cancelled', 'The call was aborted by its abortTrigger.'),
    },
    TransportFailure.network => ('unavailable', 'A network failure$type.'),
    TransportFailure.redirected => (
      'unavailable',
      'The server answered with a redirect, which is never followed.',
    ),
  };
}

String _codeOf(RpcStatus? status, int? httpStatus) {
  if (status != null && status != RpcStatus.ok) {
    return status.kebab;
  }
  if (httpStatus == null) {
    return RpcStatus.unknown.kebab;
  }
  final RpcStatus byHttp = RpcStatus.fromHttpStatus(httpStatus);
  return byHttp == RpcStatus.ok ? RpcStatus.unknown.kebab : byHttp.kebab;
}

String _enableHint(String? projectId) {
  final String project = projectId ?? '<project id>';
  return 'Firebase AI Logic is not enabled for this project; enable it at '
      'https://console.firebase.google.com/project/$project/ailogic/.';
}

String _serverAnswerMessage(
  int? status,
  _Envelope? envelope,
  List<String> notes,
) {
  final RpcStatus? named = envelope?.body.status;
  final String wire = named == null ? '' : ' ${_wireNameOf(named)}';
  final String head = status == null
      ? 'The server answered with an error$wire.'
      : 'The server answered $status$wire.';
  return <String>[head, ...notes].join(' ');
}

String _wireNameOf(RpcStatus status) =>
    status.kebab.replaceAll('-', '_').toUpperCase();

Object? _decodeOrNull(List<int> body) {
  try {
    return decodeGuardedBytes(body, maxDepth: maxAiJsonDepth);
  } on FormatException {
    return null;
  }
}

bool _namesAiServiceDisabled(_Envelope? envelope) {
  if (envelope == null) {
    return false;
  }
  for (final Map<String, Object?> detail in envelope.details) {
    if (detail['@type'] != _errorInfoType ||
        detail['reason'] != 'SERVICE_DISABLED' ||
        detail['domain'] != 'googleapis.com') {
      continue;
    }
    final Object? metadata = detail['metadata'];
    if (metadata is Map<String, Object?> && metadata['service'] == _aiService) {
      return true;
    }
  }
  return false;
}

Duration? _retryAfterOfHeader(Map<String, String> headers) {
  final String? value = headers['retry-after'];
  if (value == null || !_retryAfterHeader.hasMatch(value)) {
    return null;
  }
  return _clamped(Duration(seconds: int.parse(value)));
}

Duration _clamped(Duration value) =>
    value > _maxRetryAfter ? _maxRetryAfter : value;

/// The parts of an error envelope this client reads, each validated.
final class _Envelope {
  _Envelope._(this.body, this.serverStatus, this.details);

  static _Envelope? of(Object? decoded) {
    final RpcErrorBody? body = rpcErrorBodyOf(decoded);
    if (body == null) {
      return null;
    }
    final Object? error = (decoded is List<Object?> ? decoded.first : decoded);
    final Object? rawError = error is Map<String, Object?>
        ? error['error']
        : null;
    final Object? status = rawError is Map<String, Object?>
        ? rawError['status']
        : null;
    final Object? details = body.details;
    return _Envelope._(
      body,
      status is String ? sanitizeServerText(status) : null,
      <Map<String, Object?>>[
        if (details is List<Object?>)
          for (final Object? detail in details)
            if (detail is Map<String, Object?>) detail,
      ],
    );
  }

  final RpcErrorBody body;

  /// `error.status` as sent, sanitized; also an unknown name.
  final String? serverStatus;

  /// The details that are JSON objects, in order.
  final List<Map<String, Object?>> details;

  /// The `reason` of the first ErrorInfo detail, sanitized.
  String? get reason {
    for (final Map<String, Object?> detail in details) {
      if (detail['@type'] == _errorInfoType) {
        final Object? reason = detail['reason'];
        return reason is String ? sanitizeServerText(reason) : null;
      }
    }
    return null;
  }

  /// The `retryDelay` of the first RetryInfo detail, when it is a valid duration.
  Duration? get retryInfoDelay {
    for (final Map<String, Object?> detail in details) {
      if (detail['@type'] == _retryInfoType) {
        final Object? delay = detail['retryDelay'];
        return delay is String ? _parseRetryDelay(delay) : null;
      }
    }
    return null;
  }

  static Duration? _parseRetryDelay(String text) {
    final RegExpMatch? match = _retryDelay.firstMatch(text);
    if (match == null) {
      return null;
    }
    final int seconds = int.parse(match.group(1)!);
    final String fraction = (match.group(2) ?? '')
        .padRight(6, '0')
        .substring(0, 6);
    return _clamped(
      Duration(seconds: seconds, microseconds: int.parse(fraction)),
    );
  }
}
