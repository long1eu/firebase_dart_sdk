import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:firebase_ai_dart/src/errors.dart';
import 'package:firebase_ai_dart/src/exception.dart';
import 'package:firebase_ai_dart/src/headers.dart';
import 'package:http/http.dart' as http;

/// The cap on a `generateContent` success body: 64 MiB.
const int maxGenerateBodyBytes = 64 * 1024 * 1024;

/// The cap on a `countTokens` success body: 1 MiB.
const int maxCountTokensBodyBytes = 1024 * 1024;

/// The cap on any error body: 64 KiB. A longer one is cut, and the status's code is kept.
const int maxErrorBodyBytes = 64 * 1024;

/// What every request of one `FirebaseAI` shares: the HTTP client, the headers and the closed
/// flag.
final class AiRequestContext {
  /// The context of requests sent with [client] and [headers].
  ///
  /// [client] must abort `http.Abortable` requests, must not retry and must not follow redirects.
  AiRequestContext({required this.client, required this.headers});

  /// The client every request is sent with. [close] does not close it: its owner does.
  final http.Client client;

  /// The headers and tokens of every request.
  final AiHeaders headers;

  final Set<AiCall> _calls = <AiCall>{};
  bool _closed = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Starts one call: its deadline of [timeout] counts from now, also while the call waits for
  /// something else (a chat send in its queue, a stream that is not listened to yet).
  ///
  /// When [abortTrigger] completes, with a value or an error, the call fails with `cancelled`;
  /// its error is not rethrown. A call started after [close] has already ended with `ai-closed`.
  /// A call that is never sent ends at its deadline, or earlier with [AiCall.dispose].
  ///
  /// Throws an [ArgumentError] when [timeout] is negative.
  AiCall startCall({required Duration timeout, Future<void>? abortTrigger}) {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
    return AiCall._(this, timeout, abortTrigger);
  }

  /// Ends every call in flight with `ai-closed` and makes every later call end the same way.
  /// Idempotent. The closed flag is set before any call is told, so each reports `ai-closed`.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final AiCall call in _calls.toList()) {
      call.end(CallEnd.closed);
    }
  }
}

/// What ended a call before its answer was complete.
enum CallEnd {
  /// `FirebaseAI.close()`: reported as `ai-closed`.
  closed,

  /// The call's `abortTrigger`: reported as `cancelled`.
  aborted,

  /// The call's deadline: reported as `deadline-exceeded`.
  deadline,

  /// The stream's event timer, when no event arrived within the idle timeout: reported as
  /// `deadline-exceeded`.
  eventTimer,

  /// The stream stopped reading by itself: its listener cancelled, or it failed on what it
  /// read. Nothing is reported for it.
  stopped,
}

/// The deadline, the abort trigger and the closed flag of one call.
///
/// The first of them to happen is recorded and completes [whenEnded], which is the `cancel` future
/// of the shared send helpers. So the failure a helper then reports (`cancelled`) is read as what
/// was recorded: the first to happen decides the error.
final class AiCall {
  AiCall._(this._context, this._timeout, Future<void>? abortTrigger) {
    if (_context._closed) {
      _end = CallEnd.closed;
      _ended.complete();
      return;
    }
    _context._calls.add(this);
    _deadline = Timer(_timeout, () => end(CallEnd.deadline));
    if (abortTrigger != null) {
      _watch(abortTrigger);
    }
  }

  final AiRequestContext _context;
  final Duration _timeout;
  final Stopwatch _elapsed = Stopwatch()..start();
  final Completer<void> _ended = Completer<void>();
  Timer? _deadline;
  _AbortHook? _abortHook;
  CallEnd? _end;
  bool _disposed = false;

  /// Completes, never with an error, when the call ended early: its deadline passed, its abort
  /// trigger completed, the instance was closed, or a stream stopped reading. It does not
  /// complete for a call that finished or was disposed first.
  Future<void> get whenEnded => _ended.future;

