// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:async' hide Stream;

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/datastore.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/async_queue.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/exponential_backoff.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/firestore_channel.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/incoming_stream_observer.dart';
import 'package:grpc/grpc.dart';
import 'package:meta/meta.dart';
import 'package:protobuf/protobuf.dart';

/// An [AbstractStream] is an abstract base class that implements the [Stream] interface.
///
/// [ReqT] The proto type that will be sent in this stream
/// [RespT] The proto type that is received through this stream
/// [CallbackT] The type which is used for stream specific callbacks.
abstract class AbstractStream<ReqT extends GeneratedMessage, RespT extends GeneratedMessage,
    CallbackT extends StreamCallback> implements Stream<CallbackT> {
  AbstractStream(
    this._firestoreChannel,
    this._methodDescriptor,
    this._workerQueue,
    TimerId connectionTimerId,
    this._idleTimerId,
    this.listener,
  ) : backoff = ExponentialBackoff(
          _workerQueue,
          connectionTimerId,
          _backoffInitialDelayMs,
          _backoffFactor,
          _backoffMaxDelayMs,
        );

  /// Initial backoff time in milliseconds after an error. Set to 1s according to
  /// https://cloud.google.com/apis/design/errors.
  static const int _backoffInitialDelayMs = 1000;
  static const int _backoffMaxDelayMs = 60 * 1000;

  static const double _backoffFactor = 1.5;

  /// The time a stream stays open after it is marked idle.
  static const int _idleTimeoutMs = 60 * 1000;

  DelayedTask<void> _idleTimer;

  final FirestoreChannel _firestoreChannel;

  final ClientMethod<ReqT, RespT> _methodDescriptor;

  final AsyncQueue _workerQueue;

  final TimerId _idleTimerId;

  StreamState _state = StreamState.initial;

  /// A close count that's incremented every time the stream is closed; used by [CloseGuardedRunner]
  /// to invalidate callbacks that happen after close.
  int _closeCount = 0;

  BidiChannel<ReqT, RespT> _call;
  final ExponentialBackoff backoff;
  final CallbackT listener;

  @override
  bool get isStarted {
    return _state == StreamState.starting ||
        _state == StreamState.open ||
        _state == StreamState.backoff;
  }

  @override
  bool get isOpen {
    return _state == StreamState.open;
  }

  @override
  Future<void> start() async {
    hardAssert(_call == null, 'Last call still set');
    hardAssert(_idleTimer == null, 'Idle timer still set');

    if (_state == StreamState.error) {
      _performBackoff();
      return;
    }

    hardAssert(_state == StreamState.initial, 'Already started');

    final CloseGuardedRunner closeGuardedRunner =
        CloseGuardedRunner(_workerQueue, _closeCount, () => _closeCount);
    final StreamObserver<ReqT, RespT, CallbackT> streamObserver =
        StreamObserver<ReqT, RespT, CallbackT>(closeGuardedRunner, this);

    _call = _firestoreChannel.runBidiStreamingRpc(_methodDescriptor, streamObserver);

    // Note that Starting is only used as intermediate state until onOpen is called asynchronously,
    // since auth handled transparently by gRPC
    _state = StreamState.starting;
    _state = StreamState.open;

    await listener.onOpen();
  }

  /// Closes the stream and cleans up as necessary:
  ///   * closes the underlying GRPC stream;
  ///   * calls the [onClose] handler with the given [status];
  ///   * sets internal stream state to [finalState];
  ///   * adjusts the backoff timer based on status
  ///
  /// A new stream can be opened by calling [start].
  Future<void> _close(StreamState finalState, GrpcError status) async {
    hardAssert(isStarted, 'Only started streams should be closed.');
    hardAssert(finalState == StreamState.error || status.code == StatusCode.ok,
        'Can\'t provide an error when not in an error state.');

    // Cancel any outstanding timers (they're guaranteed not to execute).
    _cancelIdleCheck();
    backoff.cancel();

    // Invalidates any stream-related callbacks (e.g. from auth or the underlying stream),
    // guaranteeing they won't execute.
    _closeCount++;

    final int code = status.code;
    if (code == StatusCode.ok) {
      // If this is an intentional close ensure we don't delay our next connection attempt.
      backoff.reset();
    } else if (code == StatusCode.resourceExhausted) {
      Log.d(runtimeType.toString(),
          '($hashCode) Using maximum backoff delay to prevent overloading the backend.');
      backoff.resetToMax();
    } else if (code == StatusCode.unauthenticated) {
      // 'unauthenticated' error means the token was rejected. Try force refreshing it in case it
      // just expired.
      _firestoreChannel.invalidateToken();
    }

    if (finalState != StreamState.error) {
      Log.d(runtimeType.toString(), '($hashCode) Performing stream teardown');
      tearDown();
    }

    if (_call != null) {
      // Clean up the underlying RPC. If this [close()] is in response to an error, don't attempt to
      // call half-close to avoid secondary failures.
      if (status.code == StatusCode.ok) {
        Log.d(runtimeType.toString(), '($hashCode) Closing stream client-side');
        _call.cancel();
      }
      _call = null;
    }

    // This state must be assigned before calling listener.onClose to allow the callback to inhibit
    // backoff or otherwise manipulate the state in its non-started state.
    _state = finalState;

    // Notify the listener that the stream closed.
    await listener.onClose(status);
  }

  /// Can be overridden to perform additional cleanup before the stream is closed.
  void tearDown() {}

  Future<void> stop() async {
    if (isStarted) {
      await _close(StreamState.initial, GrpcError.ok());
    }
  }

  void inhibitBackoff() {
    hardAssert(!isStarted, 'Can only inhibit backoff after in a stopped state');

    _state = StreamState.initial;
    backoff.reset();
  }

  void writeRequest(ReqT message) {
    Log.d(runtimeType.toString(), '($hashCode) Stream sending: ${message.writeToJsonMap()}');
    _cancelIdleCheck();
    _call.add(message);
  }

  /// Called by the idle timer when the stream should close due to inactivity.
  Future<void> _handleIdleCloseTimer() async {
    if (isOpen) {
      // When timing out an idle stream there's no reason to force the stream into backoff when it
      // restarts so set the stream state to Initial instead of Error.
      await _close(StreamState.initial, GrpcError.ok());
    }
  }

  /// Called when GRPC closes the stream, which should always be due to some error.
  @visibleForTesting
  Future<void> handleServerClose(GrpcError status) async {
    hardAssert(isStarted, 'Can\'t handle server close on non-started stream!');

    // In theory the stream could close cleanly, however, in our current model we never expect this
    // to happen because if we stop a stream ourselves, this callback will never be called. To
    // prevent cases where we retry without a backoff accidentally, we set the stream to error in
    // all cases.
    await _close(StreamState.error, status);
  }

  Future<void> onNext(RespT change);

  void _performBackoff() {
    hardAssert(_state == StreamState.error, 'Should only perform backoff in an error state');
    _state = StreamState.backoff;

    backoff.backoffAndRun(() async {
      hardAssert(_state == StreamState.backoff, 'State should still be backoff but was $_state');
      // Momentarily set state to Initial as start() expects it.
      _state = StreamState.initial;
      await start();
      hardAssert(isStarted, 'Stream should have started');
    });
  }

  /// Marks this stream as idle. If no further actions are performed on the stream for one minute,
  /// the stream will automatically close itself and notify the stream's [onClose] handler with
  /// [GrpcError.ok]. The stream will then be in a [!isStarted] state, requiring the caller to start
  /// the stream again before further use.
  ///
  /// Only streams that are in state [StreamState.open] can be marked idle, as all other states
  /// imply pending network operations.
  void markIdle() {
    // Starts the idle timer if we are in state [StreamState.Open] and are not yet already running a
    // timer (in which case the previous idle timeout still applies).
    if (isOpen && _idleTimer == null) {
      _idleTimer = _workerQueue.enqueueAfterDelay(
        _idleTimerId,
        const Duration(milliseconds: _idleTimeoutMs),
        _handleIdleCloseTimer,
        'AbstractStream markIdle',
      );
    }
  }

  void _cancelIdleCheck() {
    if (_idleTimer != null) {
      _idleTimer.cancel();
      _idleTimer = null;
    }
  }
}

