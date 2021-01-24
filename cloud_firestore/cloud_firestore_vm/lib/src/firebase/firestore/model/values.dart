// File created by
// Lung Razvan <long1eu>
// on 16/01/2021

import 'dart:collection';
import 'dart:math' as math;

import 'package:cloud_firestore_vm/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/server_timestamps.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/util.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';
import 'package:cloud_firestore_vm/src/proto/google/protobuf/struct.pbenum.dart';
import 'package:cloud_firestore_vm/src/proto/google/protobuf/timestamp.pb.dart' as p;
import 'package:cloud_firestore_vm/src/proto/google/type/latlng.pb.dart' as p;
import 'package:fixnum/fixnum.dart';

final Value NAN_VALUE = Value(doubleValue: double.nan);
final Value NULL_VALUE = Value(nullValue: NullValue.NULL_VALUE);

/// The order of types in Firestore. This order is based on the backend's ordering, but modified to
/// support server timestamps.
const int TYPE_ORDER_NULL = 0;

const int TYPE_ORDER_bool = 1;
const int TYPE_ORDER_NUMBER = 2;
const int TYPE_ORDER_TIMESTAMP = 3;
const int TYPE_ORDER_SERVER_TIMESTAMP = 4;
const int TYPE_ORDER_STRING = 5;
const int TYPE_ORDER_BLOB = 6;
const int TYPE_ORDER_REFERENCE = 7;
const int TYPE_ORDER_GEOPOINT = 8;
const int TYPE_ORDER_ARRAY = 9;
const int TYPE_ORDER_MAP = 10;

/// Returns the backend's type order of the given Value type.
int typeOrder(Value value) {
  switch (value.whichValueType()) {
    case Value_ValueType.nullValue:
      return TYPE_ORDER_NULL;
    case Value_ValueType.booleanValue:
      return TYPE_ORDER_bool;
    case Value_ValueType.integerValue:
      return TYPE_ORDER_NUMBER;
    case Value_ValueType.doubleValue:
      return TYPE_ORDER_NUMBER;
    case Value_ValueType.timestampValue:
      return TYPE_ORDER_TIMESTAMP;
    case Value_ValueType.stringValue:
      return TYPE_ORDER_STRING;
    case Value_ValueType.bytesValue:
      return TYPE_ORDER_BLOB;
    case Value_ValueType.referenceValue:
      return TYPE_ORDER_REFERENCE;
    case Value_ValueType.geoPointValue:
      return TYPE_ORDER_GEOPOINT;
    case Value_ValueType.arrayValue:
      return TYPE_ORDER_ARRAY;
    case Value_ValueType.mapValue:
      if (ServerTimestamps.isServerTimestamp(value)) {
        return TYPE_ORDER_SERVER_TIMESTAMP;
      }
      return TYPE_ORDER_MAP;
    default:
      throw fail('Invalid value type: ${value.whichValueType()}');
  }
}

bool equals(Value left, Value right) {
  if (left == null && right == null) {
    return true;
  } else if (left == null || right == null) {
    return false;
  }

  final int leftType = typeOrder(left);
  final int rightType = typeOrder(right);
  if (leftType != rightType) {
    return false;
  }

  switch (leftType) {
    case TYPE_ORDER_NUMBER:
      return _numberEquals(left, right);
    case TYPE_ORDER_ARRAY:
      return _arrayEquals(left, right);
    case TYPE_ORDER_MAP:
      return _objectEquals(left, right);
    case TYPE_ORDER_SERVER_TIMESTAMP:
      return ServerTimestamps.getLocalWriteTime(left) == ServerTimestamps.getLocalWriteTime(right);
    default:
      return left == right;
  }
}

bool _numberEquals(Value left, Value right) {
  if (left.whichValueType() == Value_ValueType.integerValue && right.whichValueType() == Value_ValueType.integerValue) {
    return left.integerValue == right.integerValue;
  } else if (left.whichValueType() == Value_ValueType.doubleValue &&
      right.whichValueType() == Value_ValueType.doubleValue) {
    return left.doubleValue == right.doubleValue;
  }

  return false;
}

bool _arrayEquals(Value left, Value right) {
  final ArrayValue leftArray = left.arrayValue;
  final ArrayValue rightArray = right.arrayValue;

  if (leftArray.values.length != rightArray.values.length) {
    return false;
  }

  for (int i = 0; i < leftArray.values.length; ++i) {
    if (!equals(leftArray.values[i], rightArray.values[i])) {
      return false;
    }
  }

  return true;
}

bool _objectEquals(Value left, Value right) {
  final MapValue leftMap = left.mapValue;
  final MapValue rightMap = right.mapValue;

  if (leftMap.fields.length != rightMap.fields.length) {
    return false;
  }

  for (MapEntry<String, Value> entry in leftMap.fields.entries) {
    final Value otherEntry = rightMap.fields[entry.key];
    if (!equals(entry.value, otherEntry)) {
      return false;
    }
  }

  return true;
}

