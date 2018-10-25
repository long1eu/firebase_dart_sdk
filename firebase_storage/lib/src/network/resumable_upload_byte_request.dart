// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/network/resumable_network_request.dart';

/// A request to upload a single chunk of a large blob.
class ResumableUploadByteRequest extends ResumableNetworkRequest {
  @override
  final String url;

  @override
  final Uint8List outputRaw;

  @override
  final int outputRawSize;

  ResumableUploadByteRequest(Uri gsUri, FirebaseApp app, this.url,
      Uint8List chunk, int offset, int bytesToWrite, bool isFinal)
      : outputRaw = bytesToWrite <= 0 ? null : chunk,
        outputRawSize = bytesToWrite > 0 ? bytesToWrite : 0,
        super(gsUri, app) {
    if (url == null || url.isEmpty) {
      super.error = ArgumentError('uploadURL is null or empty');
    }

    if (chunk == null && bytesToWrite != -1) {
      super.error = ArgumentError('contentType is null or empty');
    }
    if (offset < 0) {
      super.error = ArgumentError('offset cannot be negative');
    }

    super.setCustomHeader(ResumableNetworkRequest.kProtocol, 'resumable');
    if (isFinal && bytesToWrite > 0) {
      super.setCustomHeader(
          ResumableNetworkRequest.kCommand, 'upload, finalize');
    } else if (isFinal) {
      super.setCustomHeader(ResumableNetworkRequest.kCommand, 'finalize');
    } else {
      super.setCustomHeader(ResumableNetworkRequest.kCommand, 'upload');
    }
    super.setCustomHeader(ResumableNetworkRequest.kOffset, '$offset');
  }

  @override
  String get action => 'POST';
}
