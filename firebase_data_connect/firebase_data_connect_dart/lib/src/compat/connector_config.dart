// Ported from FlutterFire firebase_data_connect 0.4.2 (commit 6a80b1b),
// lib/src/common/dataconnect_options.dart and lib/src/common/common_library.dart. Apache License
// 2.0; see NOTICE.

import 'dart:convert';

/// The connector an instance talks to.
class ConnectorConfig {
  /// The connector [connector] of the service [serviceId] in [location].
  ConnectorConfig(this.location, this.connector, this.serviceId);

  /// The location of the service, for example `us-central1`.
  String location;

  /// The name of the connector.
  String connector;

  /// The id of the service.
  String serviceId;

  /// The three parts as a JSON object: the key of the instance cache.
  String toJson() {
    return jsonEncode(<String, String>{
      'location': location,
      'connector': connector,
      'serviceId': serviceId,
    });
  }
}

/// Who calls: application code ([core]) or generated code ([generated]).
enum CallerSDKType {
  /// Application code.
  core,

  /// Generated code: adds `dart/gen` to the client header.
  generated,
}
