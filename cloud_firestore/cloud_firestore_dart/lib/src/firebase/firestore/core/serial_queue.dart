// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';

import 'package:meta/meta.dart';

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
/// with a `Deferred`) and does not throw it: as in JS, an error that leaves an operation is an unexpected one.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// How many operations threw an error instead of settling it themselves.
  @visibleForTesting
  int get escapedErrors => _escapedErrors;
  int _escapedErrors = 0;

  /// Runs [operation] after every operation requested before it completed.
  Future<T> run<T>(Future<T> Function() operation) {
    final Completer<T> result = Completer<T>();
    final Future<void> previous = _tail;
    _tail = result.future.then<void>((_) {}, onError: (Object _) {});
    previous.then<void>((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        _escapedErrors++;
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
