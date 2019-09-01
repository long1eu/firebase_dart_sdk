// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/server_timestamp_value.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

class TimestampValue extends FieldValue {
  const TimestampValue(this._value);

  factory TimestampValue.valueOf(Timestamp value) => TimestampValue(value);

  final Timestamp _value;

  @override
  int get typeOrder => FieldValue.typeOrderTimestamp;

  @override
  Timestamp get value => _value;

  @override
  Object valueWith(FieldValueOptions options) {
    if (options.timestampsInSnapshotsEnabled) {
      return _value;
    } else {
      return _value.toDate();
    }
  }

  @override
  int compareTo(FieldValue other) {
    if (other is TimestampValue) {
      return _value.compareTo(other._value);
    } else if (other is ServerTimestampValue) {
      // Concrete timestamps come before server timestamps.
      return -1;
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimestampValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value.toString();
}
