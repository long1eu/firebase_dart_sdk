// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/array_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

abstract class ArrayTransformOperation implements TransformOperation {
  final List<FieldValue> elements;

  const ArrayTransformOperation(this.elements);

  @override
  FieldValue applyToLocalView(
      FieldValue previousValue, Timestamp localWriteTime) {
    return apply(previousValue);
  }

  @override
  FieldValue applyToRemoteDocument(
      FieldValue previousValue, FieldValue transformResult) {
    // The server just sends null as the transform result for array operations, so we have to
    // calculate a result the same as we do for local applications.
    return apply(previousValue);
  }

  /// Applies this ArrayTransformOperation against the specified previousValue. */
  ArrayValue apply(FieldValue previousValue);

  /// Inspects the provided value, returning an [List] copy of the internal
  /// array if it's an ArrayValue and an empty [List] if it's null or any other
  /// type of FSTFieldValue.
  static List<FieldValue> coercedFieldValuesArray(FieldValue value) {
    if (value is ArrayValue) {
      return value.internalValue;
    } else {
      // coerce to empty array.
      return <FieldValue>[];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrayTransformOperation &&
          runtimeType == other.runtimeType &&
          elements == other.elements;

  @override
  int get hashCode => elements.hashCode;
}

/// An array union transform operation.
class ArrayTransformOperationUnion extends ArrayTransformOperation {
  ArrayTransformOperationUnion(List<FieldValue> elements) : super(elements);

  @override
  ArrayValue apply(FieldValue previousValue) {
    final List<FieldValue> result =
        ArrayTransformOperation.coercedFieldValuesArray(previousValue);
    for (FieldValue element in elements) {
      if (!result.contains(element)) {
        result.add(element);
      }
    }
    return ArrayValue.fromList(result);
  }
}

/// An array remove transform operation.
class ArrayTransformOperationRemove extends ArrayTransformOperation {
  ArrayTransformOperationRemove(List<FieldValue> elements) : super(elements);

  @override
  ArrayValue apply(FieldValue previousValue) {
    final List<FieldValue> result =
        ArrayTransformOperation.coercedFieldValuesArray(previousValue);

    elements.forEach(result.remove);
    return ArrayValue.fromList(result);
  }
}
