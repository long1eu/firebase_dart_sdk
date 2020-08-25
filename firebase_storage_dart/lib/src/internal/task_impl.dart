// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';
import 'dart:isolate';

import 'package:firebase_storage_vm/src/internal/task_events.dart';
import 'package:firebase_storage_vm/src/streamed_task.dart';
import 'package:firebase_storage_vm/src/task.dart';

class TaskImpl<TState extends StorageTaskState> extends Task<TState> {
  TaskImpl._(this._received, this._completer) {
    _received
        .where((dynamic data) => data is SendPort)
        .cast<SendPort>()
        .first
        .then((SendPort data) => _port = data);
  }

  final Stream<dynamic> _received;
  final Completer<TState> _completer;

  List<dynamic> _queue = <dynamic>[];
  SendPort _port;
  int _id = 0;

  static TaskImpl<TState> create<TState extends StorageTaskState>(
      Stream<dynamic> received, Completer<TState> completer) {
    return TaskImpl<TState>._(received, completer);
  }

  @override
  Future<TState> get future => _completer.future;

  @override
  Future<bool> cancel() => _callMethod('cancel');

  @override
  Future<bool> pause() => _callMethod('pause');

  @override
  Future<bool> resume() => _callMethod('resume');

  @override
  Future<bool> get isCanceled => _callMethod('isCanceled');

  @override
  Future<bool> get isInProgress => _callMethod('isInProgress');

  @override
  Future<bool> get isPaused => _callMethod('isPaused');

  Future<bool> _callMethod(String method) async {
    final int id = ++_id;
    _send(<dynamic>[id, method]);

    final bool result = (await _received
        .where((dynamic it) => it[0] == id && it[1] == method)
        .first)[2];
    return result;
  }

  void _send(dynamic message) {
    if (_queue == null) {
      _port.send(message);
    }
    _queue.add(message);

    if (_port != null) {
      final List<dynamic> queue = _queue.toList();
      _queue = null;
      queue.forEach(_port.send);
    }
  }

  @override
  Stream<TaskEvent<TState>> get events => _received
      .where((dynamic data) => data is TaskPayload)
      .cast<TaskPayload>()
      .map(TaskEvent.deserialized);
}

class StreamedTaskImpl<TState extends StorageStreamedTaskState>
    extends TaskImpl<TState> implements StreamedTask<TState> {
  StreamedTaskImpl._(Stream<dynamic> received, Completer<TState> completer)
      : super._(received, completer);

  static StreamedTaskImpl<TState>
      create<TState extends StorageStreamedTaskState>(
          Stream<dynamic> received, Completer<TState> completer) {
    return StreamedTaskImpl<TState>._(received, completer);
  }

  @override
  Future<bool> resume() {
    throw StateError('This operation is not support on StreamedTask.');
  }

  @override
  Future<bool> pause() {
    throw StateError('This operation is not support on StreamedTask.');
  }

  @override
  Stream<List<int>> get data => _received
      .where((dynamic data) => data is TaskPayload)
      .cast<TaskPayload>()
      .map<TaskEvent<StorageStreamedTaskState>>(TaskEvent.deserialized)
      .where((TaskEvent<StorageStreamedTaskState> it) =>
          it.type == TaskEventType.progress)
      .map((TaskEvent<StorageStreamedTaskState> it) => it.data.data);
}
