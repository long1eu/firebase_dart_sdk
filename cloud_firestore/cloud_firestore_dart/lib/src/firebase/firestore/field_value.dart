// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/vector_value.dart';
import 'package:collection/collection.dart';

/// Special values for writes: they tell the server how to change a field
/// instead of giving its new value.
///
/// Use them as values in the data of `set` and `update` (on a
/// `DocumentReference`, a `WriteBatch` or a `Transaction`). They cannot be
/// used in queries, and not inside an array value: there the call fails
/// with an [ArgumentError].
///
/// ```dart
/// await firestore.doc('cities/SF').update(<String, Object?>{
///   'population': FieldValue.increment(1),
///   'tags': FieldValue.arrayUnion(<Object?>['coastal']),
///   'updatedAt': FieldValue.serverTimestamp(),
///   'obsolete': FieldValue.delete(),
/// });
/// ```
///
/// Outside a transaction, the client applies the transforms to its local
/// cache at once, so listeners see an estimate before the server confirms the
/// write
/// (a pending server timestamp is read as `null` unless you choose another
/// `ServerTimestampBehavior`). A document can hold at most 500 field
/// transforms in one write.
///
/// [FieldValue.vector] is the exception: it creates a [VectorValue], a plain
/// value and not a transform.
abstract class FieldValue {
  const FieldValue._(this._elements);

  /// Removes the field from the document.
  ///
  /// Allowed only at the top level of the data of `update`, or anywhere in the
  /// data of a `set` with a merge option ([SetOptions.mergeAllFields],
  /// [SetOptions.mergeFields] or [SetOptions.mergeFieldPaths]). Elsewhere,
  /// including a plain `set`, the write fails with an [ArgumentError].
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').update(<String, Object?>{
  ///   'capital': FieldValue.delete(),
  /// });
  /// ```
  factory FieldValue.delete() => _deleteInstance;

  /// Sets the field to the time at which the server applies the write.
  ///
  /// Until the server confirms the write, a snapshot reads the field as `null`
  /// by default; pass [ServerTimestampBehavior.estimate] or
  /// [ServerTimestampBehavior.previous] to `getData`, `get` or `getTimestamp`
  /// of the snapshot to read a local estimate or the previous value instead.
  /// While the client is offline the field stays pending until the write
  /// reaches the server.
  ///
  /// ```dart
  /// await firestore.doc('posts/hello').set(<String, Object?>{
  ///   'title': 'Hello',
  ///   'createdAt': FieldValue.serverTimestamp(),
  /// });
  /// ```
  factory FieldValue.serverTimestamp() => _serverTimestampInstance;

  /// Adds each of [elements] to the end of the array in the field, unless the
  /// array already contains an equal value.
  ///
  /// If the field is not an array (or does not exist), it is set to an array
  /// of exactly [elements]. Values are compared as the backend compares them:
  /// the integer `1` and the double `1.0` are equal (the JS SDK compares them
  /// strictly). [elements] cannot contain other [FieldValue]s or arrays.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').update(<String, Object?>{
  ///   'regions': FieldValue.arrayUnion(<Object?>['west_coast', 'norcal']),
  /// });
  /// ```
  factory FieldValue.arrayUnion(List<Object?> elements) {
    return _ArrayUnionFieldValue._(elements);
  }

  /// Removes every value equal to one of [elements] from the array in the
  /// field.
  ///
  /// If the field is not an array (or does not exist), it is set to an empty
  /// array. Values are compared as in [FieldValue.arrayUnion]. [elements]
  /// cannot contain other [FieldValue]s or arrays.
  ///
  /// ```dart
  /// await firestore.doc('cities/SF').update(<String, Object?>{
  ///   'regions': FieldValue.arrayRemove(<Object?>['norcal']),
  /// });
  /// ```
  factory FieldValue.arrayRemove(List<Object?> elements) {
    return _ArrayRemoveFieldValue._(elements);
  }

