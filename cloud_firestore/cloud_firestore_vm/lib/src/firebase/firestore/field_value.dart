// File created by
// Lung Razvan <long1eu>
// on 20/09/2018



/// Sentinel values that can be used when writing document fields with [set] or [update].
abstract class FieldValue {
  const FieldValue._(this.elements);

  /// Returns a sentinel for use with update() to mark a field for deletion.
  factory FieldValue.delete() => _deleteInstance;

  /// Returns a sentinel for use with set() or update() to include a server-generated timestamp in
  /// the written data.
  factory FieldValue.serverTimestamp() => _serverTimestampInstance;

  /// Returns a special value that can be used with set() or update() that tells the server to union
  /// the given elements with any array value that already exists on the server. Each specified
  /// element that doesn't already exist in the array will be added to the end. If the field being
  /// modified is not already an array it will be overwritten with an array containing exactly the
  /// specified elements. The [elements] to union into the array. Returns the [FieldValue] sentinel
  /// for use in a call to set() or update().
  factory FieldValue.arrayUnion(List<Object> elements) {
    return _ArrayUnionFieldValue._(elements);
  }

  /// Returns a special value that can be used with set() or update() that tells the server to
  /// remove the given elements from any array value that already exists on the server. All
  /// instances of each element specified will be removed from the array. If the field being
  /// modified is not already an array it will be overwritten with an empty array.
  ///
  /// The [elements] to remove from the array. Returns the [FieldValue] sentinel for use in a call
  /// to set() or update().
  factory FieldValue.arrayRemove(List<Object> elements) {
    return _ArrayRemoveFieldValue._(elements);
  }

  final List<Object> elements;

  /// Returns the method name (e.g. 'FieldValue.delete') that was used to create this FieldValue
  /// instance, for use in error messages, etc.
  String get methodName;

  bool get isDelete => this is _DeleteFieldValue;

  bool get isServerTimestamp => this is _ServerTimestampFieldValue;

  bool get isArrayUnion => this is _ArrayUnionFieldValue;

  bool get isArrayRemove => this is _ArrayRemoveFieldValue;

  static const _DeleteFieldValue _deleteInstance = _DeleteFieldValue._();

  static const _ServerTimestampFieldValue _serverTimestampInstance =
      _ServerTimestampFieldValue._();
}

/// FieldValue class for field deletes.
class _DeleteFieldValue extends FieldValue {
  const _DeleteFieldValue._() : super._(null);

  @override
  String get methodName => 'FieldValue.delete';
}

/// FieldValue class for server timestamps.
class _ServerTimestampFieldValue extends FieldValue {
  const _ServerTimestampFieldValue._() : super._(null);

  @override
  String get methodName => 'FieldValue.serverTimestamp';
}

/// FieldValue class for arrayUnion() transforms.
class _ArrayUnionFieldValue extends FieldValue {
  const _ArrayUnionFieldValue._(List<Object> elements) : super._(elements);

  @override
  String get methodName => 'FieldValue.arrayUnion';
}

/// FieldValue class for arrayRemove() transforms.
class _ArrayRemoveFieldValue extends FieldValue {
  const _ArrayRemoveFieldValue._(List<Object> elements) : super._(elements);

  @override
  String get methodName => 'FieldValue.arrayRemove';
}
