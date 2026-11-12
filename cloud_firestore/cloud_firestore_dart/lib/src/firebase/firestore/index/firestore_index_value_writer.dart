import 'dart:convert';

import 'package:cloud_firestore_dart/src/firebase/firestore/blob.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/index/index_byte_encoder.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/resource_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Firestore index value writer. Port of `FirestoreIndexValueWriter` of the
/// Android SDK.
///
/// PORTING NOTE: upstream encodes `Value` protos, this port encodes its
/// [FieldValue] model. Differences that follow from that:
///   * A [ReferenceValue] holds a document key, so its segments are written
///     directly (upstream skips the five `projects/p/databases/d/documents`
///     segments of the resource name).
///   * A BSON timestamp is written as two numbers (seconds, increment)
///     instead of one packed signed long, see [_writeIndexValueAux].
///   * A reference ends with a truncation marker, which upstream does not
///     write: see [_writeIndexEntityRef]. The index entries are only read by
///     this SDK, so the different bytes are not a compatibility concern.
///   * A [VectorFieldValue] is its own type, written the way upstream writes
///     the `{__type__: __vector__, value: [...]}` map.
///   * A [ServerTimestampValue] (a pending local write) is written as the map
///     upstream stores for it, with the keys in sorted order.
///   * Map entries are written in the order of [ObjectValue], which is sorted
///     by key. The encoding is only compared with other encodings made by
///     this writer, so only its consistency matters.
///   * The BSON types are their own [FieldValue] classes (upstream detects
///     them from the shape of a map), and a blob carries its BSON subtype.
///   * The internal max value of upstream (a map with `__type__: __max__`) is
///     [InternalMaxValue].
class FirestoreIndexValueWriter {
  // Note: This file is copied from the backend. Code that is not used by
  // Firestore was removed. Code that has different behavior was modified.

  const FirestoreIndexValueWriter._();

  static const int indexTypeNull = 5;
  static const int indexTypeMinKey = 7;
  static const int indexTypeBoolean = 10;
  static const int indexTypeNan = 13;
  static const int indexTypeNumber = 15;
  static const int indexTypeTimestamp = 20;
  static const int indexTypeBsonTimestamp = 22;
  static const int indexTypeString = 25;
  static const int indexTypeBlob = 30;
  static const int indexTypeBsonBinary = 31;
  static const int indexTypeReference = 37;
  static const int indexTypeBsonObjectId = 43;
  static const int indexTypeGeopoint = 45;
  static const int indexTypeRegex = 47;
  static const int indexTypeArray = 50;
  static const int indexTypeVector = 53;
  static const int indexTypeMap = 55;
  static const int indexTypeReferenceSegment = 60;
  static const int indexTypeMaxKey = 999;

  /// The label of the internal max value, which sorts after every value
  /// (`Integer.MAX_VALUE` upstream).
  static const int indexTypeMax = 0x7fffffff;

  /// A terminator that indicates that a truncatable value was not truncated.
  /// This must be smaller than all other type labels.
  static const int notTruncated = 2;

  /// The key of the vector values in the map form of a vector.
  static const String _vectorMapVectorsKey = 'value';

  static const String _serverTimestampTypeKey = '__type__';
  static const String _serverTimestampSentinel = 'server_timestamp';
  static const String _serverTimestampLocalWriteTimeKey =
      '__local_write_time__';
  static const String _serverTimestampPreviousValueKey = '__previous_value__';

  static const FirestoreIndexValueWriter instance =
      FirestoreIndexValueWriter._();

  /// Writes an index value.
  void writeIndexValue(FieldValue value, DirectionalIndexByteEncoder encoder) {
    _writeIndexValueAux(value, encoder);
    // Write separator to split index values (see
    // go/firestore-storage-format#encodings).
    encoder.writeInfinity();
  }

  /// Writes the value that sorts after all other values (the upper bound of
  /// an open range).
  void writeMaxValue(DirectionalIndexByteEncoder encoder) {
    _writeValueTypeLabel(encoder, indexTypeMax);
    encoder.writeInfinity();
  }

