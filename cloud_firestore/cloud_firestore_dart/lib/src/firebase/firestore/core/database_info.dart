// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/firestore_settings.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:firebase_app_dart/internal.dart';

/// Contains info about host, project id and database
class DatabaseInfo {
  const DatabaseInfo(
    this.databaseId,
    this.persistenceKey,
    this.host, {
    required this.sslEnabled,
    this.port = 443,
    this.forceLongPolling = false,
    this.autoDetectLongPolling = true,
    this.grpcFlowControlWindow = FirestoreSettings.defaultGrpcFlowControlWindow,
  });

  final DatabaseId databaseId;
  final String persistenceKey;
  final String host;
  final int port;
  final bool sslEnabled;

  /// Web transport only: always request the streams in long polling mode.
  final bool forceLongPolling;

  /// Web transport only: switch a stream to long polling when its responses
  /// seem to be held back by a buffering proxy.
  final bool autoDetectLongPolling;

  /// gRPC transport only: the HTTP/2 flow-control window, in bytes.
  final int grpcFlowControlWindow;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('databaseId', databaseId)
          ..add('persistenceKey', persistenceKey)
          ..add('host', host)
          ..add('port', port)
          ..add('sslEnabled', sslEnabled)
          ..add('grpcFlowControlWindow', grpcFlowControlWindow))
        .toString();
  }
}
