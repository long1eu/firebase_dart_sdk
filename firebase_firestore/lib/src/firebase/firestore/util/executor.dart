import 'dart:async';

class Executor {
  Executor._();

  static Future<Executor> create(void Function(dynamic e) onError) async {
    return Executor._();
  }

  Future<T> run<T>(final Future<T> Function() handler) async => await handler();

  void close() {}
}
