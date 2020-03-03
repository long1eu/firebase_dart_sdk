// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/src/network/network_request.dart';

/// A network request that returns metadata on a gcs object.
class GetMetadataNetworkRequest extends NetworkRequest {
  GetMetadataNetworkRequest(Uri gsUri, FirebaseApp app) : super(gsUri, app);

  @override
  String get action => 'GET';
}
