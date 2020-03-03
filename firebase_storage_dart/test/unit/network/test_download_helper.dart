// File created by
// Lung Razvan <long1eu>
// on 24/10/2018

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/cancel_exception.dart';
import 'package:firebase_storage_vm/src/firebase_storage.dart';
import 'package:firebase_storage_vm/src/internal/task_events.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task_manager.dart';
import 'package:firebase_storage/src/task.dart';
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

  bool success;
  final Task<DownloadTaskSnapshot> task = storage.getFile(file);
  task.events.listen((TaskEvent<DownloadTaskSnapshot> event) async {
    if (event.type == TaskEventType.success) {
      success = true;
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
        await task.cancel();
      }
    } else if (event.type == TaskEventType.complete) {
      final String statusMessage = '\nonComplete:Success=\n$success';
      Log.i(_tag, statusMessage);
      builder.write(statusMessage);
    } else if (event.type == TaskEventType.error) {
      success = false;
      final dynamic error = event.data.error;
      if (error is CancelException) {
        const String statusMessage = '\nonCanceled:';
        Log.i(_tag, statusMessage);
        builder.write(statusMessage);
      } else {
        const String statusMessage = '\nonFailure:\n$e';
        Log.i(_tag, statusMessage);
        builder.write(statusMessage);
      }
    } else {
      throw StateError('Unhandeled event type $event.');
    }
  });

  expect(storage.activeDownloadTasks.length, 1);
  expect(
      StorageTaskManager.instance
          .getDownloadTasksUnder(storage.parent)
          .isNotEmpty,
      isTrue);

  if (cancelAfter == 0) {
    await task.cancel();
  }

  return task.future.then((_) => builder);
}

String fileTaskToString(DownloadTaskSnapshot state) {
  final String exceptionMessage =
      state.error != null ? state.error.message : '<none>';
  final String bytesDownloaded = '${state.bytesTransferred}';

  return '  exceptionMessage:$exceptionMessage\n  '
      'bytesDownloaded:$bytesDownloaded';
}
