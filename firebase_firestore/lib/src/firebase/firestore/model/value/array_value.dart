// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value_options.dart';

/// A wrapper for Array values in Firestore
class ArrayValue extends FieldValue {
  const ArrayValue(this._value);

  factory ArrayValue.fromList(List<FieldValue> list) => ArrayValue(list);

  final List<FieldValue> _value;

  @override
  int get typeOrder => FieldValue.typeOrderArray;

  @override
  List<Object> get value {
    return _value.map((FieldValue it) => it.value).toList(growable: false);
  }

  List<FieldValue> get internalValue => _value;

  @override
  Object valueWith(FieldValueOptions options) {
    return _value
        .map((FieldValue it) => it.valueWith(options))
        .toList(growable: false);
  }

  @override
  int compareTo(FieldValue other) {
    if (other is ArrayValue) {
      final int minLength = min(_value.length, other._value.length);

      for (int i = 0; i < minLength; i++) {
        final int cmp = _value[i].compareTo(other._value[i]);
        if (cmp != 0) {
          return cmp;
        }
      }

      return _value.length.compareTo(other._value.length);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrayValue &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(_value, other._value);

  @override
  int get hashCode => const DeepCollectionEquality().hash(_value);
}
