// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

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
  });

  final DatabaseId databaseId;
  final String persistenceKey;
  final String host;
  final int port;
  final bool sslEnabled;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('databaseId', databaseId)
          ..add('persistenceKey', persistenceKey)
          ..add('host', host)
          ..add('port', port)
          ..add('sslEnabled', sslEnabled))
        .toString();
  }
}
