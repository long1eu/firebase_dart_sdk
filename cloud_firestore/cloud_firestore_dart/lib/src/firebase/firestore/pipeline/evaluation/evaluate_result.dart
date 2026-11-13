// The result of evaluating a pipeline expression locally.

import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';

/// What a pipeline expression evaluates to for one input: a value, nothing
/// ([unset], as a field that does not exist) or an [error].
///
/// An error is not an exception: functions such as `is_error` and `if_error`
/// observe it, and logic functions may skip it. A stage decides what an error
/// that reaches it means (the backend fails the whole pipeline).
sealed class EvaluateResult {
  const EvaluateResult();

  /// The result with [value].
  const factory EvaluateResult.value(FieldValue value) = EvaluateValue;

  /// The result of an expression that has no value, such as a reference to a
  /// field that does not exist.
  static const EvaluateResult unset = EvaluateUnset._();

  /// The result of an expression that failed.
  static const EvaluateResult error = EvaluateError._();

  /// The null value.
  static final EvaluateResult nullValue = EvaluateValue(NullValue.nullValue());

  static const EvaluateResult trueValue = EvaluateValue(BoolValue.trueValue);
  static const EvaluateResult falseValue = EvaluateValue(BoolValue.falseValue);

  /// The value, or null for [unset] and [error].
  FieldValue? get value => null;

  bool get isError => false;

  bool get isUnset => false;

  /// Whether this is the null value or [unset]: most functions treat a
  /// missing argument as null.
  bool get isNullOrUnset => false;
}

/// A result that is a value.
final class EvaluateValue extends EvaluateResult {
  const EvaluateValue(this.value);

  @override
  final FieldValue value;

  @override
  bool get isNullOrUnset => value is NullValue;

  @override
  bool operator ==(Object other) =>
      other is EvaluateValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'value($value)';
}

/// See [EvaluateResult.unset].
final class EvaluateUnset extends EvaluateResult {
  const EvaluateUnset._();

  @override
  bool get isUnset => true;

  @override
  bool get isNullOrUnset => true;

  @override
  String toString() => 'unset';
}

/// See [EvaluateResult.error].
final class EvaluateError extends EvaluateResult {
  const EvaluateError._();

  @override
  bool get isError => true;

  @override
  String toString() => 'error';
}
