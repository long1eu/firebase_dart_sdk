// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/database_id.dart';
import 'package:meta/meta.dart';

/// Contains info about host, project id and database
class DatabaseInfo {
  const DatabaseInfo(
    this.databaseId,
    this.persistenceKey,
    this.host, {
    @required this.sslEnabled,
  });

  final DatabaseId databaseId;
  final String persistenceKey;
  final String host;
  final bool sslEnabled;

  /// Constructs a new DatabaseInfo.
  ///
  /// [databaseId] The Google Cloud Project ID and database naming the Firestore
  /// instance. [persistenceKey] is a unique identifier for this Firestore's
  /// local storage. Usually derived from [FirebaseApp.name]. [host] is the
  /// hostname of the backend and [sslEnabled] is used to tell whether to use
  /// SSL when connecting.

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('databaseId', databaseId)
          ..add('persistenceKey', persistenceKey)
          ..add('host', host)
          ..add('sslEnabled', sslEnabled))
        .toString();
  }
}
