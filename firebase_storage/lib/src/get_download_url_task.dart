// File created by
// Lung Razvan <long1eu>
// on 21/10/2018

import 'dart:async';

import 'package:firebase_storage/src/firebase_storage.dart';
import 'package:firebase_storage/src/internal/exponential_backoff_sender.dart';
import 'package:firebase_storage/src/network/get_metadata_network_request.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:firebase_storage/src/storage_reference.dart';
import 'package:firebase_storage/src/storage_task_scheduler.dart';
import 'package:firebase_storage/src/util/wrapped_future.dart';

/// A Task that retrieves the download URL for a [StorageReference] object
class GetDownloadUrlTask extends WrappedFuture<Uri> {
  static const String _kDownloadTokensKey = 'downloadTokens';

  final StorageReference _reference;
  final ExponentialBackoffSender _sender;

  GetDownloadUrlTask._(this._reference)
      : assert(_reference != null),
        _sender = ExponentialBackoffSender(
          _reference.app,
          _reference.storage.maxOperationRetry,
        ) {
    run();
  }

  static Future<Uri> execute(StorageReference reference) {
    return StorageTaskScheduler.instance
        .scheduleCommand(_execute, <dynamic>[reference.toString()]);
  }

  Future<void> run() async {
    final NetworkRequest request =
        GetMetadataNetworkRequest(_reference.storageUri, _reference.app);

    await _sender.sendWithExponentialBackoff(request);

    Uri downloadUrl;
    if (request.isResultSuccess) {
      downloadUrl = _extractDownloadUrl(request.resultBody);
    }

    request.completeTask(this, downloadUrl);
  }

  Uri _extractDownloadUrl(Map<String, dynamic> response) {
    final String downloadTokens = response[_kDownloadTokensKey];

    if (downloadTokens != null && downloadTokens.isNotEmpty) {
      final String downloadToken = downloadTokens.split(',').first;
      final String baseUrl =
          NetworkRequest.getDefaultUrl(_reference.storageUri);
      return Uri.parse('$baseUrl?alt=media&token=$downloadToken');
    }

    return null;
  }
}

Future<Uri> _execute(List<dynamic> args) {
  final String refUrl = args.first;
  final StorageReference reference =
      FirebaseStorage.instance.getReferenceFromUrl(refUrl);

  return GetDownloadUrlTask._(reference);
}
