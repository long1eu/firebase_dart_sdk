// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/core/filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/null_value.dart';

/// Filter that matches NULL values.
class NullFilter extends Filter {
  const NullFilter(this.fieldPath);

  final FieldPath fieldPath;

  @override
  FieldPath get field => fieldPath;

  @override
  bool matches(Document doc) {
    final FieldValue fieldValue = doc.getField(fieldPath);
    return fieldValue != null && fieldValue == NullValue.nullValue();
  }

  @override
  String get canonicalId => '${fieldPath.canonicalString} IS NULL';

  @override
  String toString() => canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NullFilter &&
          runtimeType == other.runtimeType &&
          fieldPath == other.fieldPath;

  @override
  int get hashCode => fieldPath.hashCode;
}
