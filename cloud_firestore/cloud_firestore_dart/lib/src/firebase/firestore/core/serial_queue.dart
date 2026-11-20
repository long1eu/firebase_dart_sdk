// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_dart/internal.dart';

/// Runs asynchronous operations strictly one after the other, in the order they are requested (the `enqueue` of the
/// JS `AsyncQueue`).
///
/// PORTING NOTE: the Android SDK runs everything (user operations, stream events, timers) on a single worker queue
/// where every task runs to completion before the next one starts. The Dart handlers are asynchronous, so without a
/// queue two of them can be in flight at the same time and observe each other's half finished work.
///
/// As in JS, an operation that is requested by the operation that is running (directly or through what it calls)
/// runs after it. The running operation must not wait for such an operation: it would wait forever. Code that runs on
/// the queue calls the work it needs directly instead of requesting it.
///
/// An operation whose caller expects an error settles the result of the caller itself (the JS operations do that
/// with a `Deferred`) and does not throw it. As in JS, an error that leaves an operation is an unexpected one and
/// fails the queue for good: the operations that wait for their turn fail with that error without running, and the
/// operations that are requested later fail with an error that says so.
class SerialQueue {
  static const String _tag = 'SerialQueue';

  Future<void> _tail = Future<void>.value();

  Object? _failure;
  StackTrace? _failureStackTrace;

  /// The error that failed this queue, or null.
  Object? get failure => _failure;

  /// Whether an unexpected error left an operation: this queue runs no operations any more, except the ones requested
  /// with `evenIfFailed`.
  bool get isFailed => _failure != null;

  /// Runs [operation] after every operation requested before it completed. An error of [operation] fails the returned
  /// future and the queue.
  ///
  /// With [evenIfFailed] the operation also runs on a queue that failed (to shut down); its error does not replace
  /// the one that failed the queue.
  ///
  /// PORTING NOTE: the JS `enqueue` throws when the queue failed; the returned future fails instead.
  Future<T> run<T>(
    Future<T> Function() operation, {
    bool evenIfFailed = false,
  }) {
    return _run<T>(operation, evenIfFailed: evenIfFailed);
  }

  /// Runs [operation] like [run], for callers that do not use its result (the JS `enqueueAndForget`). An error of
  /// [operation] fails the queue and is reported to the current zone as an uncaught error. The returned future
  /// completes without an error once the operation ran.
  ///
  /// PORTING NOTE: the JS `enqueueAndForget` throws when the queue failed. Here the operation is dropped: the
  /// callers are event handlers and timers, where nothing could handle the error, and the failure of the queue was
  /// reported when it happened.
  Future<void> enqueueAndForget(Future<void> Function() operation) {
    if (isFailed) {
      return Future<void>.value();
    }
    final Zone zone = Zone.current;
    return _run<void>(
      operation,
      onOwnError: zone.handleUncaughtError,
    ).then<void>((_) {}, onError: (Object _) {});
  }

  Future<T> _run<T>(
    Future<T> Function() operation, {
    bool evenIfFailed = false,
    void Function(Object error, StackTrace stackTrace)? onOwnError,
  }) {
    if (isFailed && !evenIfFailed) {
      return Future<T>.error(_alreadyFailed(), StackTrace.current);
    }

    final Completer<T> result = Completer<T>();
    final Future<void> previous = _tail;
    _tail = result.future.then<void>((_) {}, onError: (Object _) {});
    previous.then<void>((_) async {
      final Object? failure = _failure;
      if (failure != null && !evenIfFailed) {
        // As in JS, where the tail of the queue is a rejected promise from then on.
        result.completeError(failure, _failureStackTrace);
        return;
      }
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        _fail(error, stackTrace);
        result.completeError(error, stackTrace);
        onOwnError?.call(error, stackTrace);
      }
    });
    return result.future;
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (isFailed) {
      return;
    }
    _failure = error;
    _failureStackTrace = stackTrace;
    Log.e(_tag, 'INTERNAL UNHANDLED ERROR: ${_messageOrStack()}');
  }

  String _messageOrStack() => '$_failure\n$_failureStackTrace';

  /// The error of the JS `verifyNotFailed`.
  AssertionError _alreadyFailed() {
    final String context = jsonEncode(<String, String>{
      'messageOrStack': _messageOrStack(),
    });
    return AssertionError(
      'FIRESTORE INTERNAL ASSERTION FAILED: AsyncQueue is already failed (ID: b815) CONTEXT: $context',
    );
  }
}
