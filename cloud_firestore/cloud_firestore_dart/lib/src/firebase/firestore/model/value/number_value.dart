// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

part of field_value;

/// Base class inherited from by IntegerValue and DoubleValue. It implements proper number
/// comparisons between the two types.
abstract class NumberValue extends FieldValue {
  const NumberValue();

  @override
  num get value;

  @override
  int get typeOrder => FieldValue.typeOrderNumber;
}
