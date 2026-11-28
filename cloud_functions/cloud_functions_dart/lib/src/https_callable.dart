import 'dart:async';
import 'dart:typed_data';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:cloud_functions_dart/src/exception.dart';
import 'package:cloud_functions_dart/src/firebase_functions.dart';
import 'package:cloud_functions_dart/src/request.dart';
import 'package:cloud_functions_dart/src/response.dart';
import 'package:cloud_functions_dart/src/serializer.dart';
import 'package:cloud_functions_dart/src/streaming.dart';
import 'package:meta/meta.dart';

/// The largest unary 2xx body read: 32 MiB.
const int _successCap = 32 * 1024 * 1024;

/// The largest non-2xx body read: 1 MiB.
const int _errorCap = 1024 * 1024;

/// The options of one callable.
final class HttpsCallableOptions {
  /// Options with [timeout] and [limitedUseAppCheckTokens].
  ///
  /// [timeout] null uses the timeout of the `FirebaseFunctions` instance. Any positive duration is
  /// accepted and clamped to 2147483647 ms; zero or negative is an [ArgumentError] when the
  /// callable is created.
  ///
  /// [limitedUseAppCheckTokens] sends a limited-use App Check token instead of the session token.
  /// It needs an App Check provider that implements `LimitedUseAppCheckTokenProvider`; with any
  /// other provider no App Check header is sent.
  const HttpsCallableOptions({
    this.timeout,
    this.limitedUseAppCheckTokens = false,
  });

  /// The timeout of each call, token wait included, or null for the instance's.
  final Duration? timeout;

  /// Whether each call sends a limited-use App Check token.
  final bool limitedUseAppCheckTokens;
}

/// A reference to one callable function, from [FirebaseFunctions.httpsCallable] or
/// [FirebaseFunctions.httpsCallableFromUrl].
///
/// It holds no connection: each [call] and each listen to a [stream] sends one request.
final class HttpsCallable {
  /// A callable at [url] of [functions]. Created by [FirebaseFunctions] only.
  ///
  /// [timeout] is the effective timeout, already checked and clamped; [originChosenByApplication]
  /// is true only for [FirebaseFunctions.httpsCallableFromUrl].
  @internal
  HttpsCallable.internal(
    FirebaseFunctions functions, {
    required this.url,
    required this.options,
    required this.timeout,
    required bool originChosenByApplication,
  }) : _functions = functions,
       _originChosenByApplication = originChosenByApplication;

  final FirebaseFunctions _functions;
  final bool _originChosenByApplication;

  /// The URL the call goes to.
  final Uri url;

  /// The options this callable was created with.
  final HttpsCallableOptions options;

  /// The effective timeout: `options.timeout`, or the instance's timeout, clamped to 2147483647 ms.
  final Duration timeout;

  /// Calls the function with [data] and returns its result.
  ///
  /// [data] is encoded synchronously: a value that is not JSON (null, bool, finite num, String,
  /// List, Map with String keys, at most 512 levels deep) throws an [ArgumentError] at once. A
  /// [StateError] is thrown at once after [FirebaseFunctions.close].
  ///
  /// When [abortTrigger] completes, with a value or an error, the request is aborted and the
  /// future fails with a [FirebaseFunctionsException] whose code is `cancelled`; completing it
  /// after the call ended has no effect.
  ///
  /// Fails with a [FirebaseFunctionsException] for an error the function threw, a network
  /// failure, the timeout (which covers the token wait) and an invalid response. The function may
  /// still run to its end on the server after a timeout or a cancel.
  Future<HttpsCallableResult> call([Object? data, Future<void>? abortTrigger]) {
    final CallRequest request = _request(data);
    final InFlightCall call = _functions.startCall(abortTrigger);
    return request.send(call);
  }

  /// Calls a streaming function with [data]; emits each chunk as a [CallableMessage] and the
  /// return value as the last event, a [CallableResult].
  ///
  /// [data] is encoded synchronously, as in [call], and the same [StateError] is thrown at once
  /// after [FirebaseFunctions.close]. The stream is single-subscription and the request is sent
  /// when it is listened to. Cancelling the subscription, or completing [abortTrigger], aborts the
  /// request; after a cancel nothing is emitted, after the trigger a `cancelled` error. If
  /// [abortTrigger] completed before the listen, listening emits `cancelled` and sends nothing.
  ///
  /// [timeout] bounds the wait for the response headers (token wait included) and each silence in
  /// the body, not the stream's total time: keep it above the function's `heartbeatSeconds`.
  /// Errors are [FirebaseFunctionsException]s, each followed by done.
  Stream<CallableStreamEvent> stream([
    Object? data,
    Future<void>? abortTrigger,
  ]) {
    return CallableStream(_request(data), abortTrigger).stream;
  }

