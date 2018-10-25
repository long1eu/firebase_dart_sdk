// File created by
// Lung Razvan <long1eu>
// on 20/10/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_storage/src/network/network_request.dart';

/// Encapsulates a single resumable network request and response
abstract class ResumableNetworkRequest extends NetworkRequest {
  static const String kProtocol = 'X-Goog-Upload-Protocol';
  static const String kCommand = 'X-Goog-Upload-Command';
  static const String kContentType = 'X-Goog-Upload-Header-Content-Type';
  static const String kOffset = 'X-Goog-Upload-Offset';

  ResumableNetworkRequest(Uri gsUri, FirebaseApp app) : super(gsUri, app);
}
