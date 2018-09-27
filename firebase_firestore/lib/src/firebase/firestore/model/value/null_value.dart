// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// A wrapper for null values in Firestore.
class NullValue extends FieldValue {
  static const NullValue _instance = NullValue._();

  const NullValue._();

  factory NullValue.nullValue() => _instance;

  @override
  int get typeOrder => FieldValue.typeOrderNull;

  @override
  Object get value => null;

  @override
  int compareTo(FieldValue other) {
    if (other is NullValue || other == null) {
      return 0;
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NullValue && runtimeType == other.runtimeType;

  @override
  int get hashCode => -1;
}
