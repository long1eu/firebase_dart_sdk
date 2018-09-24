import 'dart:async';
import 'dart:isolate';

import 'package:firebase_firestore/src/firebase/firestore/util/yeast.dart';

class _Task<TResult> {
  final String id;
  final Future<TResult> Function() handler;

  _Task(this.handler) : id = Yeast.yeast();

  Future<TResult> call() => handler();
}

class Executor {
  final Isolate _isolate;
  final SendPort _taskPort;
  final SendPort _quitPort;
  final Stream _resultStream;

  Executor._(this._isolate, this._taskPort, this._quitPort, this._resultStream);

  static Future<Executor> create(void Function(dynamic e) onError) async {
    final ReceivePort startupPort = ReceivePort();
    final Isolate isolate = await Isolate.spawn(_spawn, startupPort.sendPort,
        errorsAreFatal: false);
    isolate.errors.listen(onError);

    final Stream resultStream = startupPort.asBroadcastStream();
    final List<SendPort> ports = await resultStream.first;
    return Executor._(isolate, ports[0], ports[1], resultStream);
  }

  Future<T> run<T>(final Future<T> Function() handler) async {
    final _Task<T> task = _Task(handler);
    _taskPort.send(task);
    final List<dynamic> result =
        await _resultStream.where((list) => list[0] == task.id).first;
    return result.last;
  }

  void close() {
    _quitPort.send(null);
    _isolate.kill();
  }

  static void _spawn(SendPort executorPort) {
    final ReceivePort taskPort = ReceivePort();
    final ReceivePort quitPort = ReceivePort();
    executorPort.send([taskPort.sendPort, quitPort.sendPort]);

    taskPort.listen((task) async {
      final result = await task();
      executorPort.send([task.id, result]);
    });

    quitPort.first.then((_) {
      quitPort.close();
      taskPort.close();
    });
  }
}
