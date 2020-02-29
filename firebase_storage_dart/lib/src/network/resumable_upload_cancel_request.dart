// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/network/resumable_network_request.dart';
import 'package:meta/meta.dart';

/// Cancels an upload request in progress.
class ResumableUploadCancelRequest extends ResumableNetworkRequest {
  ResumableUploadCancelRequest(Uri gsUri, FirebaseApp app, this.url)
      : super(gsUri, app) {
    kCancelCalled = true;
    if (url == null || url.isEmpty) {
      super.error = ArgumentError('uploadURL is null or empty');
    }

    setCustomHeader(ResumableNetworkRequest.kProtocol, 'resumable');
    setCustomHeader(ResumableNetworkRequest.kCommand, 'cancel');
  }

  @visibleForTesting
  static bool kCancelCalled = false;

  @override
  final String url;

  @override
  String get action => 'POST';
}
