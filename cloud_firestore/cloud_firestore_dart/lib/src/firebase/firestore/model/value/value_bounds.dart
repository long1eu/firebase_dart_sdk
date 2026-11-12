import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_object_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/bson_timestamp.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/geo_point.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/database_id.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/regex_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// The value that sorts after every other value, used as the upper bound of
/// an index range that has no upper bound. Port of `Values.INTERNAL_MAX_VALUE`
/// (a map with `__type__: __max__` upstream). It never leaves the SDK: it is
/// not part of documents and is not sent to the backend.
class InternalMaxValue extends FieldValue {
  const InternalMaxValue._();

  static const InternalMaxValue instance = InternalMaxValue._();

  /// After [FieldValue.typeOrderMaxKey].
  @override
  int get typeOrder => 0x7fffffff;

  @override
  Object? get value => null;

  @override
  int compareTo(FieldValue other) {
    return other is InternalMaxValue ? 0 : defaultCompareTo(other);
  }

  @override
  bool operator ==(Object other) => other is InternalMaxValue;

  @override
  int get hashCode => 0x6d6178;

  @override
  String toString() => '{__type__:__max__}';
}

/// The bounds of the value types, used to turn the filters of a target into
/// ranges of an index. Port of the bound helpers of `Values` of the Android
/// SDK.
// ignore: avoid_classes_with_only_static_members
class ValueBounds {
  /// The value that sorts before every other value (`INTERNAL_MIN_VALUE`).
  static final FieldValue internalMinValue = NullValue.nullValue();

  /// The value that sorts after every other value (`INTERNAL_MAX_VALUE`).
  static const FieldValue internalMaxValue = InternalMaxValue.instance;

  static final FieldValue _minKey = MinKeyValue.instance();
  static final FieldValue _maxKey = MaxKeyValue.instance();
  static final FieldValue _minBoolean = BoolValue.valueOf(false);
  static final FieldValue _minNumber = DoubleValue.valueOf(double.nan);

  /// PORTING NOTE: upstream uses `Long.MIN_VALUE` seconds; this is the
  /// earliest timestamp the port's [Timestamp] can hold.
  static final FieldValue _minTimestamp =
      TimestampValue.valueOf(const Timestamp(-62135596800, 0));
  static final FieldValue _minBsonTimestamp =
      BsonTimestampValue(BsonTimestamp(0, 0));
  static final FieldValue _minString = StringValue.valueOf('');
  static final FieldValue _minBytes = BlobValue.valueOf(Blob(Uint8List(0)));
  static final FieldValue _minReference = ReferenceValue.valueOf(
      DatabaseId.forDatabase('', ''), DocumentKey.empty());
  static const FieldValue _minBsonObjectId =
      BsonObjectIdValue(BsonObjectId(''));
  static final FieldValue _minGeoPoint =
      GeoPointValue.valueOf(const GeoPoint(-90, -180));
  static const FieldValue _minRegex = RegexFieldValue(RegexValue('', ''));
  static final FieldValue _minArray = ArrayValue.fromList(const <FieldValue>[]);
  static final FieldValue _minVector =
      VectorFieldValue.fromList(const <double>[]);
  static final FieldValue _minMap = ObjectValue.empty;

  /// Returns the lowest value for the type of [value] (inclusive).
  static FieldValue getLowerBound(FieldValue value) {
    if (value is NullValue) {
      return internalMinValue;
    } else if (value is MinKeyValue) {
      return _minKey;
    } else if (value is BoolValue) {
      return _minBoolean;
    } else if (value is NumberValue) {
      // Integers, doubles, 32-bit integers and 128-bit decimals.
      return _minNumber;
    } else if (value is TimestampValue) {
      return _minTimestamp;
    } else if (value is BsonTimestampValue) {
      return _minBsonTimestamp;
    } else if (value is StringValue) {
      return _minString;
    } else if (value is BlobValue) {
      // Regular blobs and BSON binary data.
      return _minBytes;
    } else if (value is ReferenceValue) {
      return _minReference;
    } else if (value is BsonObjectIdValue) {
      return _minBsonObjectId;
    } else if (value is GeoPointValue) {
      return _minGeoPoint;
    } else if (value is RegexFieldValue) {
      return _minRegex;
    } else if (value is ArrayValue) {
      return _minArray;
    } else if (value is VectorFieldValue) {
      return _minVector;
    } else if (value is MaxKeyValue) {
      return _maxKey;
    } else if (value is ObjectValue || value is ServerTimestampValue) {
      // A pending server timestamp is a map upstream.
      return _minMap;
    }
    throw ArgumentError('Unknown value type: ${value.runtimeType}');
  }

  /// Returns the largest value for the type of [value] (exclusive): the lowest
  /// value of the type that sorts next.
  static FieldValue getUpperBound(FieldValue value) {
    if (value is NullValue) {
      return _minKey;
    } else if (value is MinKeyValue) {
      return _minBoolean;
    } else if (value is BoolValue) {
      return _minNumber;
    } else if (value is NumberValue) {
      return _minTimestamp;
    } else if (value is TimestampValue) {
      return _minBsonTimestamp;
    } else if (value is BsonTimestampValue) {
      return _minString;
    } else if (value is StringValue) {
      return _minBytes;
    } else if (value is BlobValue) {
      return _minReference;
    } else if (value is ReferenceValue) {
      return _minBsonObjectId;
    } else if (value is BsonObjectIdValue) {
      return _minGeoPoint;
    } else if (value is GeoPointValue) {
      return _minRegex;
    } else if (value is RegexFieldValue) {
      return _minArray;
    } else if (value is ArrayValue) {
      return _minVector;
    } else if (value is VectorFieldValue) {
      return _minMap;
    } else if (value is MaxKeyValue) {
      return internalMaxValue;
    } else if (value is ObjectValue || value is ServerTimestampValue) {
      return _maxKey;
    }
    throw ArgumentError('Unknown value type: ${value.runtimeType}');
  }

  /// Compares two lower bounds: for equal values the inclusive bound is the
  /// lower one.
  static int lowerBoundCompare(FieldValue left, bool leftInclusive,
      FieldValue right, bool rightInclusive) {
    final int cmp = left.compareTo(right);
    if (cmp != 0) {
      return cmp;
    }

    if (leftInclusive && !rightInclusive) {
      return -1;
    } else if (!leftInclusive && rightInclusive) {
      return 1;
    }

    return 0;
  }

  /// Compares two upper bounds: for equal values the inclusive bound is the
  /// higher one.
  static int upperBoundCompare(FieldValue left, bool leftInclusive,
      FieldValue right, bool rightInclusive) {
    final int cmp = left.compareTo(right);
    if (cmp != 0) {
      return cmp;
    }

    if (leftInclusive && !rightInclusive) {
      return 1;
    } else if (!leftInclusive && rightInclusive) {
      return -1;
    }

    return 0;
  }
}
