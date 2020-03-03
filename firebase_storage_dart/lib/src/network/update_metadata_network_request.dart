// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';

/// Represents a request to update metadata on a GCS blob.
class UpdateMetadataNetworkRequest extends NetworkRequest {
  UpdateMetadataNetworkRequest(Uri gsUri, FirebaseApp app, this._metadata)
      : super(gsUri, app) {
    setCustomHeader('X-HTTP-Method-Override', 'PATCH');
  }

  final Map<String, dynamic> _metadata;

  @override
  String get action => 'PUT';

  @override
  Map<String, dynamic> get outputJson => _metadata;
}
