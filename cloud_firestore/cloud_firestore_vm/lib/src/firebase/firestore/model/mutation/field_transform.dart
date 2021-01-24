// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';

/// A field path and the operation to perform upon it.
class FieldTransform {
  const FieldTransform(this.fieldPath, this.operation);

  final FieldPath fieldPath;
  final TransformOperation operation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldTransform &&
          runtimeType == other.runtimeType &&
          fieldPath == other.fieldPath &&
          operation == other.operation;

  @override
  int get hashCode => fieldPath.hashCode ^ operation.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('fieldPath', fieldPath)
          ..add('operation', operation))
        .toString();
  }
}
