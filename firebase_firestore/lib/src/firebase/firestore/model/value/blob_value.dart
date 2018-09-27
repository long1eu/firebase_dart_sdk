// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/blob.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// A wrapper for blob values in Firestore.
class BlobValue extends FieldValue {
  final Blob _value;

  const BlobValue(this._value);

  factory BlobValue.valueOf(Blob blob) => BlobValue(blob);

  @override
  int get typeOrder => FieldValue.typeOrderBlob;

  @override
  Blob get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is BlobValue) {
      return _value.compareTo(other._value);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => super.hashCode ^ _value.hashCode;
}
