// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// Base class inherited from by IntegerValue and DoubleValue. It implements
/// proper number comparisons between the two types.
abstract class NumberValue extends FieldValue {
  const NumberValue();

  @override
  num get value;

  @override
  int get typeOrder => FieldValue.typeOrderNumber;

  @override
  int compareTo(FieldValue other) {
    if (other is! NumberValue) {
      return defaultCompareTo(other);
    }

    return value.compareTo(other.value);
  }
}
