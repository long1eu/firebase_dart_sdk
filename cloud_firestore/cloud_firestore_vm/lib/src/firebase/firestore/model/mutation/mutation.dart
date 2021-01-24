// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:cloud_firestore_vm/src/proto/google/firestore/v1/index.dart' show Value;

/// Represents a [Mutation] of a document. Different subclasses of Mutation will
/// perform different kinds of changes to a base document. For example, a
/// [SetMutation] replaces the value of a document and a [DeleteMutation]
/// deletes a document.
///
/// In addition to the value of the document mutations also operate on the version. For local
/// mutations (mutations that haven't been committed yet), we preserve the existing version for Set
/// and Patch mutations. For local deletes, we reset the version to 0.
///
/// Here's the expected transition table.
///
/// ||||
/// |--- |--- |--- |
/// |MUTATION               |APPLIED TO         |RESULTS IN|
/// |SetMutation            |Document(v3)       |Document(v3)|
/// |SetMutation            |NoDocument(v3)     |Document(v0)|
/// |SetMutation            |null               |Document(v0)|
/// |PatchMutation          |Document(v3)       |Document(v3)|
/// |PatchMutation          |NoDocument(v3)     |NoDocument(v3)|
/// |PatchMutation          |null               |null|
/// |DeleteMutation         |Document(v3)       |NoDocument(v0)|
///
/// For acknowledged mutations, we use the [updateTime] of the [WriteResponse] as the resulting
/// version for Set and Patch mutations. As deletes have no explicit update time, we use
/// the [commitTime] of the [WriteResponse] for acknowledged deletes.
///
/// If a mutation is acknowledged by the backend but fails the precondition check locally, we return
/// an [UnknownDocument] and rely on Watch to send us the updated version.
///
/// Field transforms are used only with Patch and Set Mutations. We use the [updateTransforms]
/// field to store transforms, rather than the [transforms] message.
abstract class Mutation {
  const Mutation(this.key, this.precondition, [this.fieldTransforms = const <FieldTransform>[]]);

  final DocumentKey key;

  /// The precondition for the mutation.
  final Precondition precondition;

  final List<FieldTransform> fieldTransforms;

  /// Applies this mutation to the given [MaybeDocument] for the purposes of computing a new remote
  /// document. If the input document doesn't match the expected state (e.g. it is null or
  /// outdated), an [UnknownDocument] can be returned.
  ///
  /// [maybeDoc] is the document to mutate. The input document can be null if the client has no
  /// knowledge of the pre-mutation state of the document.
  ///
  /// [mutationResult] is the result of applying the mutation from the backend.
  ///
  /// Returns the mutated document. The returned document may be an [UnknownDocument], if the
  /// mutation could not be applied to the locally cached base document.
  MaybeDocument applyToRemoteDocument(MaybeDocument maybeDoc, MutationResult mutationResult);

  /// Applies this mutation to [maybeDoc] for the purposes of computing the new local view of a
  /// document. Both the input and returned documents can be null.
  ///
  /// [maybeDoc] is the document to mutate. The input document can be null if the client has no
  /// knowledge of the pre-mutation state of the document.
  ///
  /// [baseDoc] is the state of the document prior to this mutation batch. The input document can be
  /// null if the client has no knowledge of the pre-mutation state of the document.
  ///
  /// [localWriteTime] is timestamp indicating the local write time of the batch this mutation is a
  /// part of.
  ///
  /// Returns the mutated document. The returned document may be null, but only if [maybeDoc] was
  /// null and the mutation would not create a new document.
  MaybeDocument applyToLocalView(MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime);

  /// Helper for derived classes to implement .equals.
  bool hasSameKeyAndPrecondition(Mutation other) {
    return key == other.key && precondition == other.precondition;
  }

  /// Helper for derived classes to implement .hashCode.
  int keyAndPreconditionHashCode() {
    return key.hashCode * 31 + precondition.hashCode;
  }

  void verifyKeyMatches(MaybeDocument maybeDoc) {
    if (maybeDoc != null) {
      hardAssert(maybeDoc.key == key, 'Can only apply a mutation to a document with the same key');
    }
  }

  /// Returns the version from the given document for use as the result of a mutation. Mutations are
  /// defined to return the version of the base document only if it is an existing document. Deleted
  /// and unknown documents have a post-mutation version of [SnapshotVersion.none].
  static SnapshotVersion getPostMutationVersion(MaybeDocument maybeDoc) {
    if (maybeDoc is Document) {
      return maybeDoc.version;
    } else {
      return SnapshotVersion.none;
    }
  }

  /// Creates a list of "transform results" (a transform result is a field value representing the
  /// result of applying a transform) for use after a mutation containing transforms has been
  /// acknowledged by the server.
  ///
  /// The [baseDoc] is the document prior to applying this mutation batch.
  List<Value> serverTransformResults(MaybeDocument baseDoc, List<Value> serverTransformResults) {
    final List<Value> transformResults = <Value>[];
    hardAssert(
      fieldTransforms.length == serverTransformResults.length,
      'server transform count (${serverTransformResults.length}) should match field transform count (${fieldTransforms.length})',
    );

    for (int i = 0; i < serverTransformResults.length; i++) {
      final FieldTransform fieldTransform = fieldTransforms[i];
      final TransformOperation transform = fieldTransform.operation;

      Value previousValue;
      if (baseDoc is Document) {
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults.add(transform.applyToRemoteDocument(previousValue, serverTransformResults[i]));
    }
    return transformResults;
  }

  /// Creates a list of "transform results" (a transform result is a field value representing the
  /// result of applying a transform) for use when applying a transform locally.
  ///
  /// The [localWriteTime] is the local time of the mutation (used to generate ServerTimestampValues),
  /// [maybeDoc] is the current state of the document after applying all previous mutations and [baseDoc]
  /// is the document prior to applying this mutation batch.
  List<Value> localTransformResults(Timestamp localWriteTime, MaybeDocument maybeDoc, MaybeDocument baseDoc) {
    final List<Value> transformResults = <Value>[];
    for (FieldTransform fieldTransform in fieldTransforms) {
      final TransformOperation transform = fieldTransform.operation;

      Value previousValue;
      if (maybeDoc is Document) {
        previousValue = maybeDoc.getField(fieldTransform.fieldPath);
      }

      transformResults.add(transform.applyToLocalView(previousValue, localWriteTime));
    }
    return transformResults;
  }

  ObjectValue transformObject(ObjectValue objectValue, List<Value> transformResults) {
    hardAssert(transformResults.length == fieldTransforms.length, 'Transform results length mismatch.');

    final ObjectValueBuilder builder = objectValue.toBuilder();
    for (int i = 0; i < fieldTransforms.length; i++) {
      final FieldTransform fieldTransform = fieldTransforms[i];
      final FieldPath fieldPath = fieldTransform.fieldPath;
      builder[fieldPath] = transformResults[i];
    }
    return builder.build();
  }

  ObjectValue extractTransformBaseValue(MaybeDocument maybeDoc) {
    ObjectValueBuilder baseObject;

    for (FieldTransform transform in fieldTransforms) {
      Value existingValue;
      if (maybeDoc is Document) {
        existingValue = maybeDoc.getField(transform.fieldPath);
      }

      final Value coercedValue = transform.operation.computeBaseValue(existingValue);
      if (coercedValue != null) {
        baseObject ??= ObjectValue.newBuilder();
        baseObject[transform.fieldPath] = coercedValue;
      }
    }

    return baseObject != null ? baseObject.build() : null;
  }
}
