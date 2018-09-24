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

/// An [AbstractStream] is an abstract base class that implements the [Stream]
/// interface.
///
/// [ReqT] The proto type that will be sent in this stream
/// [RespT] The proto type that is received through this stream
/// [CallbackT] The type which is used for stream specific callbacks.
abstract class AbstractStream<ReqT, RespT, CallbackT extends StreamCallback>
    implements Stream<CallbackT> {
  /**
   * Initial backoff time in milliseconds after an error. Set to 1s according to
   * https://cloud.google.com/apis/design/errors.
   */
  /*/*private*/*/
  static final int BACKOFF_INITIAL_DELAY_MS =
      Duration(seconds: 1).inMilliseconds;

  /*/*private*/*/
  static final int BACKOFF_MAX_DELAY_MS = Duration(minutes: 1).inMilliseconds;

  /*/*private*/*/
  static final double BACKOFF_FACTOR = 1.5;

  /** The time a stream stays open after it is marked idle. */
  /*/*private*/*/
  static final int IDLE_TIMEOUT_MS = Duration(minutes: 1).inMilliseconds;

  /*/*private*/*/
  DelayedTask idleTimer;

  /*/*private*/*/
  final FirestoreChannel firestoreChannel;

  /*/*private*/*/
  final ClientMethod<ReqT, RespT> methodDescriptor;

  /*/*private*/*/
  final AsyncQueue workerQueue;

  /*/*private*/*/
  final TimerId idleTimerId;

  /*/*private*/*/
  StreamState state = StreamState.Initial;

  /// A close count that's incremented every time the stream is closed; used by
  /// [CloseGuardedRunner] to invalidate callbacks that happen after close.
  int _closeCount = 0;

  BidiChannel<ReqT, RespT> _call;
  final ExponentialBackoff backoff;
  final CallbackT listener;

  AbstractStream(
    this.firestoreChannel,
    this.methodDescriptor,
    this.workerQueue,
    TimerId connectionTimerId,
    this.idleTimerId,
    this.listener,
  ) : backoff = ExponentialBackoff(
          workerQueue,
          connectionTimerId,
          BACKOFF_INITIAL_DELAY_MS,
          BACKOFF_FACTOR,
          BACKOFF_MAX_DELAY_MS,
        );

  @override
  bool get isStarted {
    return state == StreamState.Starting ||
        state == StreamState.Open ||
        state == StreamState.Backoff;
  }

  @override
  bool get isOpen {
    return state == StreamState.Open;
  }

  @override
  void start() {
    Assert.hardAssert(_call == null, 'Last call still set');
    Assert.hardAssert(idleTimer == null, 'Idle timer still set');

    if (state == StreamState.Error) {
      _performBackoff();
      return;
    }

    Assert.hardAssert(state == StreamState.Initial, 'Already started');

    final CloseGuardedRunner closeGuardedRunner =
        CloseGuardedRunner(_closeCount, () => _closeCount);
    final StreamObserver<RespT> streamObserver =
        new StreamObserver<RespT>(closeGuardedRunner, this);

    _call =
        firestoreChannel.runBidiStreamingRpc(methodDescriptor, streamObserver);

    // Note that Starting is only used as intermediate state until onOpen is called asynchronously,
    // since auth handled transparently by gRPC
    state = StreamState.Starting;

    workerQueue.enqueueAndForget(() {
      closeGuardedRunner.run(() {
        state = StreamState.Open;
        this.listener.onOpen();
      });
    });
  }

  /// Closes the stream and cleans up as necessary:
  ///
  /// <ul>
  /// <li>closes the underlying GRPC stream;
  /// <li>calls the [onClose] handler with the given [status];
  /// <li>sets internal stream state to [finalState];
  /// <li>adjusts the backoff timer based on status
  /// </ul>
  ///
  /// * A new stream can be opened by calling [start].
  Future<void> _close(StreamState finalState, GrpcError status) async {
    Assert.hardAssert(isStarted, 'Only started streams should be closed.');
    Assert.hardAssert(
        finalState == StreamState.Error || status.code == StatusCode.ok,
        'Can\'t provide an error when not in an error state.');

    // Cancel any outstanding timers (they're guaranteed not to execute).
    _cancelIdleCheck();
    backoff.cancel();

    // Invalidates any stream-related callbacks (e.g. from auth or the
    // underlying stream), guaranteeing they won't execute.
    _closeCount++;

    final int code = status.code;
    if (code == StatusCode.ok) {
      // If this is an intentional close ensure we don't delay our next
      // connection attempt.
      backoff.reset();
    } else if (code == StatusCode.resourceExhausted) {
      Log.d(runtimeType.toString(),
          '($hashCode) Using maximum backoff delay to prevent overloading the backend.');
      backoff.resetToMax();
    } else if (code == StatusCode.unauthenticated) {
      // 'unauthenticated' error means the token was rejected. Try force
      // refreshing it in case it just expired.
      firestoreChannel.invalidateToken();
    }

    if (finalState != StreamState.Error) {
      Log.d(runtimeType.toString(), '($hashCode) Performing stream teardown');
      tearDown();
    }

    if (_call != null) {
      // Clean up the underlying RPC. If this [close()] is in response to an
      // error, don't attempt to call half-close to avoid secondary failures.
      if (status.code == StatusCode.ok) {
        Log.d(runtimeType.toString(), "($hashCode) Closing stream client-side");
        await _call.cancel();
      }
      _call = null;
    }

    // This state must be assigned before calling listener.onClose to allow the
    // callback to inhibit backoff or otherwise manipulate the state in its
    // non-started state.
    this.state = finalState;

    // Notify the listener that the stream closed.
    listener.onClose(status);
  }

  /// Can be overridden to perform additional cleanup before the stream is
  /// closed. Calling super.tearDown() is not required.
  void tearDown() {}

  @override
  Future<void> stop() async {
    if (isStarted) {
      await _close(StreamState.Initial, GrpcError.ok());
    }
  }

  @override
  void inhibitBackoff() {
    Assert.hardAssert(
        !isStarted, 'Can only inhibit backoff after in a stopped state');

    state = StreamState.Initial;
    backoff.reset();
  }

  void writeRequest(ReqT message) {
    Log.d(runtimeType.toString(), '($hashCode) Stream sending: $message');
    _cancelIdleCheck();
    _call.add(message);
  }

  /// Called by the idle timer when the stream should close due to inactivity.
  Future<void> _handleIdleCloseTimer() async {
    if (this.isOpen) {
      // When timing out an idle stream there's no reason to force the stream
      // into backoff when it restarts so set the stream state to Initial
      // instead of Error.
      await _close(StreamState.Initial, GrpcError.ok());
    }
  }

  /// Called when GRPC closes the stream, which should always be due to some
  /// error.
  @visibleForTesting
  void handleServerClose(GrpcError status) async {
    Assert.hardAssert(
        isStarted, 'Can\'t handle server close on non-started stream!');

    // In theory the stream could close cleanly, however, in our current model
    // we never expect this to happen because if we stop a stream ourselves,
    // this callback will never be called. To prevent cases where we retry
    // without a backoff accidentally, we set the stream to error in all cases.
    await _close(StreamState.Error, status);
  }

  void onNext(RespT change);

  void _performBackoff() {
    Assert.hardAssert(state == StreamState.Error,
        'Should only perform backoff in an error state');
    state = StreamState.Backoff;

    backoff.backoffAndRun(() {
      Assert.hardAssert(state == StreamState.Backoff,
          'State should still be backoff but was $state');
      // Momentarily set state to Initial as start() expects it.
      state = StreamState.Initial;
      start();
      Assert.hardAssert(isStarted, "Stream should have started");
    });
  }

  /// Marks this stream as idle. If no further actions are performed on the
  /// stream for one minute, the stream will automatically close itself and
  /// notify the stream's [onClose] handler with [GrpcError.ok]. The stream will
  /// then be in a [!isStarted] state, requiring the caller to start the stream
  /// again before further use.
  ///
  /// * Only streams that are in state [StreamState.Open] can be marked idle, as
  /// all other states imply pending network operations.
  void markIdle() {
    // Starts the idle timer if we are in state [StreamState.Open] and are not
    // yet already running a timer (in which case the previous idle timeout
    // still applies).
    if (this.isOpen && idleTimer == null) {
      idleTimer = workerQueue.enqueueAfterDelay(this.idleTimerId,
          Duration(milliseconds: IDLE_TIMEOUT_MS), _handleIdleCloseTimer);
    }
  }

  void _cancelIdleCheck() {
    if (idleTimer != null) {
      idleTimer.cancel();
      idleTimer = null;
    }
  }
}

