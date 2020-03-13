// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';

/// A wrapper for boolean value in Firestore.
class BoolValue extends FieldValue {
  const BoolValue._(this._value);

  // ignore: avoid_positional_boolean_parameters
  factory BoolValue.valueOf(bool value) => value ? trueValue : falseValue;

  static const BoolValue trueValue = BoolValue._(true);
  static const BoolValue falseValue = BoolValue._(false);

  final bool _value;

  @override
  int get typeOrder => FieldValue.typeOrderBool;

  // Since we create shared instances for true / false, we can use reference equality.
  @override
  bool get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is BoolValue) {
      return _value == other._value ? 0 : _value ? 1 : -1;
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is BoolValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value ? 1 : 0;
}
