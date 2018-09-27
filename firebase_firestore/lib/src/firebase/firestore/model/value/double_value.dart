// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/number_value.dart';

/// A wrapper for float/double values in Firestore.
class DoubleValue extends NumberValue {
  static const DoubleValue nan = DoubleValue(double.nan);

  final double _value;

  const DoubleValue(this._value);

  factory DoubleValue.valueOf(double value) => DoubleValue(value);

  @override
  double get value => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoubleValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => super.hashCode ^ _value.hashCode;

  @override
  int compareTo(FieldValue other) {
    if (other is! NumberValue) {
      return defaultCompareTo(other);
    }

    NumberValue val = other;
    if (value.isNaN && val.value.isNaN) {
      return 0;
    } else if (value.isNaN) {
      return -1;
    } else if (val.value is double && val.value.isNaN) {
      return 1;
    } else if (val.value == value) {
      return 0;
    }

    return value.compareTo(other.value as num);
  }
}