/// Returns true if the Value list contains the specified element.
bool contains(ArrayValue haystack, Value needle) {
  for (Value haystackElement in haystack.values) {
    if (equals(haystackElement, needle)) {
      return true;
    }
  }
  return false;
}

int compare(Value left, Value right) {
  final int leftType = typeOrder(left);
  final int rightType = typeOrder(right);

  if (leftType != rightType) {
    return leftType.compareTo(rightType);
  }

  switch (leftType) {
    case TYPE_ORDER_NULL:
      return 0;
    case TYPE_ORDER_bool:
      return compareBools(left.booleanValue, right.booleanValue);
    case TYPE_ORDER_NUMBER:
      return _compareNumbers(left, right);
    case TYPE_ORDER_TIMESTAMP:
      return _compareTimestamps(left.timestampValue, right.timestampValue);
    case TYPE_ORDER_SERVER_TIMESTAMP:
      return _compareTimestamps(ServerTimestamps.getLocalWriteTime(left), ServerTimestamps.getLocalWriteTime(right));
    case TYPE_ORDER_STRING:
      return left.stringValue.compareTo(right.stringValue);
    case TYPE_ORDER_BLOB:
      return compareBytes(left.bytesValue, right.bytesValue);
    case TYPE_ORDER_REFERENCE:
      return _compareReferences(left.referenceValue, right.referenceValue);
    case TYPE_ORDER_GEOPOINT:
      return _compareGeoPoints(left.geoPointValue, right.geoPointValue);
    case TYPE_ORDER_ARRAY:
      return _compareArrays(left.arrayValue, right.arrayValue);
    case TYPE_ORDER_MAP:
      return _compareMaps(left.mapValue, right.mapValue);
    default:
      throw fail('Invalid value type: $leftType');
  }
}

int _compareNumbers(Value left, Value right) {
  if (left.whichValueType() == Value_ValueType.doubleValue) {
    final double leftDouble = left.doubleValue;
    if (right.whichValueType() == Value_ValueType.doubleValue) {
      return leftDouble.compareTo(right.doubleValue);
    } else if (right.whichValueType() == Value_ValueType.integerValue) {
      return leftDouble.compareTo(right.integerValue.toInt());
    }
  } else if (left.whichValueType() == Value_ValueType.integerValue) {
    final Int64 leftInt = left.integerValue;
    if (right.whichValueType() == Value_ValueType.integerValue) {
      return leftInt.compareTo(right.integerValue);
    } else if (right.whichValueType() == Value_ValueType.doubleValue) {
      return -1 * right.doubleValue.compareTo(leftInt.toDouble());
    }
  }

  throw fail('Unexpected values: $left vs $right');
}

int _compareTimestamps(p.Timestamp left, p.Timestamp right) {
  final int cmp = left.seconds.compareTo(right.seconds);
  if (cmp != 0) {
    return cmp;
  }

  return left.nanos.compareTo(right.nanos);
}

int _compareReferences(String leftPath, String rightPath) {
  final List<String> leftSegments = leftPath.split('/');
  final List<String> rightSegments = rightPath.split('/');

  final int minLength = math.min(leftSegments.length, rightSegments.length);
  for (int i = 0; i < minLength; i++) {
    final int cmp = leftSegments[i].compareTo(rightSegments[i]);
    if (cmp != 0) {
      return cmp;
    }
  }

  return leftSegments.length.compareTo(rightSegments.length);
}

int _compareGeoPoints(p.LatLng left, p.LatLng right) {
  final int comparison = left.latitude.compareTo(right.latitude);
  if (comparison == 0) {
    return left.longitude.compareTo(right.longitude);
  }
  return comparison;
}

int _compareArrays(ArrayValue left, ArrayValue right) {
  final int minLength = math.min(left.values.length, right.values.length);
  for (int i = 0; i < minLength; i++) {
    final int cmp = compare(left.values[i], right.values[i]);
    if (cmp != 0) {
      return cmp;
    }
  }

  return left.values.length.compareTo(right.values.length);
}

int _compareMaps(MapValue left, MapValue right) {
  final Iterator<MapEntry<String, Value>> iterator1 = SplayTreeMap<String, Value>.of(left.fields).entries.iterator;
  final Iterator<MapEntry<String, Value>> iterator2 = SplayTreeMap<String, Value>.of(right.fields).entries.iterator;
  while (iterator1.moveNext() && iterator2.moveNext()) {
    final MapEntry<String, Value> entry1 = iterator1.current;
    final MapEntry<String, Value> entry2 = iterator2.current;
    final int keyCompare = entry1.key.compareTo(entry2.key);
    if (keyCompare != 0) {
      return keyCompare;
    }
    final int valueCompare = compare(entry1.value, entry2.value);
    if (valueCompare != 0) {
      return valueCompare;
    }
  }

  // Only equal if both iterators are exhausted.
  return compareBools(iterator1.moveNext(), iterator2.moveNext());
}

