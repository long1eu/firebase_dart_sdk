// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_operation.dart';

/// A field path and the operation to perform upon it.
class FieldTransform {
  final FieldPath fieldPath;
  final TransformOperation operation;

  const FieldTransform(this.fieldPath, this.operation);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldTransform &&
          runtimeType == other.runtimeType &&
          fieldPath == other.fieldPath &&
          operation == other.operation;

  @override
  int get hashCode => fieldPath.hashCode ^ operation.hashCode;
}