  /// The closed check comes before the encoding (§5.2).
  CallRequest _request(Object? data) {
    if (_functions.isClosed) {
      throw StateError(closedMessage);
    }
    return CallRequest(
      functions: _functions,
      url: url,
      body: encodeRequestBody(data),
      timeout: timeout,
      limitedUseAppCheckTokens: options.limitedUseAppCheckTokens,
      originChosenByApplication: _originChosenByApplication,
    );
  }
}

/// The result of [HttpsCallable.call].
final class HttpsCallableResult {
  /// A result holding [data].
  const HttpsCallableResult(this.data);

  /// The decoded value: null, bool, int, double, String, `List<Object?>` or
  /// `Map<String, Object?>`. Numbers keep the type the JSON gave them; read them as `num`.
  final Object? data;
}

/// An event of [HttpsCallable.stream].
sealed class CallableStreamEvent {
  /// Subclasses only.
  const CallableStreamEvent();
}

/// A chunk the function sent with `sendChunk`.
final class CallableMessage extends CallableStreamEvent {
  /// A chunk holding [data].
  const CallableMessage(this.data);

  /// The decoded chunk, typed as [HttpsCallableResult.data].
  final Object? data;
}

/// The function's return value; always the last event.
final class CallableResult extends CallableStreamEvent {
  /// A result holding [data].
  const CallableResult(this.data);

  /// The decoded value, typed as [HttpsCallableResult.data].
  final Object? data;
}

/// One encoded call of a callable: what a unary call and a stream share.
@internal
final class CallRequest {
  /// The call of [url] through [functions] with the encoded [body].
  const CallRequest({
    required this.functions,
    required this.url,
    required this.body,
    required this.timeout,
    required this.limitedUseAppCheckTokens,
    required this.originChosenByApplication,
  });

  /// The instance the call belongs to.
  final FirebaseFunctions functions;

  /// The URL called.
  final Uri url;

  /// The UTF-8 bytes of `{"data": ...}`.
  final Uint8List body;

  /// The effective timeout.
  final Duration timeout;

  /// Whether a limited-use App Check token is asked for.
  final bool limitedUseAppCheckTokens;

  /// True only for `httpsCallableFromUrl`.
  final bool originChosenByApplication;

  /// "The call did not finish within `<t>`.": the unary deadline and the token wait.
  String get callDeadlineMessage =>
      'The call did not finish within ${describeDuration(timeout)}.';

  /// The tokens of the one request of [call], fetched within its time left (§5.9 token phase).
  ///
  /// Throws what [FirebaseFunctions.tokensFor] throws: a cancelled [TransportException] when
  /// [call] was aborted (nothing may be sent then), a [TimeoutException], a
  /// [TokenFetchException] or a [StateError].
  Future<RequestTokens> tokensFor(InFlightCall call) {
    return functions.tokensFor(
      call,
      url,
      timeout: timeout,
      limitedUseAppCheck: limitedUseAppCheckTokens,
      originChosenByApplication: originChosenByApplication,
    );
  }

  /// What is left of [timeout] for [call]; throws [TimeoutException] when nothing is left.
  Duration timeLeft(InFlightCall call) {
    final Duration left = call.timeLeft(timeout);
    if (left <= Duration.zero) {
      throw TimeoutException('The call ran out of time.', timeout);
    }
    return left;
  }

  /// After a bare transport 401 the next call forces an Auth refresh when this request carried an
  /// Auth token (§5.4 rule 6). Never for a callable envelope or an error frame.
  void afterResponse(CappedResponse response, RequestTokens tokens) {
    if (isBareUnauthorized(
      response.statusCode,
      response.body,
      truncated: response.truncated,
    )) {
      functions.bareUnauthorized(tokens);
    }
  }

  /// The [HttpsCallable.call] flow: tokens, one capped send, the unary response rules (§5.7).
  /// Settles [call] whatever the outcome.
  Future<HttpsCallableResult> send(InFlightCall call) async {
    try {
      final RequestTokens tokens = await tokensFor(call);
      final CappedResponse response = await sendCapped(
        functions.httpClient,
        (Future<void> abort) => buildCallableRequest(
          url: url,
          body: body,
          tokens: tokens,
          abort: abort,
        ),
        successCap: _successCap,
        errorCap: _errorCap,
        deadline: timeLeft(call),
        cancel: call.aborted,
      );
      afterResponse(response, tokens);
      return HttpsCallableResult(
        valueOfResponse(
          response.statusCode,
          response.body,
          truncated: response.truncated,
        ),
      );
    } on Object catch (error) {
      if (error is TimeoutException) {
        call.abort(AbortReason.deadline);
      }
      final FirebaseFunctionsException? mapped = exceptionOfFailure(
        error,
        closed: call.reason == AbortReason.closed,
        deadlineMessage: callDeadlineMessage,
      );
      if (mapped == null) {
        rethrow;
      }
      throw mapped;
    } finally {
      call.settle();
    }
  }
}
