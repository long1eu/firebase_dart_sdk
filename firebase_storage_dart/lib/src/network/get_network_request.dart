// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage_vm/src/network/network_request.dart';

/// A network request that returns bytes of a gcs object.
class GetNetworkRequest extends NetworkRequest {
  GetNetworkRequest(Uri gsUri, FirebaseApp app, int startByte)
      : super(gsUri, app) {
    if (startByte != 0) {
      setCustomHeader('Range', 'bytes=$startByte-');
    }
  }

  @override
  String get action => 'GET';

  @override
  String get queryParameters {
    return getPostDataString(
        keys: <String>['alt'], values: <String>['media'], encode: true);
  }
}
