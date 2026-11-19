// Copyright 2022 Google LLC (behaviour ported from `firestore_index_value_writer.ts` and `index_byte_encoder.ts` of
// firebase-js-sdk)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// The index value encoding of the JS SDK, which the IndexedDB cache stores in `indexEntries`.
///
/// It is not the encoding of [FirestoreIndexValueWriter] (the Android SDK's, which the SQLite cache uses): the JS SDK
/// writes every number, type labels included, as an IEEE 754 double (`writeNumber`), the seconds of a timestamp as a
/// decimal string, a reference without a closing marker, and BSON timestamps and object ids in forms of its own. Index
/// entries written by either SDK on the same database are only usable by the other when the bytes are the same, so
/// this writer follows the JS one value by value, including its quirks (noted where they are).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/index/ordered_code_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/value_bounds.dart';

/// An encoder of one direction (`DirectionalIndexByteEncoder` of the JS SDK).
abstract class JsDirectionalIndexByteEncoder {
  void writeBytes(List<int> value);

  void writeString(String value);

  void writeNumber(double value);

  void writeInfinity();
}

/// `IndexByteEncoder` of the JS SDK: both directions write into one buffer.
class JsIndexByteEncoder {
  JsIndexByteEncoder() {
    _ascending = _JsAscending(_orderedCode);
    _descending = _JsDescending(_orderedCode);
  }

  final OrderedCodeWriter _orderedCode = OrderedCodeWriter();
  late final JsDirectionalIndexByteEncoder _ascending;
  late final JsDirectionalIndexByteEncoder _descending;

  /// Appends [encodedBytes] as they are.
  void seed(List<int> encodedBytes) => _orderedCode.seed(encodedBytes);

  /// As the JS SDK: every kind other than ascending writes descending.
  JsDirectionalIndexByteEncoder forKind(SegmentKind kind) =>
      kind == SegmentKind.ascending ? _ascending : _descending;

  Uint8List get encodedBytes => _orderedCode.encodedBytes();
}

class _JsAscending implements JsDirectionalIndexByteEncoder {
  _JsAscending(this._orderedCode);

  final OrderedCodeWriter _orderedCode;

  @override
  void writeBytes(List<int> value) => _orderedCode.writeBytesAscending(value);

  @override
  void writeString(String value) => _orderedCode.writeUtf8Ascending(value);

  @override
  void writeNumber(double value) => _orderedCode.writeNumberAscending(value);

  @override
  void writeInfinity() => _orderedCode.writeInfinityAscending();
}

class _JsDescending implements JsDirectionalIndexByteEncoder {
  _JsDescending(this._orderedCode);

  final OrderedCodeWriter _orderedCode;

  @override
  void writeBytes(List<int> value) => _orderedCode.writeBytesDescending(value);

  @override
  void writeString(String value) => _orderedCode.writeUtf8Descending(value);

  @override
  void writeNumber(double value) => _orderedCode.writeNumberDescending(value);

  @override
  void writeInfinity() => _orderedCode.writeInfinityDescending();
}

/// `FirestoreIndexValueWriter` of the JS SDK, over the values of this SDK: each value is written as the JS SDK writes
/// its proto form.
class JsIndexValueWriter {
  const JsIndexValueWriter._();

  static const JsIndexValueWriter instance = JsIndexValueWriter._();

  static const double _typeNull = 5;
  static const double _typeMinKey = 7;
  static const double _typeBoolean = 10;
  static const double _typeNan = 13;
  static const double _typeNumber = 15;
  static const double _typeTimestamp = 20;
  static const double _typeBsonTimestamp = 22;
  static const double _typeString = 25;
  static const double _typeBlob = 30;
  static const double _typeBsonBinary = 31;
  static const double _typeReference = 37;
  static const double _typeBsonObjectId = 43;
  static const double _typeGeoPoint = 45;
  static const double _typeRegex = 47;
  static const double _typeArray = 50;
  static const double _typeVector = 53;
  static const double _typeMap = 55;
  static const double _typeReferenceSegment = 60;
  static const double _typeMaxKey = 999;

  /// `Number.MAX_SAFE_INTEGER`, the label of the internal maximum value.
  static const double _typeInternalMax = 9007199254740991;

  static const double _notTruncated = 2;

  /// Writes [value] and the separator that ends a value (`writeIndexValue`).
  void writeIndexValue(
    FieldValue value,
    JsDirectionalIndexByteEncoder encoder,
  ) {
    _write(value, encoder);
    encoder.writeInfinity();
  }

