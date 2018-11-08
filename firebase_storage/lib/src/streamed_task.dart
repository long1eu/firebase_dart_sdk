// File created by
// Lung Razvan <long1eu>
// on 22/10/2018
import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/task.dart';

@publicApi
abstract class StreamedTask<TState extends StorageTaskState>
    extends Task<TState> {
  /// The task itself can not be resumed, however the [data] stream can be used
  /// as a normal stream. The subscription to that stream can be resumed.
  @override
  Future<bool> resume() {
    throw StateError('This operation is not support on StreamedTask.');
  }

  /// The task itself can not be paused, however the [data] stream can be used
  /// as a normal stream. The subscription to that stream can be paused.
  @override
  Future<bool> pause() {
    throw StateError('This operation is not support on StreamedTask.');
  }

  /// Returns a stream witch emits chucks of data as it becomes available
  Stream<List<int>> get data;
}
