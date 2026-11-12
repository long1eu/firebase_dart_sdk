// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';

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
  MaybeDocument applyToRemoteDocument(
    MaybeDocument? maybeDoc,
    MutationResult mutationResult,
  ) {
    verifyKeyMatches(maybeDoc);

    // Unlike applyToLocalView, if we're applying a mutation to a remote document the server has
    // accepted the mutation so the precondition must have held.
    final SnapshotVersion version = mutationResult.version;
    ObjectValue newData = value;
    if (fieldTransforms.isNotEmpty) {
      // The transforms are applied by the backend on top of the written data.
      final Document written = Document(
        key,
        version,
        DocumentState.committedMutations,
        value,
      );
      final List<FieldValue> transformResults = serverTransformResults(
        written,
        mutationResult.transformResults,
      );
      newData = transformObject(newData, transformResults);
    }
    return Document(key, version, DocumentState.committedMutations, newData);
  }

  @override
  MaybeDocument? applyToLocalView(
    MaybeDocument? maybeDoc,
    MaybeDocument? baseDoc,
    Timestamp localWriteTime,
  ) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    // Locally mutated documents carry no server version (matches upstream
    // MutableDocument.setHasLocalMutations()).
    const SnapshotVersion version = SnapshotVersion.none;
    ObjectValue newData = value;
    if (fieldTransforms.isNotEmpty) {
      final Document written = Document(
        key,
        version,
        DocumentState.localMutations,
        value,
      );
      final List<FieldValue> transformResults = localTransformResults(
        localWriteTime,
        written,
        baseDoc,
      );
      newData = transformObject(newData, transformResults);
    }
    return Document(key, version, DocumentState.localMutations, newData);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other) &&
          value == other.value &&
          const ListEquality<FieldTransform>().equals(
            fieldTransforms,
            other.fieldTransforms,
          );

  @override
  int get hashCode =>
      value.hashCode ^
      const ListEquality<FieldTransform>().hash(fieldTransforms) ^
      keyAndPreconditionHashCode();

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('precondition', precondition)
          ..add('value', value)
          ..add('fieldTransforms', fieldTransforms))
        .toString();
  }
}
