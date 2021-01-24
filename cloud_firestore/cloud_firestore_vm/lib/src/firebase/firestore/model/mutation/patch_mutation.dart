// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart' show Value;
import 'package:collection/collection.dart';

/// A mutation that modifies fields of the document at the given key with the given values. The
/// values are applied through a field mask:
///   * When a field is in both the mask and the values, the corresponding field is updated.
///   * When a field is in neither the mask nor the values, the corresponding field is unmodified.
///   * When a field is in the mask but not in the values, the corresponding field is deleted.
///   * When a field is not in the mask but is in the values, the values map is ignored.
class PatchMutation extends Mutation {
  const PatchMutation(DocumentKey key, this.value, this.mask, Precondition precondition,
      [List<FieldTransform> fieldTransforms = const <FieldTransform>[]])
      : super(key, precondition, fieldTransforms);

  /// Returns the fields and associated values to use when patching the document.
  final ObjectValue value;

  /// Returns the mask to apply to [value], where only fields that are in both the fieldMask and the
  /// value will be updated.
  final FieldMask mask;

  @override
  MaybeDocument applyToRemoteDocument(MaybeDocument maybeDoc, MutationResult mutationResult) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      // Since the mutation was not rejected, we know that the precondition matched on the backend.
      // We therefore must not have the expected version of the document in our cache and return an
      // [UnknownDocument] with the known [updateTime].
      return UnknownDocument(key, mutationResult.version);
    }

    final List<Value> transformResults = mutationResult.transformResults != null
        ? serverTransformResults(maybeDoc, mutationResult.transformResults)
        : <Value>[];

    final SnapshotVersion version = mutationResult.version;
    final ObjectValue newData = patchDocument(maybeDoc, transformResults);
    return Document(key, version, newData, DocumentState.committedMutations);
  }

  @override
  MaybeDocument applyToLocalView(MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final List<Value> transformResults = localTransformResults(localWriteTime, maybeDoc, baseDoc);
    final SnapshotVersion version = Mutation.getPostMutationVersion(maybeDoc);
    final ObjectValue newData = patchDocument(maybeDoc, transformResults);
    return Document(key, version, newData, DocumentState.localMutations);
  }

  /// Patches the data of document if available or creates a new document. Note that this does not
  /// check whether or not the precondition of this patch holds.
  ObjectValue patchDocument(MaybeDocument maybeDoc, List<Value> transformResults) {
    ObjectValue data;
    if (maybeDoc is Document) {
      data = maybeDoc.data;
    } else {
      data = ObjectValue.empty();
    }
    data = patchObject(data);
    data = transformObject(data, transformResults);
    return data;
  }

  ObjectValue patchObject(ObjectValue obj) {
    final ObjectValueBuilder builder = obj.toBuilder();
    for (FieldPath path in mask.mask) {
      if (path.isNotEmpty) {
        final Value newValue = value.get(path);
        if (newValue == null) {
          builder.delete(path);
        } else {
          builder[path] = newValue;
        }
      }
    }
    return builder.build();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatchMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other) &&
          value == other.value &&
          mask == other.mask &&
          const ListEquality<FieldTransform>().equals(fieldTransforms, other.fieldTransforms);

  @override
  int get hashCode =>
      keyAndPreconditionHashCode() ^
      value.hashCode ^
      mask.hashCode ^
      const ListEquality<FieldTransform>().hash(fieldTransforms);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('precondition', precondition)
          ..add('mask', mask)
          ..add('value', value))
        .toString();
  }
}
