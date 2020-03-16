// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

library field_value;

import 'dart:math';

import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';

part 'array_value.dart';
part 'blob_value.dart';
part 'bool_value.dart';
part 'double_value.dart';
part 'geo_point_value.dart';
part 'integer_value.dart';
part 'null_value.dart';
part 'number_value.dart';
part 'object_value.dart';
part 'reference_value.dart';
part 'server_timestamp_value.dart';
part 'string_value.dart';
part 'timestamp_value.dart';

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
