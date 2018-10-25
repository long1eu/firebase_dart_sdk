// File created by
// Lung Razvan <long1eu>
// on 24/10/2018

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/cancel_exception.dart';
import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/future_handle.dart';
import 'package:firebase_storage/src/internal/task_events.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task_manager.dart';
import 'package:test/test.dart';

const String _tag = 'TestDownloadHelper';

// ignore_for_file: avoid_as
Future<StringBuffer> fileDownload(
    final File file, void Function() callback, final int cancelAfter) async {
  final StringBuffer builder = StringBuffer();

  final StorageReference storage = FirebaseStorage.getInstance()
      .getReferenceFromUrl(
          'gs://project-5516366556574091405.appspot.com/image.jpg');

  expect(storage.activeDownloadTasks, isEmpty);
  expect(StorageTaskManager.instance.getDownloadTasksUnder(storage.parent),
      isEmpty);

  FutureHandler<DownloadTaskSnapshot> task;
  task = storage.getFile(file, (TaskEvent<DownloadTaskSnapshot> event) {
    if (event.type == TaskEventType.success) {
      final String statusMessage =
          '\nonSuccess:\n${fileTaskToString(event.data)}';
      Log.i(_tag, statusMessage);
      builder.write(statusMessage);
      callback?.call();
    } else if (event.type == TaskEventType.progress) {
      final String statusMessage =
          '\nonProgressUpdate:\n${fileTaskToString(event.data)}';
      Log.i(_tag, statusMessage);
      builder.write(statusMessage);

      if (cancelAfter != -1 && event.data.bytesTransferred > cancelAfter) {
        task.cancel();
      }
    } else if (event.type == TaskEventType.complete) {
      final String statusMessage =
          '\nonComplete:Success=\n${task.isInProgress}';
      Log.i(_tag, statusMessage);
      builder.write(statusMessage);
    }
  }).catchError((dynamic error) {
    if (error is CancelException) {
      const String statusMessage = '\nonCanceled:';
      Log.i(_tag, statusMessage);
      builder.write(statusMessage);
    } else {
      const String statusMessage = '\nonFailure:\n$e';
      Log.i(_tag, statusMessage);
      builder.write(statusMessage);
    }
  }) as FutureHandler<DownloadTaskSnapshot>;

  expect(storage.activeDownloadTasks.length, 1);
  expect(StorageTaskManager.instance.getDownloadTasksUnder(storage.parent),
      isNotEmpty);

  if (cancelAfter == 0) {
    await task.cancel();
  }

  return task.then((_) => builder);
}

String fileTaskToString(DownloadTaskSnapshot state) {
  final String exceptionMessage =
      state.error != null ? state.error.message : '<none>';
  final String bytesDownloaded = '${state.bytesTransferred}';

  return '  exceptionMessage:$exceptionMessage\n  '
      'bytesDownloaded:$bytesDownloaded';
}
