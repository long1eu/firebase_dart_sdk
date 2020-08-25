// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';

class WrappedFuture<T> implements Future<T>, Completer<T> {
  final Completer<T> _completer = Completer<T>();

  @override
  void complete([FutureOr<T> value]) => _completer.complete(value);

  @override
  void completeError(Object error, [StackTrace stackTrace]) {
    _completer.completeError(error, stackTrace);
  }

  @override
  bool get isCompleted => _completer.isCompleted;

  @override
  Future<T> get future => _completer.future;

  @override
  Stream<T> asStream() => future.asStream();

  @override
  Future<T> catchError(Function onError, {bool Function(Object error) test}) {
    return future.catchError(onError, test: test);
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function onError}) {
    return future.then(onValue, onError: onError);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function() onTimeout}) {
    return future.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<T> whenComplete(FutureOr<dynamic> Function() action) {
    return future.whenComplete(action);
  }
}
