// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';

/// A transform within a [TransformMutation].
abstract class TransformOperation {
  /// Computes the local transform result against the provided [previousValue],
  /// optionally using the provided [localWriteTime].
  FieldValue applyToLocalView(
      FieldValue previousValue, Timestamp localWriteTime);

  /// Computes a final transform result after the transform has been
  /// acknowledged by the server, potentially using the server-provided
  /// [transformResult].
  FieldValue applyToRemoteDocument(
      FieldValue previousValue, FieldValue transformResult);

  /// If applicable, returns the base value to persist for this transform. If a
  /// base value is provided, the transform operation is always applied to this
  /// base value, even if document has already been updated.
  ///
  /// Base values provide consistent behavior for non-idempotent transforms and
  /// allow us to return the same latency-compensated value even if the backend
  /// has already applied the transform operation. The base value is null for
  /// idempotent transforms, as they can be re-played even if the backend has
  /// already applied them.
  ///
  /// Returns a base value to store along with the mutation, or null for
  /// idempotent transforms.
  FieldValue computeBaseValue(FieldValue previousValue);
}
