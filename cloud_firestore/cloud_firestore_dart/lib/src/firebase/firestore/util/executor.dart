import 'dart:async';

class Executor {
  Executor();

  Future<T> run<T>(final Future<T> Function() handler) => handler();

  void close() {}
}
