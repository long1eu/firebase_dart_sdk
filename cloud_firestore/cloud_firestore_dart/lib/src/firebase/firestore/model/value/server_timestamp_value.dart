// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of 'field_value.dart';

/// Represents a locally-applied Server Timestamp.
///
/// Notes:
///   - ServerTimestampValue instances are created as the result of applying a transform. They can
///   only exist in the local view of a document. Therefore they do not need to be parsed or
///   serialized.
///   - When evaluated locally (e.g. via [DocumentSnapshot.ata]), they evaluate to null.
///   - They sort after all [TimestampValue]s. With respect to other [ServerTimestampValue]s, they
///   sort by their [localWriteTime].
class ServerTimestampValue extends FieldValue {
  /// Creates a pending server timestamp.
  ///
  /// Deeply nested server timestamp values are avoided because the
  /// intermediate "previous values" are never used:
  ///
  ///     previous: 42, add: t1, result: t1 -> 42
  ///     previous: t1, add: t2, result: t2 -> 42 (NOT t2 -> t1 -> 42)
  factory ServerTimestampValue(
    Timestamp localWriteTime,
    FieldValue? previousValue,
  ) {
    return ServerTimestampValue._(
      localWriteTime,
      previousValue is ServerTimestampValue
          ? previousValue._previousValue
          : previousValue,
    );
  }

  const ServerTimestampValue._(this.localWriteTime, this._previousValue);

  final Timestamp localWriteTime;
  final FieldValue? _previousValue;

  @override
  int get typeOrder => FieldValue.typeOrderServerTimestamp;

  @override
  Object? get value => null;

  /// Returns the value of the field before this ServerTimestamp was set.
  ///
  /// Preserving the previous values allows the user to display the last resoled
  /// value until the backend responds with the timestamp
  /// [ServerTimestampBehavior].
  /// The same value as [previousValue] but as the model [FieldValue], so that
  /// callers can convert it (references, timestamps, maps) like a regular value.
  FieldValue? get previousFieldValue => _previousValue;

  Object? get previousValue {
    return _previousValue?.value;
  }

  @override
  int compareTo(FieldValue other) {
    if (other is ServerTimestampValue) {
      return localWriteTime.compareTo(other.localWriteTime);
    } else {
      return defaultCompareTo(other);
    }
  }

  @override
  String toString() {
    return (ToStringHelper(ServerTimestampValue)
          ..add('localWriteTime', localWriteTime)
          ..add('previousValue', previousValue))
        .toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerTimestampValue &&
          runtimeType == other.runtimeType &&
          localWriteTime == other.localWriteTime &&
          _previousValue == other._previousValue;

  @override
  int get hashCode => localWriteTime.hashCode ^ _previousValue.hashCode;
}
