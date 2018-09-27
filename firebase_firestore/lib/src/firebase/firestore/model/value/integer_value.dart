// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/number_value.dart';

/// A wrapper for integer/long values in Firestore.
class IntegerValue extends NumberValue {
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
}
