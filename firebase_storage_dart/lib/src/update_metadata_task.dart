// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/firebase_storage.dart';
import 'package:firebase_storage_vm/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';
import 'package:firebase_storage_vm/src/network/update_metadata_network_request.dart';
import 'package:firebase_storage_vm/src/storage_exception.dart';
import 'package:firebase_storage_vm/src/storage_metadata.dart';
import 'package:firebase_storage_vm/src/storage_reference.dart';
import 'package:firebase_storage_vm/src/storage_task_scheduler.dart';
import 'package:firebase_storage_vm/src/util/wrapped_future.dart';

/// A Task that updates metadata on a [StorageReference]
class UpdateMetadataTask extends WrappedFuture<StorageMetadata> {
  UpdateMetadataTask._(this._storageRef, this._newMetadata)
      : _sender = ExponentialBackoffSender(
          _storageRef.app,
          _storageRef.storage.maxOperationRetry,
        ) {
    run();
  }

  static const String _tag = 'UpdateMetadataTask';

  final StorageReference _storageRef;
  final Map<String, dynamic> _newMetadata;
  final ExponentialBackoffSender _sender;

  StorageMetadata _resultMetadata;

  static Future<StorageMetadata> execute(
      StorageReference storageRef, StorageMetadata newMetadata) {
    return StorageTaskScheduler.instance.scheduleCommand(
        _execute, <dynamic>[storageRef.toString(), newMetadata.createJson()]);
  }

  Future<void> run() async {
    NetworkRequest request;
    try {
      request = UpdateMetadataNetworkRequest(
          _storageRef.storageUri, _storageRef.app, _newMetadata);
    } on FormatException catch (e) {
      Log.e(_tag, 'Unable to create the request from metadata.');

      completeError(StorageException.fromException(e));
      return;
    }

    await _sender.sendWithExponentialBackoff(request);
    if (request.isResultSuccess) {
      try {
        _resultMetadata =
            StorageMetadata.fromJson(request.resultBody, _storageRef);
      } on FormatException catch (e) {
        Log.e(
            _tag,
            'Unable to parse a valid JSON object from resulting metadata: '
            '${request.rawResponse}');

        completeError(StorageException.fromException(e));
        return;
      }
    }

    request.completeTask(this, _resultMetadata);
  }
}

Future<StorageMetadata> _execute(List<dynamic> args) {
  final String refUrl = args[0];
  final Map<String, dynamic> json = args[1];

  final StorageReference reference =
      FirebaseStorage.instance.getReferenceFromUrl(refUrl);

  return UpdateMetadataTask._(reference, json);
}