/// Generate the canonical ID for the provided field value (as used in Target serialization).
String canonicalId(Value value) {
  final StringBuffer buffer = StringBuffer();
  _canonifyValue(buffer, value);
  return buffer.toString();
}

void _canonifyValue(StringBuffer buffer, Value value) {
  switch (value.whichValueType()) {
    case Value_ValueType.nullValue:
      buffer.write('null');
      break;
    case Value_ValueType.booleanValue:
      buffer.write(value.booleanValue);
      break;
    case Value_ValueType.integerValue:
      buffer.write(value.integerValue);
      break;
    case Value_ValueType.doubleValue:
      buffer.write(value.doubleValue);
      break;
    case Value_ValueType.timestampValue:
      _canonifyTimestamp(buffer, value.timestampValue);
      break;
    case Value_ValueType.stringValue:
      buffer.write(value.stringValue);
      break;
    case Value_ValueType.bytesValue:
      buffer.write(toDebugString(value.bytesValue));
      break;
    case Value_ValueType.referenceValue:
      _canonifyReference(buffer, value);
      break;
    case Value_ValueType.geoPointValue:
      _canonifyGeoPoint(buffer, value.geoPointValue);
      break;
    case Value_ValueType.arrayValue:
      _canonifyArray(buffer, value.arrayValue);
      break;
    case Value_ValueType.mapValue:
      _canonifyObject(buffer, value.mapValue);
      break;
    default:
      throw fail('Invalid value type: ${value.whichValueType()}');
  }
}

void _canonifyTimestamp(StringBuffer buffer, p.Timestamp timestamp) {
  buffer.write('time(${timestamp.seconds},${timestamp.nanos})');
}

void _canonifyGeoPoint(StringBuffer buffer, p.LatLng latLng) {
  buffer.write('geo(${latLng.latitude},${latLng.longitude})');
}

void _canonifyReference(StringBuffer buffer, Value value) {
  hardAssert(isReferenceValue(value), 'Value should be a ReferenceValue');
  buffer.write(DocumentKey.fromName(value.referenceValue));
}

void _canonifyObject(StringBuffer buffer, MapValue mapValue) {
  // Even though MapValue are likely sorted correctly based on their insertion order (e.g. when
  // received from the backend), local modifications can bring elements out of order. We need to
  // re-sort the elements to ensure that canonical IDs are independent of insertion order.
  final List<String> keys = mapValue.fields.keys.toList()..sort();

  buffer.write('{');
  bool first = true;
  for (String key in keys) {
    if (!first) {
      buffer.write(',');
    } else {
      first = false;
    }
    buffer //
      ..write(key)
      ..write(':');
    _canonifyValue(buffer, mapValue.fields[key]);
  }
  buffer.write('}');
}

void _canonifyArray(StringBuffer buffer, ArrayValue arrayValue) {
  buffer.write('[');
  for (int i = 0; i < arrayValue.values.length; ++i) {
    _canonifyValue(buffer, arrayValue.values[i]);
    if (i != arrayValue.values.length - 1) {
      buffer.write(',');
    }
  }
  buffer.write(']');
}

/// Returns true if `value` is either a INTEGER_VALUE.
bool isInteger(Value value) {
  return value != null && value.whichValueType() == Value_ValueType.integerValue;
}

/// Returns true if `value` is either a DOUBLE_VALUE.
bool isDouble(Value value) {
  return value != null && value.whichValueType() == Value_ValueType.doubleValue;
}

/// Returns true if `value` is either a INTEGER_VALUE or a DOUBLE_VALUE.
bool isNumber(Value value) {
  return isInteger(value) || isDouble(value);
}

/// Returns true if `value` is an ARRAY_VALUE.
bool isArray(Value value) {
  return value != null && value.whichValueType() == Value_ValueType.arrayValue;
}

bool isReferenceValue(Value value) {
  return value != null && value.whichValueType() == Value_ValueType.referenceValue;
}

bool isNullValue(Value value) {
  return value != null && value.whichValueType() == Value_ValueType.nullValue;
}

bool isNanValue(Value value) {
  return value != null && value.doubleValue.isNaN;
}

bool isMapValue(Value value) {
  return value != null && value.whichValueType() == Value_ValueType.mapValue;
}

Value refValue(DatabaseId databaseId, DocumentKey key) {
  return Value(
    referenceValue: 'projects/${databaseId.projectId}/databases/${databaseId.databaseId}/documents/$key',
  );
}