  /// Adds [l] to the number in the field; use a negative [l] to subtract.
  ///
  /// If both the current value and [l] are integers, the result is an
  /// integer, clamped to the range of a 64-bit signed integer instead of
  /// overflowing. If either is a double, the result is a double (IEEE 754).
  /// If the field is not a number (or does not exist), it is set to [l].
  ///
  /// ```dart
  /// await firestore.doc('counters/visits').update(<String, Object?>{
  ///   'value': FieldValue.increment(1),
  /// });
  /// ```
  ///
  /// When the answer to a commit is lost and the client sends the write
  /// again, the increment can be applied twice; the JS and Android SDKs have
  /// the same exposure.
  factory FieldValue.increment(num l) {
    return _NumericIncrementFieldValue(l);
  }

  /// Sets the field to the smaller of its current value and [l].
  ///
  /// If the current value is not a number, the field is set to the given value.
  /// If both are numbers they are compared numerically (NaN wins over any other
  /// number); the field keeps the type (integer or double) of the smaller
  /// operand, and keeps its current value and type if they are equivalent.
  ///
  /// ```dart
  /// await firestore.doc('stats/today').update(<String, Object?>{
  ///   'lowest': FieldValue.minimum(12),
  /// });
  /// ```
  factory FieldValue.minimum(num l) {
    return _NumericMinimumFieldValue(l);
  }

  /// Sets the field to the larger of its current value and [l].
  ///
  /// If the current value is not a number, the field is set to the given value.
  /// If both are numbers they are compared numerically (NaN wins over any other
  /// number); the field keeps the type (integer or double) of the larger
  /// operand, and keeps its current value and type if they are equivalent.
  ///
  /// ```dart
  /// await firestore.doc('stats/today').update(<String, Object?>{
  ///   'highest': FieldValue.maximum(31.5),
  /// });
  /// ```
  factory FieldValue.maximum(num l) {
    return _NumericMaximumFieldValue(l);
  }

  /// Creates a [VectorValue] holding a copy of [values], the same as
  /// `VectorValue(values)`.
  ///
  /// Unlike the other factories this is a plain value, not a sentinel: it can
  /// be stored anywhere a value can, and read back with `getVectorValue`.
  /// Vector fields are what `Query.findNearest` searches.
  ///
  /// ```dart
  /// await firestore.doc('items/a').set(<String, Object?>{
  ///   'embedding': FieldValue.vector(<double>[0.1, 0.2, 0.3]),
  /// });
  /// ```
  static VectorValue vector(List<double> values) => VectorValue(values);

  final List<Object?> _elements;

  String get _methodName;

  static const _DeleteFieldValue _deleteInstance = _DeleteFieldValue._();

  static const _ServerTimestampFieldValue _serverTimestampInstance =
      _ServerTimestampFieldValue._();
}

/// FieldValue class for field deletes.
class _DeleteFieldValue extends FieldValue {
  const _DeleteFieldValue._() : super._(const <Object>[]);

  @override
  String get _methodName => 'FieldValue.delete';
}

/// FieldValue class for server timestamps.
class _ServerTimestampFieldValue extends FieldValue {
  const _ServerTimestampFieldValue._() : super._(const <Object>[]);

  @override
  String get _methodName => 'FieldValue.serverTimestamp';
}

/// FieldValue class for arrayUnion() transforms.
class _ArrayUnionFieldValue extends FieldValue {
  const _ArrayUnionFieldValue._(super.elements) : super._();

  @override
  String get _methodName => 'FieldValue.arrayUnion';

  /// Equal when the elements are equal, in the same order (as `isEqual` of
  /// the JS SDK).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ArrayUnionFieldValue &&
          _elementEquality.equals(_elements, other._elements);

  @override
  int get hashCode =>
      Object.hash(runtimeType, _elementEquality.hash(_elements));
}

/// FieldValue class for arrayRemove() transforms.
class _ArrayRemoveFieldValue extends FieldValue {
  const _ArrayRemoveFieldValue._(super.elements) : super._();

  @override
  String get _methodName => 'FieldValue.arrayRemove';

  /// Equal when the elements are equal, in the same order (as `isEqual` of
  /// the JS SDK).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ArrayRemoveFieldValue &&
          _elementEquality.equals(_elements, other._elements);