/// A "runner" that runs operations but only if [closeCount] remains unchanged.
/// This allows us to turn auth / stream callbacks into no-ops if the stream is
/// closed / re-opened, etc.
///
/// * PORTING NOTE: Because all the stream callbacks already happen on the
/// [workerQueue], we don't need to dispatch onto the queue, and so we instead
/// only expose a run() method which asserts that we're already on the
/// [workerQueue].
class CloseGuardedRunner {
  final int initialCloseCount;
  final int Function() closeCount;

  CloseGuardedRunner(this.initialCloseCount, this.closeCount);

  void run(Function task) {
    if (closeCount() == initialCloseCount) {
      task();
    } else {
      Log.d('AbstractStream', 'stream callback skipped by CloseGuardedRunner.');
    }
  }
}

/// Implementation of [IncomingStreamObserver] that runs callbacks via
/// [CloseGuardedRunner].
class StreamObserver<RespT> implements IncomingStreamObserver<RespT> {
  final CloseGuardedRunner _dispatcher;
  final AbstractStream stream;

  StreamObserver(this._dispatcher, this.stream);

  @override
  void onHeaders(Map<String, String> headers) {
    _dispatcher.run(() {
      if (Log.isDebugEnabled) {
        Map<String, String> whitelistedHeaders = <String, String>{};
        for (String header in headers.keys) {
          if (Datastore.WHITE_LISTED_HEADERS.contains(header.toLowerCase())) {
            whitelistedHeaders[header] = headers[header];
          }
        }
        if (!whitelistedHeaders.isEmpty) {
          Log.d('AbstractStream',
              '($hashCode) Stream received headers: $whitelistedHeaders');
        }
      }
    });
  }

  @override
  void onNext(RespT response) {
    _dispatcher.run(() {
      Log.d('AbstractStream', '($hashCode) Stream received: $response');
      stream.onNext(response);
    });
  }

  @override
  void onReady() {
    _dispatcher
        .run(() => Log.d('AbstractStream', "($hashCode) Stream is ready"));
  }

  @override
  void onClose(GrpcError status) {
    _dispatcher.run(() {
      if (status.code == StatusCode.ok) {
        Log.d('AbstractStream', '($hashCode) Stream closed.');
      } else {
        Log.d('AbstractStream',
            '($hashCode) Stream closed with status: $status.');
      }
      stream.handleServerClose(status);
    });
  }
}
