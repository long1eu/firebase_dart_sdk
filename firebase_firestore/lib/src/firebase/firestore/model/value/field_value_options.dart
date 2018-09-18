// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/server_timestamp_behavior.dart';

/// Holds settings that define field value deserialization options.
class FieldValueOptions {
  final ServerTimestampBehavior serverTimestampBehavior;
  final bool timestampsInSnapshotsEnabled;

  const FieldValueOptions(
      this.serverTimestampBehavior, this.timestampsInSnapshotsEnabled);
}
