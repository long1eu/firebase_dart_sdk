// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';

/// A network request that deletes a gcs object.
class DeleteNetworkRequest extends NetworkRequest {
  DeleteNetworkRequest(Uri gsUri, FirebaseApp app) : super(gsUri, app);

  @override
  String get action => 'DELETE';
}
