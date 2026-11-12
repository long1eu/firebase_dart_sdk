// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';

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
  factory FieldValue.arrayUnion(List<Object?> elements) {
    return _ArrayUnionFieldValue._(elements);
  }

  /// Returns a special value that can be used with set() or update() that tells the server to
  /// remove the given elements from any array value that already exists on the server. All
  /// instances of each element specified will be removed from the array. If the field being
  /// modified is not already an array it will be overwritten with an empty array.
  ///
  /// The [elements] to remove from the array. Returns the [FieldValue] sentinel for use in a call
  /// to set() or update().
  factory FieldValue.arrayRemove(List<Object?> elements) {
    return _ArrayRemoveFieldValue._(elements);
  }

  /// Returns a special value that can be used with set() or update() that tells
  /// the server to increment the field's current value by the given value.
  ///
  /// If the current value is an integer or a double, both the current and the
  /// given value will be interpreted as doubles and all arithmetic will follow
  /// IEEE 754 semantics. Otherwise, the transformation will set the field to
  /// the given value.
  factory FieldValue.increment(num l) {
    return _NumericIncrementFieldValue(l);
  }

  /// Returns a special value that can be used with set() or update() that tells
  /// the server to set the field to the minimum of its current value and the
  /// given value.
  ///
  /// If the current value is not a number, the field is set to the given value.
  /// If both are numbers they are compared numerically (NaN wins over any other
  /// number); the field keeps the type (integer or double) of the smaller
  /// operand, and keeps its current value and type if they are equivalent.
  factory FieldValue.minimum(num l) {
    return _NumericMinimumFieldValue(l);
  }

  /// Returns a special value that can be used with set() or update() that tells
  /// the server to set the field to the maximum of its current value and the
  /// given value.
  ///
  /// If the current value is not a number, the field is set to the given value.
  /// If both are numbers they are compared numerically (NaN wins over any other
  /// number); the field keeps the type (integer or double) of the larger
  /// operand, and keeps its current value and type if they are equivalent.
  factory FieldValue.maximum(num l) {
    return _NumericMaximumFieldValue(l);
  }

  /// Creates a new [VectorValue] constructed with a copy of the given list of doubles.
  ///
  /// Unlike the other factories this is a plain value, not a sentinel.
  static VectorValue vector(List<double> values) => VectorValue(values);

  final List<Object?> elements;

  /// Returns the method name (e.g. 'FieldValue.delete') that was used to create this FieldValue
  /// instance, for use in error messages, etc.
  String get methodName;

  bool get isDelete => this is _DeleteFieldValue;

  bool get isServerTimestamp => this is _ServerTimestampFieldValue;

  bool get isArrayUnion => this is _ArrayUnionFieldValue;

  bool get isArrayRemove => this is _ArrayRemoveFieldValue;

  bool get isIncrement => this is _NumericIncrementFieldValue;

  bool get isMinimum => this is _NumericMinimumFieldValue;

  bool get isMaximum => this is _NumericMaximumFieldValue;

  static const _DeleteFieldValue _deleteInstance = _DeleteFieldValue._();

  static const _ServerTimestampFieldValue _serverTimestampInstance =
      _ServerTimestampFieldValue._();
}

/// FieldValue class for field deletes.
class _DeleteFieldValue extends FieldValue {
  const _DeleteFieldValue._() : super._(const <Object>[]);

  @override
  String get methodName => 'FieldValue.delete';
}

/// FieldValue class for server timestamps.
class _ServerTimestampFieldValue extends FieldValue {
  const _ServerTimestampFieldValue._() : super._(const <Object>[]);

  @override
  String get methodName => 'FieldValue.serverTimestamp';
}

/// FieldValue class for arrayUnion() transforms.
class _ArrayUnionFieldValue extends FieldValue {
  const _ArrayUnionFieldValue._(List<Object?> elements) : super._(elements);

  @override
  String get methodName => 'FieldValue.arrayUnion';
}

/// FieldValue class for arrayRemove() transforms.
class _ArrayRemoveFieldValue extends FieldValue {
  const _ArrayRemoveFieldValue._(List<Object?> elements) : super._(elements);

  @override
  String get methodName => 'FieldValue.arrayRemove';
}

/* FieldValue class for increment() transforms. */
class _NumericIncrementFieldValue extends FieldValue {
  _NumericIncrementFieldValue(this.operand) : super._(<Object>[operand]);
  final num operand;

  @override
  String get methodName => 'FieldValue.increment';

  num getOperand() => operand;

  /// Integer and double operands are different (as in upstream): `5` != `5.0`.
  @override
  bool operator ==(Object other) =>
      other is _NumericIncrementFieldValue &&
      other.operand.runtimeType == operand.runtimeType &&
      (other.operand == operand || (other.operand.isNaN && operand.isNaN));

  @override
  int get hashCode => Object.hash(runtimeType, operand.runtimeType, operand);
}

/// FieldValue class for minimum() transforms.
class _NumericMinimumFieldValue extends FieldValue {
  _NumericMinimumFieldValue(this.operand) : super._(<Object>[operand]);
  final num operand;

  @override
  String get methodName => 'FieldValue.minimum';

  num getOperand() => operand;

  /// Integer and double operands are different (as in upstream): `5` != `5.0`.
  @override
  bool operator ==(Object other) =>
      other is _NumericMinimumFieldValue &&
      other.operand.runtimeType == operand.runtimeType &&
      (other.operand == operand || (other.operand.isNaN && operand.isNaN));

  @override
  int get hashCode => Object.hash(runtimeType, operand.runtimeType, operand);
}

/// FieldValue class for maximum() transforms.
class _NumericMaximumFieldValue extends FieldValue {
  _NumericMaximumFieldValue(this.operand) : super._(<Object>[operand]);
  final num operand;

  @override
  String get methodName => 'FieldValue.maximum';

  num getOperand() => operand;

  /// Integer and double operands are different (as in upstream): `5` != `5.0`.
  @override
  bool operator ==(Object other) =>
      other is _NumericMaximumFieldValue &&
      other.operand.runtimeType == operand.runtimeType &&
      (other.operand == operand || (other.operand.isNaN && operand.isNaN));

  @override
  int get hashCode => Object.hash(runtimeType, operand.runtimeType, operand);
}
