// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of 'field_value.dart';

/// A wrapper for float/double values in Firestore.
class DoubleValue extends NumberValue {
  const DoubleValue(this._value);

  factory DoubleValue.valueOf(double value) => DoubleValue(value);

  /// A constant holding the smallest positive normal value of type [double], 2<sup>-1022</sup>.
  /// It is equal to the hexadecimal floating-point literal ```0x1.0p-1022```.
  static const double minNormal = 2.2250738585072014E-308;

  static const DoubleValue nan = DoubleValue(double.nan);

  final double _value;

  @override
  double get value => _value;

  /// -0.0 is not equal with 0.0
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is DoubleValue && runtimeType == other.runtimeType) {
      if (_value == 0 &&
          other._value == 0 &&
          _value.isNegative != other._value.isNegative) {
        return false;
      }

      if (_value.isNaN && other._value.isNaN) {
        return true;
      }

      return _value == other._value;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => _value.hashCode;

  /// Comparing NaN's should return 0, if [this] is NaN it should return -1 and if [other] is NaN it
  /// should return 1
  @override
  int compareTo(FieldValue other) {
    if (other is! NumberValue) {
      return defaultCompareTo(other);
    }
    if (other is Int32FieldValue || other is Decimal128FieldValue) {
      return -other.compareTo(this);
    }

    if (other is IntegerValue) {
      return compareDoubleWithInt(_value, other._value);
    }

    final num otherValue = other.value as num;
    if (value.isNaN && otherValue.isNaN) {
      return 0;
    } else if (value.isNaN) {
      return -1;
    } else if (otherValue is double && otherValue.isNaN) {
      return 1;
    } else if (otherValue == value) {
      return 0;
    }

    return value.compareTo(otherValue);
  }
}

/// Compares a double with a 64-bit integer by their exact numeric values.
///
/// Converting the integer to a double first is not enough: from 2^53 on
/// several integers become the same double. NaN sorts before every number.
/// (`Util.compareMixed` of the Android SDK.)
int compareDoubleWithInt(double doubleValue, int intValue) {
  if (doubleValue.isNaN || doubleValue < -9223372036854775808.0) {
    return -1;
  }
  if (doubleValue >= 9223372036854775808.0) {
    return 1;
  }
  // Exact: the double is in the range of the 64-bit integers.
  final int truncated = doubleValue.toInt();
  if (truncated != intValue) {
    return truncated < intValue ? -1 : 1;
  }
  // The integer parts are equal; the double can only differ by its fraction
  // (and `truncated`, which came from a double, converts back exactly).
  final double integral = truncated.toDouble();
  return doubleValue < integral
      ? -1
      : doubleValue > integral
      ? 1
      : 0;
}
