// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'package:firebase_storage/src/file_download_task.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';

class StorageTaskManager {
  static final StorageTaskManager instance = StorageTaskManager._();

  StorageTaskManager._();

  final Map<String, StorageTask> mInProgressTasks = <String, StorageTask>{};

  /*
  List<UploadTask> getUploadTasksUnder(StorageReference parent) {
    final List<UploadTask> inProgressList = <UploadTask>[];
    final String parentPath = parent.toString();
    for (MapEntry<String, StorageTask> entry in mInProgressTasks.entries) {
      if (entry.key.startsWith(parentPath)) {
        final StorageTask task = entry.value;
        if (task is UploadTask) {
          inProgressList.add(task);
        }
      }

      return inProgressList;
    }
  }
  */

  List<FileDownloadTask> getDownloadTasksUnder(StorageReference parent) {
    final List<FileDownloadTask> inProgressList = <FileDownloadTask>[];
    String parentPath = parent.toString();
    for (MapEntry<String, StorageTask> entry in mInProgressTasks.entries) {
      if (entry.key.startsWith(parentPath)) {
        final StorageTask task = entry.value;
        if (task is FileDownloadTask) {
          inProgressList.add(task);
        }
      }
    }
    return inProgressList;
  }

  void ensureRegistered(StorageTask targetTask) {
    // ensure *this* is added to the in progress list
    mInProgressTasks[targetTask.storage.toString()] = targetTask;
  }

  void unRegister(StorageTask targetTask) {
    // ensure *this* is added to the in progress list
    final String key = targetTask.storage.toString();
    final StorageTask task = mInProgressTasks[key];
    if (task == null || task == targetTask) {
      mInProgressTasks.remove(key);
    }
  }
}
