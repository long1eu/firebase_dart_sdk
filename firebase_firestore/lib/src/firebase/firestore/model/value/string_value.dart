// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// A wrapper for string values in Firestore.
// TODO: Add truncation support
class StringValue extends FieldValue {
  final String _value;

  const StringValue(this._value);

  factory StringValue.valueOf(String value) {
    return StringValue(value);
  }

  @override
  int get typeOrder => FieldValue.typeOrderString;

  @override
  String get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is StringValue) {
      return _value.compareTo(other._value);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StringValue &&
            runtimeType == other.runtimeType &&
            _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;
}