/// A 'runner' that runs operations but only if [closeCount] remains unchanged. This allows us to
/// turn auth / stream callbacks into no-ops if the stream is closed / re-opened, etc.
///
/// PORTING NOTE: Because all the stream callbacks already happen on the [asyncQueue], we don't need
/// to dispatch onto the queue, and so we instead only expose a run() method which asserts that
/// we're already on the [asyncQueue].
class CloseGuardedRunner {
  CloseGuardedRunner(
    this.asyncQueue,
    this.initialCloseCount,
    this.closeCount,
  );

  final AsyncQueue asyncQueue;
  final int initialCloseCount;
  final int Function() closeCount;

  Future<void> run(Task<void> task, String caller) async {
    if (closeCount() == initialCloseCount) {
      await asyncQueue.enqueue(task, caller);
    } else {
      Log.d('AbstractStream', 'stream callback skipped by CloseGuardedRunner.');
    }
  }
}

/// Implementation of [IncomingStreamObserver] that runs callbacks via [CloseGuardedRunner].
class StreamObserver<ReqT extends GeneratedMessage, RespT extends GeneratedMessage,
    CallbackT extends StreamCallback> implements IncomingStreamObserver<RespT> {
  const StreamObserver(this._dispatcher, this.stream);

  final CloseGuardedRunner _dispatcher;
  final AbstractStream<ReqT, RespT, CallbackT> stream;

  @override
  void onHeaders(Map<String, String> headers) {
    _dispatcher.run(() async {
      if (Log.isDebugEnabled) {
        final Map<String, String> whitelistedHeaders = <String, String>{};
        for (String header in headers.keys) {
          if (Datastore.whiteListedHeaders.contains(header.toLowerCase())) {
            whitelistedHeaders[header] = headers[header];
          }
        }
        if (whitelistedHeaders.isNotEmpty) {
          Log.d('AbstractStream', '($hashCode) Stream received headers: $whitelistedHeaders');
        }
      }
    }, 'onHeaders');
  }

  @override
  Future<void> onNext(RespT response) async {
    await _dispatcher.run(() async {
      if (Log.isDebugEnabled) {
        Log.d('AbstractStream', '($hashCode) Stream received: ${response.writeToJsonMap()}');
      }
      await stream.onNext(response);
    }, 'onNext');
  }

  @override
  void onReady() {
    _dispatcher.run(() async => Log.d('AbstractStream', '($hashCode) Stream is ready'), 'onReady');
  }

  @override
  void onClose(GrpcError status) async {
    await _dispatcher.run(() async {
      if (status.code == StatusCode.ok) {
        Log.d('AbstractStream', '($hashCode) Stream closed.');
      } else {
        Log.d('AbstractStream', '($hashCode) Stream closed with status: $status.');
      }
      await stream.handleServerClose(status);
    }, 'onClose');
  }
}
