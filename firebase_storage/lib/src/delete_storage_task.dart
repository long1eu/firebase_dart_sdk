// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';

import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage/src/network/delete_network_request.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task_scheduler.dart';
import 'package:firebase_storage/src/util/wrapped_future.dart';

/// A task that sends network requests to delete a Google Cloud Storage blob.
class DeleteStorageTask extends WrappedFuture<void> {
  final StorageReference _storageRef;
  final ExponentialBackoffSender _sender;

  DeleteStorageTask._(this._storageRef)
      : assert(_storageRef != null),
        _sender = ExponentialBackoffSender(
            _storageRef.app, _storageRef.storage.maxOperationRetry) {
    run();
  }

  static Future<void> execute(StorageReference storageRef) {
    return StorageTaskScheduler.instance
        .scheduleCommand(_execute, <dynamic>[storageRef.toString()]);
  }

  Future<void> run() async {
    final NetworkRequest request =
        DeleteNetworkRequest(_storageRef.storageUri, _storageRef.app);

    await _sender.sendWithExponentialBackoff(request);
    request.completeTask(this, null);
  }
}

Future<void> _execute(List<dynamic> args) {
  final String refUrl = args.first;
  final StorageReference reference =
      FirebaseStorage.instance.getReferenceFromUrl(refUrl);

  return DeleteStorageTask._(reference);
}