  /// The exception of a call that ended early: `deadline-exceeded`, `cancelled` or `ai-closed`.
  /// Null while the call has not ended early, and for a stream that stopped reading by itself.
  FirebaseAIException? get endError {
    return switch (_end) {
      null || CallEnd.stopped => null,
      CallEnd.closed => closedError(),
      CallEnd.aborted => _cancelledBy(CancelSource.abortTrigger),
      CallEnd.eventTimer => _cancelledBy(CancelSource.eventTimer),
      CallEnd.deadline => errorFromFailure(
        TimeoutException('The call took longer than its deadline', _timeout),
      ),
    };
  }

  /// What the call throws once it has ended early; for [CallEnd.stopped] a `cancelled` that
  /// nobody sees.
  FirebaseAIException get _failure =>
      endError ?? _cancelledBy(CancelSource.abortTrigger);

  /// Throws [endError] when the call has ended early.
  void throwIfEnded() {
    if (_end != null) {
      throw _failure;
    }
  }

  /// What remains of the deadline, for the shared helpers. Always positive.
  ///
  /// Throws the exception of the early end when the call has ended, or when nothing remains (the
  /// call then ends with [CallEnd.deadline]).
  Duration takeTimeLeft() {
    throwIfEnded();
    final Duration left = _timeout - _elapsed.elapsed;
    if (left > Duration.zero) {
      return left;
    }
    end(CallEnd.deadline);
    throw _failure;
  }

  /// Ends the call early for [reason], unless it has ended or was disposed.
  void end(CallEnd reason) {
    if (_end != null || _disposed) {
      return;
    }
    _end = reason;
    _release();
    _ended.complete();
  }

  /// Stops the deadline: a stream's deadline lasts until its response headers arrive. The abort
  /// trigger and the closed flag still end the call.
  void stopDeadline() {
    _deadline?.cancel();
  }

  /// Releases the call when it finished, or when it will never be sent. Idempotent.
  void dispose() {
    _disposed = true;
    _release();
  }

  void _release() {
    _deadline?.cancel();
    _abortHook?.call = null;
    _context._calls.remove(this);
  }

  /// The closures given to [trigger] hold the hook, not the call, so a trigger that outlives the
  /// call keeps nothing of it.
  void _watch(Future<void> trigger) {
    final _AbortHook hook = _abortHook = _AbortHook(this);
    unawaited(
      trigger.then<void>(
        (_) => hook.fire(),
        onError: (Object _, StackTrace _) => hook.fire(),
      ),
    );
  }

  static FirebaseAIException _cancelledBy(CancelSource source) {
    return errorFromFailure(
      const TransportException(TransportFailure.cancelled),
      cancelledBy: source,
    );
  }
}

/// The listener on a caller's abort trigger.
final class _AbortHook {
  _AbortHook(this.call);

  AiCall? call;

  void fire() {
    final AiCall? call = this.call;
    this.call = null;
    call?.end(CallEnd.aborted);
  }
}

/// Sends one unary request and returns the top-level JSON object of its success body.
///
/// [call] was started when the caller's method was called; its deadline covers the token wait,
/// the headers and the whole body. [body] is sent as JSON to [url] with POST. A success body is
/// read up to [successCap] bytes and decoded with the depth guard; an error body is cut at
/// [maxErrorBodyBytes]. Nothing is sent again, also not after a 401.
///
/// Throws a `FirebaseAIException`:
/// - the one [errorFromResponse] builds with [errorContext] for any non-2xx answer;
/// - `ai-closed`, `cancelled` or `deadline-exceeded` when [call] ended early, whichever happened
///   first;
/// - `unauthenticated`, `unavailable` or `failed-precondition` when the Auth token could not be
///   had, and `unavailable` for a transport failure or a redirect;
/// - `response-too-large` past [successCap], and `parse-failed` for a body that is not a JSON
///   object.
///
/// Throws a [StateError] when the app's options hold no API key, or no app id while data
/// collection is on.
Future<Map<String, Object?>> sendUnary(
  AiRequestContext context,
  AiCall call, {
  required Uri url,
  required Map<String, Object?> body,
  required int successCap,
  required ErrorContext errorContext,
}) async {
  try {
    final Uint8List bytes = encodeBody(body);
    final RequestTokens tokens = await fetchTokens(context, call, url);
    final CappedResponse response = await sendCapped(
      context.client,
      (Future<void> abort) => postRequest(context, url, bytes, tokens, abort),
      successCap: successCap,
      errorCap: maxErrorBodyBytes,
      deadline: call.takeTimeLeft(),
      cancel: call.whenEnded,
    );
    context.headers.afterAnswer(response.statusCode, tokens);
    if (!response.isSuccess) {
      throw errorFromResponse(
        response,
        errorContext,
        appCheckOutcome: tokens.appCheck.name,
      );
    }
    return _decodeObject(response.body);
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(failureOf(context, call, error), stackTrace);
  } finally {
    call.dispose();
  }
}

