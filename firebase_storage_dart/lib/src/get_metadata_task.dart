// File created by
// Lung Razvan <long1eu>
// on 22/10/2018

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_vm/src/firebase_storage.dart';
import 'package:firebase_storage_vm/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage_vm/src/network/get_metadata_network_request.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';
import 'package:firebase_storage_vm/src/storage_exception.dart';
import 'package:firebase_storage_vm/src/storage_metadata.dart';
import 'package:firebase_storage_vm/src/storage_reference.dart';
import 'package:firebase_storage_vm/src/storage_task_scheduler.dart';
import 'package:firebase_storage_vm/src/util/wrapped_future.dart';

/// A [Future] that retrieves metadata for a [StorageReference] object
class GetMetadataTask extends WrappedFuture<StorageMetadata> {
  GetMetadataTask._(this._reference)
      : assert(_reference != null),
        _sender = ExponentialBackoffSender(
          _reference.app,
          _reference.storage.maxOperationRetry,
        ) {
    run();
  }

  static const String _tag = 'GetMetadataTask';
  final StorageReference _reference;
  final ExponentialBackoffSender _sender;

  StorageMetadata _resultMetadata;

  static Future<StorageMetadata> execute(StorageReference reference) {
    return StorageTaskScheduler.instance
        .scheduleCommand(_execute, <dynamic>[reference.toString()]);
  }

  Future<void> run() async {
    final NetworkRequest request =
        GetMetadataNetworkRequest(_reference.storageUri, _reference.app);

    await _sender.sendWithExponentialBackoff(request);
    if (request.isResultSuccess) {
      try {
        _resultMetadata =
            StorageMetadata.fromJson(request.resultBody, _reference);
      } on FormatException catch (e) {
        Log.e(
            _tag, 'Unable to parse resulting metadata. ${request.rawResponse}');

        completeError(StorageException.fromException(e));
        return;
      }
    }

    request.completeTask(this, _resultMetadata);
  }
}

Future<StorageMetadata> _execute(List<dynamic> args) {
  final String refUrl = args.first;
  final StorageReference reference =
      FirebaseStorage.instance.getReferenceFromUrl(refUrl);

  return GetMetadataTask._(reference);
}
