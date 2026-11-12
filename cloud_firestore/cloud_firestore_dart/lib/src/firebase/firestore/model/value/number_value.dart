// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of 'field_value.dart';

/// Base class inherited from by [IntegerValue], [DoubleValue], [Int32FieldValue] and
/// [Decimal128FieldValue]. All of them sort together, by their numeric value.
abstract class NumberValue extends FieldValue {
  const NumberValue();

  /// A [num] for [IntegerValue] and [DoubleValue], and the public
  /// representation of the value for the BSON number types.
  @override
  Object get value;

  @override
  int get typeOrder => FieldValue.typeOrderNumber;
}
