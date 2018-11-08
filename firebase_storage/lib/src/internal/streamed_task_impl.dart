// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';

import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/internal/task_impl.dart';
import 'package:firebase_storage/src/internal/task_proxy.dart';
import 'package:firebase_storage/src/streamed_task.dart';

class StreamedTaskImpl<TState extends StorageStreamedTaskState>
    extends TaskImpl<TState> implements StreamedTask<TState> {
  final Stream<dynamic> _received;

  StreamedTaskImpl(Sender sender, this._received, Completer<dynamic> completer)
      : super(sender, _received, completer);

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