  /// Writes the reference to the document [key] and the separator: the ordered document key of an index entry
  /// (`encodeDirectionalKey`).
  void writeDocumentKey(
    DocumentKey key,
    JsDirectionalIndexByteEncoder encoder,
  ) {
    _writeReference(key, encoder);
    encoder.writeInfinity();
  }

  void _write(FieldValue value, JsDirectionalIndexByteEncoder encoder) {
    if (value is NullValue) {
      encoder.writeNumber(_typeNull);
    } else if (value is BoolValue) {
      encoder
        ..writeNumber(_typeBoolean)
        ..writeNumber(value.value ? 1 : 0);
    } else if (value is IntegerValue) {
      // `normalizeNumber`: an int64 beyond 2^53 loses precision as in JS. On the web a -0.0 of the user is an `int`
      // (an IntegerValue of -0): the JS SDK has no integer -0, and writes 0.
      final double number = value.value.toDouble();
      encoder
        ..writeNumber(_typeNumber)
        ..writeNumber(number == 0 ? 0.0 : number);
    } else if (value is DoubleValue) {
      _writeDouble(value.value, encoder);
    } else if (value is Int32FieldValue) {
      encoder
        ..writeNumber(_typeNumber)
        ..writeNumber(value.intValue.toDouble());
    } else if (value is Decimal128FieldValue) {
      // `parseFloat` of the string.
      _writeDouble(
        double.tryParse(value.value.stringValue.trim()) ?? double.nan,
        encoder,
      );
    } else if (value is InternalMaxValue) {
      encoder.writeNumber(_typeInternalMax);
    } else if (value is MinKeyValue) {
      encoder.writeNumber(_typeMinKey);
    } else if (value is MaxKeyValue) {
      encoder.writeNumber(_typeMaxKey);
    } else if (value is BsonTimestampValue) {
      // The JS SDK writes the inner map `{seconds, increment}` (its comment: a JS number has 53 bits), without a
      // truncation marker.
      encoder
        ..writeNumber(_typeBsonTimestamp)
        ..writeNumber(_typeMap);
      _writeString('seconds', encoder);
      encoder
        ..writeNumber(_typeNumber)
        ..writeNumber(value.value.seconds.toDouble());
      _writeString('increment', encoder);
      encoder
        ..writeNumber(_typeNumber)
        ..writeNumber(value.value.increment.toDouble());
    } else if (value is BsonObjectIdValue) {
      // `normalizeByteString` of the hexadecimal string: the JS SDK decodes it as base64.
      encoder
        ..writeNumber(_typeBsonObjectId)
        ..writeBytes(_base64OrEmpty(value.value.value));
    } else if (value is RegexFieldValue) {
      encoder
        ..writeNumber(_typeRegex)
        ..writeString(value.value.pattern)
        ..writeString(value.value.options)
        ..writeNumber(_notTruncated);
    } else if (value is TimestampValue) {
      // The seconds as a decimal string, and as an empty string when they are 0 (`${seconds || ''}`).
      final int seconds = value.value.seconds;
      encoder
        ..writeNumber(_typeTimestamp)
        ..writeString(seconds == 0 ? '' : '$seconds')
        ..writeNumber(value.value.nanoseconds.toDouble());
    } else if (value is ServerTimestampValue) {
      // The map `{__type__, __local_write_time__[, __previous_value__]}` in the order the JS SDK builds it.
      encoder.writeNumber(_typeMap);
      _writeString('__type__', encoder);
      _writeString('server_timestamp', encoder);
      encoder.writeNumber(_notTruncated);
      _writeString('__local_write_time__', encoder);
      _write(TimestampValue.valueOf(value.localWriteTime), encoder);
      final FieldValue? previous = value.previousFieldValue;
      if (previous != null) {
        _writeString('__previous_value__', encoder);
        _write(previous, encoder);
      }
      encoder.writeNumber(_notTruncated);
    } else if (value is StringValue) {
      _writeString(value.value, encoder);
      encoder.writeNumber(_notTruncated);
    } else if (value is BlobValue) {
      final int subtype = value.value.subtype;
      if (subtype == 0) {
        encoder
          ..writeNumber(_typeBlob)
          ..writeBytes(value.value.bytes);
      } else {
        encoder
          ..writeNumber(_typeBsonBinary)
          ..writeBytes(<int>[subtype, ...value.value.bytes]);
      }
      encoder.writeNumber(_notTruncated);
    } else if (value is ReferenceValue) {
      _writeReference(value.key, encoder);
    } else if (value is GeoPointValue) {
      // `latitude || 0`: -0 and NaN are written as 0.
      encoder
        ..writeNumber(_typeGeoPoint)
        ..writeNumber(_orZero(value.value.latitude))
        ..writeNumber(_orZero(value.value.longitude));
    } else if (value is VectorFieldValue) {
      final List<double> vector = value.internalValue;
      encoder
        ..writeNumber(_typeVector)
        ..writeNumber(_typeNumber)
        ..writeNumber(vector.length.toDouble());
      _writeString('value', encoder);
      encoder.writeNumber(_typeArray);
      for (final double element in vector) {
        _writeDouble(element, encoder);
      }
      encoder.writeNumber(_notTruncated);
    } else if (value is ObjectValue) {
      encoder.writeNumber(_typeMap);
      for (final MapEntry<String, FieldValue> entry in _jsKeyOrder(value)) {
        _writeString(entry.key, encoder);
        _write(entry.value, encoder);
      }
      encoder.writeNumber(_notTruncated);
    } else if (value is ArrayValue) {
      encoder.writeNumber(_typeArray);
      for (final FieldValue element in value.internalValue) {
        _write(element, encoder);
      }
      encoder.writeNumber(_notTruncated);
    } else {
      throw ArgumentError('unknown index value type ${value.runtimeType}');
    }
  }

