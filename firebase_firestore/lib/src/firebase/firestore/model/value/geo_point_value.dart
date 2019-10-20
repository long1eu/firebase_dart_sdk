// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/geo_point.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// A wrapper for geo point values in Firestore.
class GeoPointValue extends FieldValue {
  const GeoPointValue(this._value);

  factory GeoPointValue.valueOf(GeoPoint value) => GeoPointValue(value);

  final GeoPoint _value;

  @override
  int get typeOrder => FieldValue.typeOrderGeopoint;

  @override
  GeoPoint get value => _value;

  @override
  int compareTo(FieldValue other) {
    if (other is GeoPointValue) {
      return _value.compareTo(other._value);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPointValue && runtimeType == other.runtimeType && _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}
