// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';

/// Base class inherited from by IntegerValue and DoubleValue. It implements proper number
/// comparisons between the two types.
abstract class NumberValue extends FieldValue {
  const NumberValue();

  @override
  num get value;

  @override
  int get typeOrder => FieldValue.typeOrderNumber;
}
