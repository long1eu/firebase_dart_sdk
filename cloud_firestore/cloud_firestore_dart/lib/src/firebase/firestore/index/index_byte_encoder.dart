import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/index/ordered_code_writer.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_index.dart';
import 'package:fixnum/fixnum.dart';

/// An index value encoder for one direction (ascending or descending). Port of
/// `DirectionalIndexByteEncoder` of the Android SDK.
abstract class DirectionalIndexByteEncoder {
  // Note: This code is copied from the backend. Code that is not used by
  // Firestore was removed.

  void writeBytes(List<int> val);

  void writeString(String val);

  /// Writes a signed 64-bit integer. An [int] is enough for everything the
  /// SDK writes (type labels, lengths, seconds and nanoseconds); use
  /// [writeInt64] for values that need all 64 bits on the web.
  void writeLong(int val) => writeInt64(Int64(val));

  void writeInt64(Int64 val);

  void writeDouble(double val);

  void writeInfinity();
}

/// Implements [DirectionalIndexByteEncoder] using [OrderedCodeWriter] for the
/// actual encoding. Both directions write into the same buffer, so that the
/// segments of one index entry can have different directions.
class IndexByteEncoder {
  IndexByteEncoder() {
    _ascending = _AscendingIndexByteEncoder(_orderedCode);
    _descending = _DescendingIndexByteEncoder(_orderedCode);
  }

  final OrderedCodeWriter _orderedCode = OrderedCodeWriter();
  late final DirectionalIndexByteEncoder _ascending;
  late final DirectionalIndexByteEncoder _descending;

  /// Appends [encodedBytes] as they are.
  void seed(List<int> encodedBytes) => _orderedCode.seed(encodedBytes);

  DirectionalIndexByteEncoder forKind(SegmentKind kind) {
    return kind == SegmentKind.descending ? _descending : _ascending;
  }

  Uint8List get encodedBytes => _orderedCode.encodedBytes();

  void reset() => _orderedCode.reset();
}

class _AscendingIndexByteEncoder extends DirectionalIndexByteEncoder {
  _AscendingIndexByteEncoder(this._orderedCode);

  final OrderedCodeWriter _orderedCode;

  @override
  void writeBytes(List<int> val) => _orderedCode.writeBytesAscending(val);

  @override
  void writeString(String val) => _orderedCode.writeUtf8Ascending(val);

  @override
  void writeInt64(Int64 val) => _orderedCode.writeSignedLongAscending(val);

  @override
  void writeDouble(double val) => _orderedCode.writeDoubleAscending(val);

  @override
  void writeInfinity() => _orderedCode.writeInfinityAscending();
}

class _DescendingIndexByteEncoder extends DirectionalIndexByteEncoder {
  _DescendingIndexByteEncoder(this._orderedCode);

  final OrderedCodeWriter _orderedCode;

  @override
  void writeBytes(List<int> val) => _orderedCode.writeBytesDescending(val);

  @override
  void writeString(String val) => _orderedCode.writeUtf8Descending(val);

  @override
  void writeInt64(Int64 val) => _orderedCode.writeSignedLongDescending(val);

  @override
  void writeDouble(double val) => _orderedCode.writeDoubleDescending(val);

  @override
  void writeInfinity() => _orderedCode.writeInfinityDescending();
}
