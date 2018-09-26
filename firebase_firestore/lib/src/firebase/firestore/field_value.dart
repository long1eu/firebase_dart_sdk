// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:firebase_common/firebase_common.dart';

/// Sentinel values that can be used when writing document fields with [set()] or
/// [update()].
@publicApi
abstract class FieldValue {
  const FieldValue._();

  /// Returns a special value that can be used with set() or update() that tells
  /// the server to union the given elements with any array value that already
  /// exists on the server. Each specified element that doesn't already exist in
  /// the array will be added to the end. If the field being modified is not
  /// already an array it will be overwritten with an array containing exactly
  /// the specified elements.
  /// The [elements] to union into the array. Returns the [FieldValue] sentinel
  /// for use in a call to set() or update().
  @publicApi
  factory FieldValue.arrayUnion(List<Object> elements) {
    return ArrayUnionFieldValue._(elements);
  }

  /// Returns a special value that can be used with set() or update() that tells
  /// the server to remove the given elements from any array value that already
  /// exists on the server. All instances of each element specified will be
  /// removed from the array. If the field being modified is not already an
  /// array it will be overwritten with an empty array.
  ///
  /// The [elements] to remove from the array. Returns the [FieldValue] sentinel
  /// for use in a call to set() or update().
  @publicApi
  factory FieldValue.arrayRemove(List<Object> elements) {
    return ArrayRemoveFieldValue._(elements);
  }

  /// Returns the method name (e.g. "FieldValue.delete") that was used to create
  /// this FieldValue instance, for use in error messages, etc.
  String get methodName;

  static const DeleteFieldValue _deleteInstance = DeleteFieldValue._();

  static const ServerTimestampFieldValue _serverTimestampInstance =
      ServerTimestampFieldValue._();

  /// Returns a sentinel for use with update() to mark a field for deletion.
  @publicApi
  static FieldValue get delete => _deleteInstance;

  /// Returns a sentinel for use with set() or update() to include a
  /// server-generated timestamp in the written data.
  @publicApi
  static FieldValue get serverTimestamp => _serverTimestampInstance;
}

/* FieldValue class for field deletes. */
class DeleteFieldValue extends FieldValue {
  const DeleteFieldValue._() : super._();

  @override
  String get methodName => 'FieldValue.delete';
}

/* FieldValue class for server timestamps. */
class ServerTimestampFieldValue extends FieldValue {
  const ServerTimestampFieldValue._() : super._();

  @override
  String get methodName => 'FieldValue.serverTimestamp';
}

/* FieldValue class for arrayUnion() transforms. */
class ArrayUnionFieldValue extends FieldValue {
  const ArrayUnionFieldValue._(this.elements) : super._();
  final List<Object> elements;

  @override
  String get methodName => 'FieldValue.arrayUnion';
}

/* FieldValue class for arrayRemove() transforms. */
class ArrayRemoveFieldValue extends FieldValue {
  final List<Object> elements;

  const ArrayRemoveFieldValue._(this.elements) : super._();

  @override
  String get methodName => 'FieldValue.arrayRemove';
}
