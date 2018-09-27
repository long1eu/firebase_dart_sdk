// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/number_value.dart';

/// A wrapper for integer/long values in Firestore.
class IntegerValue extends NumberValue {
  static const int max = 9223372036854775807;
  static const int min = -9223372036854775808;

  final int _value;

  const IntegerValue(this._value);

  factory IntegerValue.valueOf(int value) => IntegerValue(value);

  @override
  int get value => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntegerValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => super.hashCode ^ _value.hashCode;

  @override
  int compareTo(FieldValue other) {
    if (other is NumberValue) {
      if (other.value.isNaN) {
        return 1;
      } else if (other.value is double && other.value == 0.0) {
        return value.compareTo(0);
      } else {
        return value.compareTo(other.value);
      }
    } else {
      return defaultCompareTo(other);
    }
  }
}
