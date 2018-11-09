// File created by
// Lung Razvan <long1eu>
// on 08/11/2018

import 'dart:async';
import 'dart:isolate';

import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';
import 'package:firebase_storage/src/storage_task_scheduler.dart';
import 'package:firebase_storage/src/task.dart';
import 'package:meta/meta.dart';

typedef TaskBuilder<T extends StorageTaskState> = Task<T> Function(
    Stream<dynamic> received, Completer<T> completer);

typedef Sender = void Function(dynamic);

typedef TaskExecutor = Future<void> Function(List<dynamic> args);

typedef StorageTaskBuilder<TState extends StorageTaskState>
    = StorageTask<TState> Function(
        StorageReference reference, SendPort sendPort, List<dynamic> args);

Task<TState> proxySchedule<TState extends StorageTaskState>({
  @required StorageReference storage,
  @required TaskBuilder<TState> taskBuilder,
  @required StorageTaskBuilder<TState> storageTaskBuilder,
  List<dynamic> args = const <dynamic>[],
}) {
  final ReceivePort receivePort = ReceivePort();
  final Stream<dynamic> received = receivePort.asBroadcastStream();
  final Completer<TState> completer = Completer<TState>();

  received.listen((dynamic data) {
    if (data is TaskPayload) {
      final TaskEvent<TState> event = TaskEvent.deserialized<TState>(data);

      if (event.type == TaskEventType.complete) {
        receivePort.close();
        completer.complete(event.data);
      }
    } else if (data is SendPort) {
      // this is handled by the [TaskImpl]
    } else if (data is List) {
      // this are method calls handled by the [TaskImpl]
    } else {
      throw StateError('Something wrong came of the task ReceivePort. $data');
    }
  });

  StorageTaskScheduler.instance.scheduleDownload(
    _execute,
    <dynamic>[
      receivePort.sendPort,
      storage.toString(),
      storageTaskBuilder,
    ]..addAll(args),
  );

  return taskBuilder(received, completer);
}

Future<void> _execute<TState extends StorageTaskState>(
    List<dynamic> arguments) async {
  final SendPort sendPort = arguments[0];
  final ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final String referenceUrl = arguments[1];

  // TODO:{22/10/2018 14:15}-long1eu: this is not good since we don't know if
  // this is the right FirestoreStorage instance
  final StorageReference storage =
      FirebaseStorage.instance.getReferenceFromUrl(referenceUrl);

  final StorageTaskBuilder<TState> builder = arguments[2];
  final List<dynamic> userArgs = arguments.sublist(3);
  final StorageTask<TState> task = builder(storage, sendPort, userArgs);

  receivePort.cast<List<dynamic>>().listen((List<dynamic> args) {
    final int id = args[0];
    final String method = args[1];
    bool result;
    if (method == 'cancel') {
      result = task.cancel();
    } else if (method == 'pause') {
      result = task.pause();
    } else if (method == 'resume') {
      result = task.resume();
    } else if (method == 'isCanceled') {
      result = task.isCanceled;
    } else if (method == 'isInProgress') {
      result = task.isInProgress;
    } else if (method == 'isPaused') {
      result = task.isPaused;
    } else {
      throw StateError('This call is not recognized. $args');
    }

    sendPort.send(<dynamic>[id, method, result]);
  });

  return task.future;
}
