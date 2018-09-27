// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// Represents a locally-applied Server Timestamp.
///
/// * Notes:
///   - ServerTimestampValue instances are created as the result of
///   applying a TransformMutation (see [TransformMutation.applyTo]). They can
///   only exist in the local view of a document. Therefore they do not need to be
///   parsed or serialized.
///   - When evaluated locally (e.g. via [DocumentSnapshot.data]), they evaluate
///   to null.
///   - They sort after all TimestampValues. With respect to other
///   ServerTimestampValues, they sort by their localWriteTime.
class ServerTimestampValue extends FieldValue {
  final Timestamp localWriteTime;
  final FieldValue previousValue;

  const ServerTimestampValue(this.localWriteTime, this.previousValue);

  @override
  int get typeOrder => FieldValue.typeOrderTimestamp;

  @override
  Object get value => null;

  @override
  Object valueWith(FieldValueOptions options) {
    switch (options.serverTimestampBehavior) {
      case ServerTimestampBehavior.previous:
        return previousValue != null ? previousValue.valueWith(options) : null;
      case ServerTimestampBehavior.estimate:
        return TimestampValue(localWriteTime).valueWith(options);
      case ServerTimestampBehavior.none:
        return null;

      default:
        throw Assert.fail(
            'Unexpected case for ServerTimestampBehavior: ${options.serverTimestampBehavior}');
    }
  }

  @override
  int compareTo(FieldValue other) {
    if (other is ServerTimestampValue) {
      return localWriteTime.compareTo(other.localWriteTime);
    } else if (other is TimestampValue) {
      // Server timestamps come after all concrete timestamps.
      return 1;
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  String toString() => '<ServerTimestamp localTime=$localWriteTime>';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerTimestampValue &&
          runtimeType == other.runtimeType &&
          localWriteTime == other.localWriteTime &&
          previousValue == other.previousValue;

  @override
  int get hashCode =>
      super.hashCode ^ localWriteTime.hashCode ^ previousValue.hashCode;
}
