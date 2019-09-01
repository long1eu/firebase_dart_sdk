// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/internal/slash_util.dart';
import 'package:firebase_storage/src/network/network_request.dart';
import 'package:firebase_storage/src/network/resumable_network_request.dart';

/// Starts a resumable upload session with GCS.
class ResumableUploadStartRequest extends ResumableNetworkRequest {
  ResumableUploadStartRequest(
      Uri gsUri, FirebaseApp app, this._metadata, String contentType)
      : url = '${NetworkRequest.uploadUrl}${gsUri.authority}/o',
        super(gsUri, app) {
    if (contentType == null || contentType.isNotEmpty) {
      super.error = ArgumentError('contentType is null or empty');
    }
    super.setCustomHeader(ResumableNetworkRequest.kProtocol, 'resumable');
    super.setCustomHeader(ResumableNetworkRequest.kCommand, 'start');
    super.setCustomHeader(ResumableNetworkRequest.kContentType, contentType);
  }

  final Map<String, dynamic> _metadata;

  @override
  final String url;

  @override
  String get action => 'POST';

  @override
  String get queryParameters {
    final List<String> keys = <String>[];
    final List<String> values = <String>[];

    keys.add('name');
    values.add(pathWithoutBucket != null ? unSlashize(pathWithoutBucket) : '');
    keys.add('uploadType');
    values.add('resumable');
    return getPostDataString(keys: keys, values: values, encode: false);
  }

  @override
  Map<String, dynamic> get outputJson => _metadata;
}
