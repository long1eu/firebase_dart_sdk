// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/double_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/** Filter that matches NaN (not-a-number) fields. */
class NaNFilter extends Filter {
  final FieldPath fieldPath;

  const NaNFilter(this.fieldPath);

  @override
  FieldPath get field => fieldPath;

  @override
  bool matches(Document doc) {
    final FieldValue fieldValue = doc.getField(fieldPath);
    return fieldValue != null && fieldValue == DoubleValue.nan;
  }

  @override
  String get canonicalId => fieldPath.canonicalString + " IS NaN";

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaNFilter &&
          runtimeType == other.runtimeType &&
          fieldPath == other.fieldPath;

  @override
  int get hashCode => fieldPath.hashCode;
}
