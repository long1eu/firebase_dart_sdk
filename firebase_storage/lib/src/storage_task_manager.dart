// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'package:firebase_storage/src/file_download_task.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task.dart';

// ignore: always_specify_types
class StorageTaskManager {
  static final StorageTaskManager instance = StorageTaskManager._();

  StorageTaskManager._();

  final Map<String, StorageTask> _inProgressTasks = <String, StorageTask>{};

  /*
  List<UploadTask> getUploadTasksUnder(StorageReference parent) {
    final List<UploadTask> inProgressList = <UploadTask>[];
    final String parentPath = parent.toString();
    for (MapEntry<String, StorageTask> entry in _inProgressTasks.entries) {
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
    final String parentPath = parent.toString();
    for (MapEntry<String, StorageTask> entry in _inProgressTasks.entries) {
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
    print('#ensureRegistered called with: targetTask:[$targetTask]');
    // ensure *this* is added to the in progress list
    _inProgressTasks[targetTask.reference.toString()] = targetTask;
  }

  void unRegister(StorageTask targetTask) {
    print('#unRegister called with: targetTask:[$targetTask]');
    // ensure *this* is added to the in progress list
    final String key = targetTask.reference.toString();
    final StorageTask task = _inProgressTasks[key];
    if (task == null || task == targetTask) {
      _inProgressTasks.remove(key);
    }
  }
}
