// File created by
// Lung Razvan <long1eu>
// on 10/10/2018

import 'dart:async';
import 'dart:collection';

class AwaitHelper<T> {
  AwaitHelper([int count = 1]) {
    for (int i = 0; i < count; i++) {
      _values.add(Completer<T>());
    }
  }

  final Queue<Completer<T>> _values = Queue<Completer<T>>();

  void add([int count = 1]) {
    for (int i = 0; i < count; i++) {
      _values.add(Completer<T>());
    }
  }

  /// Completes the next pending slot. Like `TaskCompletionSource.trySetResult`
  /// in the Java tests, this is a no-op when no slot is left.
  void completeNext([FutureOr<T>? value]) {
    if (_values.isEmpty) {
      return;
    }
    _lastCompleted = _values.removeFirst()..complete(value as FutureOr<T>);
  }

  void completeFollowing(int count, [List<FutureOr<T>?>? values]) {
    assert(count != 0);
    assert(_values.length >= count);

    for (int i = 0; i < count; i++) {
      _values.removeFirst().complete(
          values == null ? null as FutureOr<T> : values[i] as FutureOr<T>);
    }
  }

  void completeErrorNext(Object error, [StackTrace? stackTrace]) {
    _values.removeFirst().completeError(error, stackTrace);
  }

  Completer<T>? _lastCompleted;

  Future<T> get next {
    // If every slot was already completed (e.g. the event arrived before the
    // test started waiting), the most recent result is still observable.
    if (_values.isEmpty && _lastCompleted != null) {
      return _lastCompleted!.future;
    }
    return _values.first.future;
  }

  Future<List<T>> get all => following(length);

  Future<List<T>> following(int count) {
    assert(count != 0);
    assert(_values.length >= count);

    return Future.wait<T>(
        _values.take(count).map((Completer<T> it) => it.future));
  }

  bool get isCompleted => _values.every((Completer<T> it) => it.isCompleted);

  int get length => _values.length;

  bool get isEmpty => _values.isEmpty;

  bool get isNotEmpty => _values.isNotEmpty;
}
