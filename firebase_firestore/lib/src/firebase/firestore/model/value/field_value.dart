// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value_options.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';

/// A field value represents a data type as stored by Firestore.
///
/// Supported types are:
/// * Null
/// * Bool
/// * todo finish this
abstract class FieldValue implements Comparable<FieldValue> {
  static final int typeOrderNull = 0;
  static final int typeOrderBool = 1;
  static final int typeOrderNumber = 2;
  static final int typeOrderTimestamp = 3;
  static final int typeOrderString = 4;
  static final int typeOrderBlob = 5;
  static final int typeOrderReference = 6;
  static final int typeOrderGeopoint = 7;
  static final int typeOrderArray = 8;
  static final int typeOrderObject = 9;

  const FieldValue();

  int get typeOrder;

  /// Converts a FieldValue into the value that users will see in document
  /// snapshots using the default deserialization options.
  Object get value;

  /// Converts a FieldValue into the value that users will see in document
  /// snapshots using the provided deserialization options.
  Object valueWith(FieldValueOptions options) => value;

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;

  @override
  int compareTo(FieldValue other);

  @override
  String toString() {
    Object val = value;
    return val == null ? 'null' : val.toString();
  }

  int defaultCompareTo(FieldValue other) {
    int cmp = typeOrder.compareTo(other.typeOrder);
    Assert.hardAssert(cmp != 0,
        'Default compareTo should not be used for values of same type.');
    return cmp;
  }
}