/// [body] as the UTF-8 bytes of its JSON text.
Uint8List encodeBody(Map<String, Object?> body) =>
    utf8.encode(jsonEncode(body));

/// The tokens of one attempt of [call] to [url], fetched within what remains of its deadline.
///
/// The wait also ends when [call] ends early; the tokens that arrive later are dropped. After the
/// tokens arrived, the early end is checked once more, so nothing is sent for a call that was
/// aborted or closed meanwhile.
///
/// Throws the exception of the early end, and what `AiHeaders.tokensFor` throws.
Future<RequestTokens> fetchTokens(
  AiRequestContext context,
  AiCall call,
  Uri url,
) async {
  final Future<RequestTokens> fetch = context.headers.tokensFor(
    url,
    timeLeft: call.takeTimeLeft(),
  );
  final RequestTokens? tokens = await Future.any<RequestTokens?>(
    <Future<RequestTokens?>>[
      fetch,
      call.whenEnded.then<RequestTokens?>((_) => null),
    ],
  );
  call.throwIfEnded();
  if (tokens == null) {
    throw call._failure;
  }
  return tokens;
}

/// The POST request of [body] to [url], aborted by [abort], with every header set.
///
/// It is the `build` argument of the shared send helpers. [tokens] are used up by it.
http.BaseRequest postRequest(
  AiRequestContext context,
  Uri url,
  Uint8List body,
  RequestTokens tokens,
  Future<void> abort,
) {
  final http.AbortableRequest request = http.AbortableRequest(
    'POST',
    url,
    abortTrigger: abort,
  )..bodyBytes = body;
  context.headers.apply(request, tokens);
  return request;
}

/// What [call] throws for [error], a failure of the token step or of a shared send helper.
///
/// - A `FirebaseAIException` is returned as it is.
/// - Once [call] ended early, the recorded end decides: the helper's `cancelled` is its echo.
/// - A [StateError] is `ai-closed` when the app was deleted (its getters throw in the window
///   before the instance closes itself); any other one is returned as it is.
/// - The failures of the shared helpers go through [errorFromFailure]. Nothing of a client's
///   exception is kept.
/// - Anything else is returned as it is.
Object failureOf(AiRequestContext context, AiCall call, Object error) {
  if (error is FirebaseAIException) {
    return error;
  }
  if (call._end != null) {
    return call._failure;
  }
  if (error is StateError) {
    return context.headers.isAppDeleted ? closedError() : error;
  }
  if (error is TokenFetchException ||
      error is TimeoutException ||
      error is TransportException ||
      error is CapExceededException) {
    return errorFromFailure(error);
  }
  return error;
}

Map<String, Object?> _decodeObject(Uint8List body) {
  final Object? decoded;
  try {
    decoded = decodeGuardedBytes(body, maxDepth: maxAiJsonDepth);
  } on FormatException catch (error) {
    throw errorFromFailure(error);
  }
  if (decoded is! Map<String, Object?>) {
    throw notAnObjectError();
  }
  return decoded;
}
