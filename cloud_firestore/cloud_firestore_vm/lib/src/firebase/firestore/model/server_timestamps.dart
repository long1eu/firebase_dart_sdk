// File created by
// Lung Razvan <long1eu>
// on 16/01/2021

import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';
import 'package:cloud_firestore_vm/src/proto/google/protobuf/timestamp.pb.dart' as p;
import 'package:fixnum/fixnum.dart';

/// Methods for manipulating locally-applied Server Timestamps.
///
/// Server Timestamps are backed by [MapValue]s that contain an internal field `__type__` with a
/// value of `server_timestamp`. The previous value and local write time are stored in its
/// `__previous_value__` and `__local_write_time__` fields respectively.
///
/// Notes:
/// * [ServerTimestamp] Values are created as the result of applying a transform. They can only exist
///     in the local view of a document. Therefore they do not need to be parsed or serialized.
/// * When evaluated locally (e.g. via [DocumentSnapshot] data), they evaluate to null.
/// * They sort after all [Timestamp] Values. With respect to other [ServerTimestamp] Values, they sort
///     by their localWriteTime.
class ServerTimestamps {
  ServerTimestamps._();

  static const String _kServerTimestampSentinel = 'server_timestamp';
  static const String _kTypeKey = '__type__';
  static const String _kPreviousValueKey = '__previous_value__';
  static const String _kLocalWriteTimeKey = '__local_write_time__';

  static bool isServerTimestamp(Value value) {
    final Value type = value == null ? null : value.mapValue.fields[_kTypeKey];
    return type != null && _kServerTimestampSentinel == type.stringValue;
  }

  static Value valueOf(Timestamp localWriteTime, Value previousValue) {
    final Value encodedType = Value(stringValue: _kServerTimestampSentinel);
    final Value encodeWriteTime = Value(
      timestampValue: p.Timestamp(
        seconds: Int64(localWriteTime.seconds),
        nanos: localWriteTime.nanoseconds,
      ),
    );

    final MapValue mapRepresentation =
        MapValue(fields: <String, Value>{_kTypeKey: encodedType, _kLocalWriteTimeKey: encodeWriteTime});

    if (previousValue != null) {
      mapRepresentation.fields[_kPreviousValueKey] = previousValue;
    }

    return Value(mapValue: mapRepresentation);
  }

  /// Returns the value of the field before this [ServerTimestamp] was set.
  ///
  /// Preserving the previous values allows the user to display the last resoled value until the
  /// backend responds with the timestamp [DocumentSnapshot.ServerTimestampBehavior].
  static Value getPreviousValue(Value serverTimestampValue) {
    final Value previousValue = serverTimestampValue.mapValue.fields[_kPreviousValueKey];
    if (isServerTimestamp(previousValue)) {
      return getPreviousValue(previousValue);
    }
    return previousValue;
  }

  static p.Timestamp getLocalWriteTime(Value serverTimestampValue) {
    final Value value = serverTimestampValue.mapValue.fields[_kLocalWriteTimeKey];
    if (value == null) {
      throw ArgumentError('Value should never be null in this case.');
    }
    return value.timestampValue;
  }
}
