import 'dart:async';

import 'package:_firebase_transport_dart/_firebase_transport_dart.dart';
import 'package:http/http.dart' as http;

/// The largest delay a timer takes on every compiler: 2^31 - 1 ms. A longer dart2js timer fires
/// at once.
const Duration maxTimeout = Duration(milliseconds: 2147483647);

/// [timeout] as a call uses it: any positive duration, clamped to [maxTimeout].
///
/// Throws an [ArgumentError] that names [parameter] when [timeout] is zero or negative.
Duration checkTimeout(Duration timeout, {String parameter = 'timeout'}) {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, parameter, 'must be positive');
  }
  return timeout > maxTimeout ? maxTimeout : timeout;
}

/// Why a call or a stream was stopped. The first reason recorded decides the error message.
enum AbortReason {
  /// The call's timeout ran out: during the token wait, the request or a silence of a stream.
  deadline,

  /// The caller's `abortTrigger` completed, or the subscription of a stream was cancelled.
  cancelled,

  /// `FirebaseFunctions.close()` was called, or the app was deleted.
  closed,
}

/// The state one call or one stream keeps while it is in flight: its abort signal, the reason it
/// was stopped for and its start time.
///
/// `FirebaseFunctions.startCall` creates it and keeps it until [settle], so that `close()` can
/// abort it and wait for it.
final class InFlightCall {
  /// A call that started at [startedAt] on the clock [elapsed]. [onSettled] runs once, at
  /// [settle].
  InFlightCall({
    required Duration Function() elapsed,
    required void Function(InFlightCall call) onSettled,
  }) : _elapsed = elapsed,
       _onSettled = onSettled,
       startedAt = elapsed();

  final Duration Function() _elapsed;
  final void Function(InFlightCall call) _onSettled;
  final Completer<void> _abort = Completer<void>();
  final Completer<void> _settled = Completer<void>();
  AbortReason? _reason;

  /// When the call started, on the instance's monotonic clock.
  final Duration startedAt;

  /// Completes, never with an error, when the call is stopped: pass it as `cancel:` to
  /// `sendCapped` and `sendStreaming`.
  Future<void> get aborted => _abort.future;

  /// Whether [abort] was called. Checked after the token wait: an aborted call sends nothing.
  bool get isAborted => _abort.isCompleted;

  /// The first reason recorded, or null while the call was never stopped.
  AbortReason? get reason => _reason;

  /// Completes when [settle] was called.
  Future<void> get settled => _settled.future;

  /// What is left of [timeout], counted from [startedAt]; zero or negative when it ran out.
  Duration timeLeft(Duration timeout) => timeout - (_elapsed() - startedAt);

  /// Stops the call for [reason]. The first reason wins; later calls change nothing.
  void abort(AbortReason reason) {
    _reason ??= reason;
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }

  /// Makes the completion of [trigger] stop the call with [AbortReason.cancelled].
  ///
  /// A value and an error are both handled, so an error the trigger completes with never becomes
  /// an unhandled one and never reaches the HTTP client.
  void watch(Future<void>? trigger) {
    if (trigger == null) {
      return;
    }
    void cancel() {
      if (!_settled.isCompleted) {
        abort(AbortReason.cancelled);
      }
    }

    trigger.then<void>((_) => cancel(), onError: (Object _) => cancel());
  }

  /// The call ended, with a result or an error; nothing of it is in flight any more. Idempotent.
  void settle() {
    if (_settled.isCompleted) {
      return;
    }
    _settled.complete();
    _onSettled(this);
  }
}

/// The request of one call to [url] (the request rules): `POST`, redirects not followed, the body
/// [body] as bytes, and these headers and no others: `Content-Type: application/json`,
/// `Authorization: Bearer <token>` and `X-Firebase-AppCheck: <token>` when [tokens] holds them,
/// and for [streaming] `Accept: text/event-stream`.
///
/// [abort] is the future the shared send helper hands to its `build` callback. [tokens] must come
/// from one `tokensFor` call for [url]; it works once, so each request needs its own.
///
/// Throws the [StateError] of `applyTokens` when [tokens] was fetched for another origin or was
/// used before.
http.AbortableRequest buildCallableRequest({
  required Uri url,
  required List<int> body,
  required RequestTokens tokens,
  required Future<void> abort,
  bool streaming = false,
}) {
  final http.AbortableRequest request =
      http.AbortableRequest('POST', url, abortTrigger: abort)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..bodyBytes = body;
  if (streaming) {
    request.headers['Accept'] = 'text/event-stream';
  }
  applyTokens(request, tokens, auth: AuthHeaderStyle.bearer);
  return request;
}
