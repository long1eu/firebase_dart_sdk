// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';

/// A field value represents a data type as stored by Firestore.
///
/// Supported types are:
///   * Null
///   * Boolean
///   * Double
///   * Timestamp
///   * ServerTimestamp (a sentinel used in uncommitted writes)
///   * String
///   * Binary
///   * (Document) References
///   * GeoPoint
///   * Array
///   * Object
abstract class FieldValue implements Comparable<FieldValue> {
  const FieldValue();

  static const int typeOrderNull = 0;
  static const int typeOrderBool = 1;
  static const int typeOrderNumber = 2;
  static const int typeOrderTimestamp = 3;
  static const int typeOrderString = 4;
  static const int typeOrderBlob = 5;
  static const int typeOrderReference = 6;
  static const int typeOrderGeopoint = 7;
  static const int typeOrderArray = 8;
  static const int typeOrderObject = 9;

  int get typeOrder;

  /// Converts a [FieldValue] into the value that users will see in document snapshots using the
  /// default deserialization options.
  Object get value;

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;

  @override
  int compareTo(FieldValue other);

  @override
  String toString() {
    final Object val = value;
    return val == null ? 'null' : val.toString();
  }

  int defaultCompareTo(FieldValue other) {
    final int cmp = typeOrder.compareTo(other.typeOrder);
    hardAssert(cmp != 0,
        'Default compareTo should not be used for values of same type.');
    return cmp;
  }
}
