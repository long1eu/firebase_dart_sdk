// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:meta/meta.dart';

/// Contains info about host, project id and database
class DatabaseInfo {
  const DatabaseInfo(
    this.databaseId,
    this.persistenceKey,
    this.host, {
    @required this.sslEnabled,
    this.port = 443,
  }) : assert(port != null);

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
