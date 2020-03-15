// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/timestamp_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

/// Represents a locally-applied Server Timestamp.
///
/// Notes:
///   - ServerTimestampValue instances are created as the result of applying a [TransformMutation]
///   (see TransformMutation.applyTo methods). They can only exist in the local view of a document.
///   Therefore they do not need to be parsed or serialized.
///   - When evaluated locally (e.g. via [DocumentSnapshot.ata]), they evaluate to null.
///   - They sort after all [TimestampValue]s. With respect to other [ServerTimestampValue]s, they
///   sort by their [localWriteTime].
class ServerTimestampValue extends FieldValue {
  const ServerTimestampValue(this.localWriteTime, this._previousValue);

  final Timestamp localWriteTime;
  final FieldValue _previousValue;

  @override
  int get typeOrder => FieldValue.typeOrderTimestamp;

  @override
  Object get value => null;

  /// Returns the value of the field before this ServerTimestamp was set.
  ///
  /// Preserving the previous values allows the user to display the last resoled
  /// value until the backend responds with the timestamp
  /// [ServerTimestampBehavior].
  Object get previousValue {
    if (_previousValue is ServerTimestampValue) {
      final ServerTimestampValue value = _previousValue;
      return value._previousValue;
    }

    return _previousValue != null ? _previousValue.value : null;
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
  String toString() {
    return (ToStringHelper(ServerTimestampValue)
          ..add('localWriteTime', localWriteTime)
          ..add('previousValue', previousValue))
        .toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerTimestampValue &&
          runtimeType == other.runtimeType &&
          localWriteTime == other.localWriteTime &&
          previousValue == other.previousValue;

  @override
  int get hashCode => localWriteTime.hashCode ^ previousValue.hashCode;
}
