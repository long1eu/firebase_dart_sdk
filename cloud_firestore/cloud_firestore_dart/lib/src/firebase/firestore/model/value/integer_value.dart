// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of 'field_value.dart';

/// A wrapper for integer/long values in Firestore.
class IntegerValue extends NumberValue {
  const IntegerValue(this._value);

  factory IntegerValue.valueOf(int value) => IntegerValue(value);

  /// The largest and the smallest 64 bit integers.
  ///
  /// Parsed rather than written as literals: compiled to JavaScript an `int`
  /// is a double, which cannot represent these values exactly, and the
  /// literals would not compile. There they are 2^63 and -2^63.
  static final int max = int.parse('9223372036854775807');
  static final int min = int.parse('-9223372036854775808');

  final int _value;

  @override
  int get value => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntegerValue &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  /// NOTE:
  /// Comparing to a NaN should always return 1;
  /// Comparing 0 with 0.0 should return 0;
  @override
  int compareTo(FieldValue other) {
    if (other is Int32FieldValue) {
      return value.compareTo(other.intValue);
    } else if (other is Decimal128FieldValue) {
      return -other.compareTo(this);
    } else if (other is NumberValue) {
      final num otherValue = other.value as num;
      if (otherValue.isNaN) {
        return 1;
      } else if (otherValue is double && otherValue == 0.0) {
        return value.compareTo(0);
      } else {
        return value.compareTo(otherValue);
      }
    } else {
      return defaultCompareTo(other);
    }
  }
}
