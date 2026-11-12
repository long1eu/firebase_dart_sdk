// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

library field_value;

import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/database_collection/database_collection.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/decimal128_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/int32_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/max_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/min_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/server_timestamp_behavior.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/exact_number.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';

part 'array_value.dart';
part 'blob_value.dart';
part 'bool_value.dart';
part 'bson_values.dart';
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
part 'vector_field_value.dart';

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

  // This order is the order of the backend. The numbers are only compared in
  // memory, they are never persisted.
  static const int typeOrderNull = 0;
  static const int typeOrderMinKey = 1;
  static const int typeOrderBool = 2;
  // All the numbers (64-bit integers, doubles, 32-bit integers and 128-bit
  // decimals) sort together by their numeric value.
  static const int typeOrderNumber = 3;
  static const int typeOrderTimestamp = 4;
  static const int typeOrderBsonTimestamp = 5;
  static const int typeOrderServerTimestamp = 6;
  static const int typeOrderString = 7;
  // Blobs with a subtype (BSON binary data) sort with the regular blobs.
  static const int typeOrderBlob = 8;
  static const int typeOrderReference = 9;
  static const int typeOrderBsonObjectId = 10;
  static const int typeOrderGeopoint = 11;
  static const int typeOrderRegex = 12;
  static const int typeOrderArray = 13;
  static const int typeOrderVector = 14;
  static const int typeOrderObject = 15;
  static const int typeOrderMaxKey = 16;

  int get typeOrder;

  /// Converts a [FieldValue] into the value that users will see in document snapshots using the
  /// default deserialization options.
  Object? get value;

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;

  @override
  int compareTo(FieldValue other);

  @override
  String toString() {
    final Object? val = value;
    return val == null ? 'null' : val.toString();
  }

  int defaultCompareTo(FieldValue other) {
    final int cmp = typeOrder.compareTo(other.typeOrder);
    hardAssert(
      cmp != 0,
      'Default compareTo should not be used for values of same type.',
    );
    return cmp;
  }
}
