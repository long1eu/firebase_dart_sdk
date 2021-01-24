// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart' show Value;
import 'package:collection/collection.dart';

/// A mutation that creates or replaces the document at the given key with the object value
/// contents.
class SetMutation extends Mutation {
  SetMutation(
    DocumentKey key,
    this.value,
    Precondition precondition, [
    List<FieldTransform> fieldTransforms = const <FieldTransform>[],
  ]) : super(key, precondition, fieldTransforms);

  /// The object value to use when setting the document.
  final ObjectValue value;

  @override
  MaybeDocument applyToRemoteDocument(MaybeDocument maybeDoc, MutationResult mutationResult)  {
    verifyKeyMatches(maybeDoc);

    // Unlike applyToLocalView, if we're applying a mutation to a remote document the server has
    // accepted the mutation so the precondition must have held.
    final SnapshotVersion version = mutationResult.version;

    ObjectValue newData = value;
    if (mutationResult.transformResults != null) {
      final List<Value> transformResults = serverTransformResults(maybeDoc, mutationResult.transformResults);
      newData = transformObject(newData, transformResults);
    }

    return Document(key, version, newData, DocumentState.committedMutations);
  }

  @override
  MaybeDocument applyToLocalView(MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final List<Value> transformResults = localTransformResults(localWriteTime, maybeDoc, baseDoc);
    final ObjectValue newData = transformObject(value, transformResults);

    final SnapshotVersion version = Mutation.getPostMutationVersion(maybeDoc);
    return Document(key, version, newData, DocumentState.localMutations);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other) &&
          const ListEquality<FieldTransform>().equals(fieldTransforms, other.fieldTransforms);

  @override
  int get hashCode =>
      keyAndPreconditionHashCode() ^ //
      value.hashCode ^
      const ListEquality<FieldTransform>().hash(fieldTransforms);

  @override
  String toString() {
    return (ToStringHelper(runtimeType) //
          ..add('key', key)
          ..add('precondition', precondition)
          ..add('value', value))
        .toString();
  }
}