  void _writeIndexValueAux(
      FieldValue indexValue, DirectionalIndexByteEncoder encoder) {
    if (indexValue is NullValue) {
      _writeValueTypeLabel(encoder, indexTypeNull);
    } else if (indexValue is BoolValue) {
      _writeValueTypeLabel(encoder, indexTypeBoolean);
      encoder.writeLong(indexValue.value ? 1 : 0);
    } else if (indexValue is DoubleValue) {
      _writeIndexDouble(indexValue.value, encoder);
    } else if (indexValue is IntegerValue) {
      _writeValueTypeLabel(encoder, indexTypeNumber);
      // Double and long sort the same
      encoder.writeDouble(indexValue.value.toDouble());
    } else if (indexValue is Int32FieldValue) {
      _writeValueTypeLabel(encoder, indexTypeNumber);
      // Double and Int32 sort the same
      encoder.writeDouble(indexValue.value.value.toDouble());
    } else if (indexValue is Decimal128FieldValue) {
      // Double and Decimal128 sort the same
      // Decimal128 is written as double with precision lost
      _writeIndexDouble(double.parse(indexValue.value.stringValue), encoder);
    } else if (indexValue is InternalMaxValue) {
      _writeValueTypeLabel(encoder, indexTypeMax);
    } else if (indexValue is MinKeyValue) {
      _writeValueTypeLabel(encoder, indexTypeMinKey);
    } else if (indexValue is MaxKeyValue) {
      _writeValueTypeLabel(encoder, indexTypeMaxKey);
    } else if (indexValue is BsonTimestampValue) {
      _writeValueTypeLabel(encoder, indexTypeBsonTimestamp);
      // PORTING NOTE: not upstream, which packs the seconds into the upper and
      // the increment into the lower 32 bits of one signed 64-bit long. That
      // long is negative for seconds >= 2^31 (the year 2038), so such
      // timestamps sort before all the others in the index and range scans
      // return other documents than a collection scan. Both parts are
      // unsigned 32-bit numbers: written as two longs they sort correctly.
      encoder
        ..writeLong(indexValue.value.seconds)
        ..writeLong(indexValue.value.increment);
    } else if (indexValue is BsonObjectIdValue) {
      _writeValueTypeLabel(encoder, indexTypeBsonObjectId);
      encoder.writeBytes(utf8.encode(indexValue.value.value));
    } else if (indexValue is RegexFieldValue) {
      _writeValueTypeLabel(encoder, indexTypeRegex);
      encoder
        ..writeString(indexValue.value.pattern)
        ..writeString(indexValue.value.options);
      _writeTruncationMarker(encoder);
    } else if (indexValue is TimestampValue) {
      _writeIndexTimestamp(indexValue.value, encoder);
    } else if (indexValue is ServerTimestampValue) {
      _writeIndexServerTimestamp(indexValue, encoder);
    } else if (indexValue is StringValue) {
      _writeIndexString(indexValue.value, encoder);
      _writeTruncationMarker(encoder);
    } else if (indexValue is BlobValue) {
      _writeIndexBlob(indexValue.value, encoder);
      _writeTruncationMarker(encoder);
    } else if (indexValue is ReferenceValue) {
      _writeIndexEntityRef(indexValue.key.path, encoder);
    } else if (indexValue is GeoPointValue) {
      _writeValueTypeLabel(encoder, indexTypeGeopoint);
      encoder
        ..writeDouble(indexValue.value.latitude)
        ..writeDouble(indexValue.value.longitude);
    } else if (indexValue is VectorFieldValue) {
      _writeIndexVector(indexValue.internalValue, encoder);
    } else if (indexValue is ObjectValue) {
      _writeValueTypeLabel(encoder, indexTypeMap);
      for (final MapEntry<String, FieldValue> entry
          in indexValue.internalValue) {
        _writeIndexString(entry.key, encoder);
        _writeIndexValueAux(entry.value, encoder);
      }
      _writeTruncationMarker(encoder);
    } else if (indexValue is ArrayValue) {
      _writeValueTypeLabel(encoder, indexTypeArray);
      for (final FieldValue element in indexValue.internalValue) {
        _writeIndexValueAux(element, encoder);
      }
      _writeTruncationMarker(encoder);
    } else {
      throw ArgumentError('unknown index value type ${indexValue.runtimeType}');
    }
  }

  void _writeIndexString(
      String stringIndexValue, DirectionalIndexByteEncoder encoder) {
    _writeValueTypeLabel(encoder, indexTypeString);
    encoder.writeString(stringIndexValue);
  }

