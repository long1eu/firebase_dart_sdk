// File created by
// Lung Razvan <long1eu>
// on 12/11/2026

import 'dart:async';

/// Runs asynchronous operations strictly one after the other, in the order they are requested.
///
/// PORTING NOTE: the Android SDK runs everything (user operations, stream events, timers) on a single worker queue
/// where every task runs to completion before the next one starts. The Dart handlers are asynchronous, so without a
/// queue two of them can be in flight at the same time and observe each other's half finished work.
///
/// A task that is already running on the queue may call [run] again (for example through a callback that is also used
/// from outside the queue): such a nested call runs inline instead of waiting for itself.
class SerialQueue {
  static final Object _zoneKey = Object();

  Future<void> _tail = Future<void>.value();
  Object? _current;

  bool get _isInsideCurrentTask =>
      _current != null && identical(Zone.current[_zoneKey], _current);

  /// Runs [operation] after every operation requested before it completed. If called from the task that is running
  /// right now, runs [operation] immediately.
  Future<T> run<T>(Future<T> Function() operation) {
    if (_isInsideCurrentTask) {
      return operation();
    }

    final Completer<T> result = Completer<T>();
    final Future<void> previous = _tail;
    _tail = result.future.then<void>((_) {}, onError: (Object _) {});
    previous.then<void>((_) {
      final Object token = Object();
      _current = token;
      Zone.current.fork(zoneValues: <Object, Object>{_zoneKey: token}).run(
        () async {
          try {
            result.complete(await operation());
          } catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          } finally {
            if (identical(_current, token)) {
              _current = null;
            }
          }
        },
      );
    });
    return result.future;
  }
}