  @override
  int get hashCode =>
      Object.hash(runtimeType, _elementEquality.hash(_elements));
}

/* FieldValue class for increment() transforms. */
class _NumericIncrementFieldValue extends FieldValue {
  _NumericIncrementFieldValue(this.operand) : super._(<Object>[operand]);
  final num operand;

  @override
  String get _methodName => 'FieldValue.increment';

  num getOperand() => operand;

  /// Integer and double operands are different (as in upstream): `5` != `5.0`.
  @override
  bool operator ==(Object other) =>
      other is _NumericIncrementFieldValue &&
      other.operand.runtimeType == operand.runtimeType &&
      (other.operand == operand || (other.operand.isNaN && operand.isNaN));

  @override
  int get hashCode =>
      Object.hash(runtimeType, operand.runtimeType, _hashableOperand(operand));
}

/// The operand of a numeric transform for hashing. All NaNs are equal there, so
/// they must hash alike, while the hash of a double follows its bits and NaNs
/// differ in theirs (`0.0 / 0.0` has the sign bit set on x64, not on arm64).
/// Compares the elements of array transforms, deeply.
const DeepCollectionEquality _elementEquality = DeepCollectionEquality();

num _hashableOperand(num operand) => operand.isNaN ? double.nan : operand;

/// FieldValue class for minimum() transforms.
class _NumericMinimumFieldValue extends FieldValue {
  _NumericMinimumFieldValue(this.operand) : super._(<Object>[operand]);
  final num operand;

  @override
  String get _methodName => 'FieldValue.minimum';

  num getOperand() => operand;

  /// Integer and double operands are different (as in upstream): `5` != `5.0`.
  @override
  bool operator ==(Object other) =>
      other is _NumericMinimumFieldValue &&
      other.operand.runtimeType == operand.runtimeType &&
      (other.operand == operand || (other.operand.isNaN && operand.isNaN));

  @override
  int get hashCode =>
      Object.hash(runtimeType, operand.runtimeType, _hashableOperand(operand));
}

/// FieldValue class for maximum() transforms.
class _NumericMaximumFieldValue extends FieldValue {
  _NumericMaximumFieldValue(this.operand) : super._(<Object>[operand]);
  final num operand;

  @override
  String get _methodName => 'FieldValue.maximum';

  num getOperand() => operand;

  /// Integer and double operands are different (as in upstream): `5` != `5.0`.
  @override
  bool operator ==(Object other) =>
      other is _NumericMaximumFieldValue &&
      other.operand.runtimeType == operand.runtimeType &&
      (other.operand == operand || (other.operand.isNaN && operand.isNaN));

  @override
  int get hashCode =>
      Object.hash(runtimeType, operand.runtimeType, _hashableOperand(operand));
}

/// Members of [FieldValue] for the SDK itself. Not exported by the public libraries.
extension FieldValueInternal on FieldValue {
  /// The elements of an array union or remove.
  List<Object?> get elements => _elements;

  /// The name of the factory that created this value (for example
  /// `FieldValue.delete`), for error messages.
  String get methodName => _methodName;

  /// Whether this value was created with [FieldValue.delete].
  bool get isDelete => this is _DeleteFieldValue;

  /// Whether this value was created with [FieldValue.serverTimestamp].
  bool get isServerTimestamp => this is _ServerTimestampFieldValue;

  /// Whether this value was created with [FieldValue.arrayUnion].
  bool get isArrayUnion => this is _ArrayUnionFieldValue;

  /// Whether this value was created with [FieldValue.arrayRemove].
  bool get isArrayRemove => this is _ArrayRemoveFieldValue;

  /// Whether this value was created with [FieldValue.increment].
  bool get isIncrement => this is _NumericIncrementFieldValue;

  /// Whether this value was created with [FieldValue.minimum].
  bool get isMinimum => this is _NumericMinimumFieldValue;

  /// Whether this value was created with [FieldValue.maximum].
  bool get isMaximum => this is _NumericMaximumFieldValue;
}
