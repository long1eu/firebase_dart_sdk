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

  void completeNext([FutureOr<T> value]) {
    _values.removeFirst().complete(value);
  }

  void completeFollowing(int count, [List<FutureOr<T>> values]) {
    assert(count != 0);
    assert(_values.length >= count);

    for (int i = 0; i < count; i++) {
      _values.removeFirst().complete(values == null ? null : values[i]);
    }
  }

  void completeErrorNext(Object error, [StackTrace stackTrace]) {
    _values.removeFirst().completeError(error, stackTrace);
  }

  Future<T> get next {
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