  void _writeString(String value, JsDirectionalIndexByteEncoder encoder) {
    encoder
      ..writeNumber(_typeString)
      ..writeString(value);
  }

  /// `writeIndexEntityRef`: the segments of the document path, without a closing marker.
  void _writeReference(DocumentKey key, JsDirectionalIndexByteEncoder encoder) {
    encoder.writeNumber(_typeReference);
    for (final String segment in key.path.segments) {
      encoder
        ..writeNumber(_typeReferenceSegment)
        ..writeString(segment);
    }
  }

  void _writeDouble(double value, JsDirectionalIndexByteEncoder encoder) {
    if (value.isNaN) {
      encoder.writeNumber(_typeNan);
    } else {
      encoder
        ..writeNumber(_typeNumber)
        // -0.0, 0 and 0.0 are all considered the same.
        ..writeNumber(value == 0 ? 0.0 : value);
    }
  }

  static double _orZero(double value) =>
      value == 0 || value.isNaN ? 0.0 : value;

  static List<int> _base64OrEmpty(String value) {
    try {
      return base64.decode(value);
    } on FormatException {
      return const <int>[];
    }
  }

  /// The entries of [value] in the order of `Object.keys` on the JS object of its fields: the keys that are array
  /// indexes ("0", "1", ...) first in numeric order, then the others in the order the object got them. For a stored
  /// document that is the order of its proto map ([ObjectValue.entriesInKeyOrder]): the backend keeps the order the
  /// writer gave, the JS SDK the order of the user's object, this SDK the sorted order. A value made from the user's
  /// data (a query value) or built field by field has its keys sorted.
  ///
  /// PORTING NOTE: so a map value whose keys the JS SDK wrote in another order than sorted gets an entry that an
  /// equality query of this SDK (sorted) does not find, and the other way round; the JS SDK has the same dependence on
  /// key order between its own writes and queries.
  static Iterable<MapEntry<String, FieldValue>> _jsKeyOrder(ObjectValue value) {
    final List<MapEntry<String, FieldValue>> indexes =
        <MapEntry<String, FieldValue>>[];
    final List<MapEntry<String, FieldValue>> others =
        <MapEntry<String, FieldValue>>[];
    for (final MapEntry<String, FieldValue> entry in value.entriesInKeyOrder) {
      (_isArrayIndex(entry.key) ? indexes : others).add(entry);
    }
    if (indexes.isEmpty) {
      return others;
    }
    indexes.sort(
      (MapEntry<String, FieldValue> a, MapEntry<String, FieldValue> b) =>
          int.parse(a.key).compareTo(int.parse(b.key)),
    );
    return <MapEntry<String, FieldValue>>[...indexes, ...others];
  }

  /// Whether [key] is a canonical array index of JS: "0", or digits without a leading zero, below 2^32 - 1.
  static bool _isArrayIndex(String key) {
    if (key.isEmpty || key.length > 10) {
      return false;
    }
    for (int i = 0; i < key.length; i++) {
      final int c = key.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        return false;
      }
    }
    if (key.length > 1 && key.codeUnitAt(0) == 0x30) {
      return false;
    }
    return int.parse(key) < 4294967295;
  }
}
