// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

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
}