  /// A blob of subtype 0 is written like a regular blob; BSON binary data of
  /// another subtype has its own label and the subtype as its first byte.
  void _writeIndexBlob(Blob blob, DirectionalIndexByteEncoder encoder) {
    if (blob.subtype == 0) {
      _writeValueTypeLabel(encoder, indexTypeBlob);
      encoder.writeBytes(blob.bytes);
    } else {
      _writeValueTypeLabel(encoder, indexTypeBsonBinary);
      encoder.writeBytes(<int>[blob.subtype, ...blob.bytes]);
    }
  }

  void _writeIndexDouble(double number, DirectionalIndexByteEncoder encoder) {
    if (number.isNaN) {
      _writeValueTypeLabel(encoder, indexTypeNan);
      return;
    }
    _writeValueTypeLabel(encoder, indexTypeNumber);
    if (number == 0.0) {
      // -0.0, 0 and 0.0 are all considered the same
      encoder.writeDouble(0.0);
    } else {
      encoder.writeDouble(number);
    }
  }

  void _writeIndexTimestamp(
      Timestamp timestamp, DirectionalIndexByteEncoder encoder) {
    _writeValueTypeLabel(encoder, indexTypeTimestamp);
    encoder
      ..writeLong(timestamp.seconds)
      ..writeLong(timestamp.nanoseconds);
  }

  /// Writes a pending server timestamp as the map upstream keeps for it:
  /// `{__local_write_time__, __previous_value__, __type__}`.
  void _writeIndexServerTimestamp(
      ServerTimestampValue value, DirectionalIndexByteEncoder encoder) {
    _writeValueTypeLabel(encoder, indexTypeMap);
    _writeIndexString(_serverTimestampLocalWriteTimeKey, encoder);
    _writeIndexTimestamp(value.localWriteTime, encoder);
    final FieldValue? previousValue = value.previousFieldValue;
    if (previousValue != null) {
      _writeIndexString(_serverTimestampPreviousValueKey, encoder);
      _writeIndexValueAux(previousValue, encoder);
    }
    _writeIndexString(_serverTimestampTypeKey, encoder);
    // The sentinel is a string value, the map is a map value: both end with
    // a truncation marker.
    _writeIndexString(_serverTimestampSentinel, encoder);
    _writeTruncationMarker(encoder);
    _writeTruncationMarker(encoder);
  }

  void _writeIndexVector(
      List<double> vector, DirectionalIndexByteEncoder encoder) {
    _writeValueTypeLabel(encoder, indexTypeVector);

    // Vectors sort first by length
    _writeValueTypeLabel(encoder, indexTypeNumber);
    encoder.writeLong(vector.length);

    // Vectors then sort by position value
    _writeIndexString(_vectorMapVectorsKey, encoder);
    _writeValueTypeLabel(encoder, indexTypeArray);
    for (final double element in vector) {
      _writeIndexDouble(element, encoder);
    }
    _writeTruncationMarker(encoder);
  }

  void _writeIndexEntityRef(
      ResourcePath path, DirectionalIndexByteEncoder encoder) {
    _writeValueTypeLabel(encoder, indexTypeReference);
    for (int index = 0; index < path.length; ++index) {
      _writeValueTypeLabel(encoder, indexTypeReferenceSegment);
      encoder.writeString(path.getSegment(index));
    }
    // PORTING NOTE: not upstream. Without a terminator the value separator
    // (0xffff ascending) follows the last segment and sorts after the segment
    // label of a longer reference, so `a/b` sorts after `a/b/c/d` and the
    // lowest reference (no segments) after every reference. Index scans for
    // `<`, `<=`, `>`, `>=`, cursors and limits on reference fields then return
    // other documents than a collection scan. The marker is smaller than
    // every label, which gives references the order of their document keys.
    _writeTruncationMarker(encoder);
  }

  void _writeValueTypeLabel(
      DirectionalIndexByteEncoder encoder, int typeOrder) {
    encoder.writeLong(typeOrder);
  }

  void _writeTruncationMarker(DirectionalIndexByteEncoder encoder) {
    // While the SDK does not implement truncation, the truncation marker is
    // used to terminate all variable length values (which are strings, bytes,
    // references, arrays and maps).
    encoder.writeLong(notTruncated);
  }
}
