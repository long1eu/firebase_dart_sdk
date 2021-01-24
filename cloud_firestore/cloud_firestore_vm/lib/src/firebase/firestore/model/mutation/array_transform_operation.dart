// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/values.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart';
import 'package:collection/collection.dart';

abstract class ArrayTransformOperation implements TransformOperation {
  const ArrayTransformOperation(this.elements);

  final List<Value> elements;

  @override
  Value applyToLocalView(Value previousValue, Timestamp localWriteTime) {
    return apply(previousValue);
  }

  @override
  Value applyToRemoteDocument(Value previousValue, Value transformResult) {
    // The server just sends null as the transform result for array operations,
    // so we have to calculate a result the same as we do for local
    // applications.
    return apply(previousValue);
  }

  @override
  Value computeBaseValue(Value currentValue) {
    // Array transforms are idempotent and don't require a base value.
    return null;
  }

  /// Applies this ArrayTransformOperation against the specified previousValue.
  Value apply(Value previousValue);

  /// Inspects the provided value, returning an [ArrayValue] containing the existing array
  /// elements or an empty builder if `value` is not an array.
  static ArrayValue coercedFieldValuesArray(Value value) {
    if (isArray(value)) {
      return value.arrayValue.toBuilder();
    } else {
      // coerce to empty array.
      return ArrayValue();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrayTransformOperation &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(elements, other.elements);

  @override
  int get hashCode => const DeepCollectionEquality().hash(elements);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)..add('elements', elements)).toString();
  }
}

/// An array union transform operation.
class ArrayTransformOperationUnion extends ArrayTransformOperation {
  ArrayTransformOperationUnion(List<Value> elements) : super(elements);

  @override
  Value apply(Value previousValue) {
    final ArrayValue result = ArrayTransformOperation.coercedFieldValuesArray(previousValue);
    for (Value element in elements) {
      if (!contains(result, element)) {
        result.values.add(element);
      }
    }

    return Value(arrayValue: result);
  }
}

/// An array remove transform operation.
class ArrayTransformOperationRemove extends ArrayTransformOperation {
  ArrayTransformOperationRemove(List<Value> elements) : super(elements);

  @override
  Value apply(Value previousValue) {
    final ArrayValue result = ArrayTransformOperation.coercedFieldValuesArray(previousValue);
    for (Value removeElement in elements) {
      for (int i = 0; i < result.values.length;) {
        if (equals(result.values[i], removeElement)) {
          result.values.remove(removeElement);
        } else {
          ++i;
        }
      }
    }
    return Value(arrayValue: result);
  }
}
