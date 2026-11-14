// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/delete_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/set_mutation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_dart/src/firebase/timestamp.dart';

/// Represents a [Mutation] of a document. Different subclasses of Mutation will
/// perform different kinds of changes to a base document. For example, a
/// [SetMutation] replaces the value of a document and a [DeleteMutation]
/// deletes a document.
///
/// In addition to the value of the document mutations also operate on the
/// version. For local mutations (mutations that haven't been committed yet), we
/// preserve the existing version for Set and Patch mutations. For
/// local deletes, we reset the version to 0.
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
/// Field transforms are used only with Set and Patch mutations. They are stored in
/// [fieldTransforms] and sent to the backend in the `updateTransforms` field of the write, rather
/// than in a separate transform write.
abstract class Mutation {
  const Mutation(
    this.key,
    this.precondition, [
    this.fieldTransforms = const <FieldTransform>[],
  ]);

  final DocumentKey key;

  /// The precondition for the mutation.
  final Precondition precondition;

  /// The field transforms (server timestamp, array union/remove, numeric increment) to apply
  /// after the mutation has written its data. Empty if the mutation has no transforms.
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
  MaybeDocument applyToRemoteDocument(
    MaybeDocument? maybeDoc,
    MutationResult mutationResult,
  );

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
  MaybeDocument? applyToLocalView(
    MaybeDocument? maybeDoc,
    MaybeDocument? baseDoc,
    Timestamp localWriteTime,
  );

  /// Applies this mutation to [maybeDoc] like [applyToLocalView] and also returns the fields of the document that are
  /// mutated locally after this mutation (the port's version of the upstream `applyToLocalView` that returns a
  /// [FieldMask], 9815e45).
  ///
  /// [previousMask] are the fields mutated by the mutations applied before this one, [FieldMask.empty] if there were
  /// none, or null if a set or a delete was applied (the whole document is mutated). The returned mask follows the
  /// same rules: a set or delete returns null, a patch adds its mask and the paths of its field transforms, and a
  /// mutation whose precondition does not hold leaves the document and the mask unchanged.
  (MaybeDocument?, FieldMask?) applyToLocalViewWithMask(
    MaybeDocument? maybeDoc,
    MaybeDocument? baseDoc,
    FieldMask? previousMask,
    Timestamp localWriteTime,
  ) {
    verifyKeyMatches(maybeDoc);
    if (!precondition.isValidFor(maybeDoc)) {
      return (maybeDoc, previousMask);
    }

    final MaybeDocument? result = applyToLocalView(
      maybeDoc,
      baseDoc,
      localWriteTime,
    );
    final Mutation mutation = this;
    if (mutation is PatchMutation) {
      // As upstream, a patch keeps its mask also when it creates the document (a merge on a document that the cache
      // knows as deleted) and when the mask is empty. The overlay then stays a patch: it is recalculated when the
      // backend creates the document, and only writes the merged fields. A set overlay would hide the other fields
      // of the backend's document. (An empty mask is handled in [calculateOverlayMutation].)
      if (previousMask == null) {
        return (result, null);
      }
      return (
        result,
        FieldMask(<FieldPath>{
          ...previousMask.mask,
          ...mutation.mask.mask,
          for (FieldTransform transform in fieldTransforms) transform.fieldPath,
        }),
      );
    } else if (mutation is SetMutation || mutation is DeleteMutation) {
      return (result, null);
    } else {
      // Verify mutations do not change the local view.
      return (result, previousMask);
    }
  }

  /// Creates a mutation that, applied to the remote version of the document, results in [maybeDoc] (the local view of
  /// the document), or null if the document has no local mutations.
  ///
  /// [mask] is the result of [applyToLocalViewWithMask] for all the pending mutations of the document: null if a set
  /// or delete was applied, which creates a set or delete overlay; otherwise a patch overlay with the values of the
  /// mutated fields.
  ///
  /// DEVIATION FROM UPSTREAM (empty patch mask): upstream returns no overlay whenever the mask is empty. A patch of no
  /// fields (`set({}, merge: true)`) still creates the document and marks it as having pending writes, so here an
  /// empty mask only means "no overlay" when the document has no local mutations; otherwise the overlay is a patch
  /// with an empty mask.
  static Mutation? calculateOverlayMutation(
    MaybeDocument? maybeDoc,
    FieldMask? mask,
  ) {
    if (mask != null &&
        mask.mask.isEmpty &&
        !(maybeDoc is Document && maybeDoc.hasLocalMutations)) {
      return null;
    }
    hardAssert(
      maybeDoc != null,
      'A document with local mutations must have a local view',
    );
    final MaybeDocument doc = maybeDoc!;

    // mask == null when there are Set or Delete being applied to get to the current document.
    if (mask == null) {
      if (doc is Document) {
        return SetMutation(doc.key, doc.data, Precondition.none);
      } else {
        hardAssert(
          doc is NoDocument,
          'A local delete must result in a NoDocument, got ${doc.runtimeType} for ${doc.key.path}',
        );
        return DeleteMutation(doc.key, Precondition.none);
      }
    }

    final ObjectValue docValue = doc is Document ? doc.data : ObjectValue.empty;
    ObjectValue patchValue = ObjectValue.empty;
    final Set<FieldPath> maskSet = <FieldPath>{};
    // In order, as upstream (a sorted FieldMask): a deleted parent such as `a.b` must be handled before the fields
    // below it (`a.b.c`), or its own parent (`a`, left as an empty map) is dropped from the overlay.
    final List<FieldPath> paths = mask.mask.toList()..sort();
    for (FieldPath path in paths) {
      if (maskSet.contains(path)) {
        continue;
      }
      FieldPath fieldPath = path;
      // If we are deleting a nested field, we take the immediate parent as the mask used to construct resulting
      // mutation.
      // Justification: Nested fields can create parent fields implicitly. If only a leaf entry is deleted in later
      // mutations, the parent field should still remain, but we may have lost this information.
      // Consider mutation (foo.bar 1), then mutation (foo.bar delete()). This leaves the final result (foo, {}).
      // Despite the fact that `doc` has the correct result, `foo` is not in `mask`, and the resulting mutation would
      // miss `foo`.
      if (docValue.get(fieldPath) == null && fieldPath.length > 1) {
        fieldPath = fieldPath.popLast();
      }
      final FieldValue? value = docValue.get(fieldPath);
      if (value != null) {
        patchValue = patchValue.set(fieldPath, value);
      }
      maskSet.add(fieldPath);
    }
    return PatchMutation(
      doc.key,
      patchValue,
      FieldMask(maskSet),
      Precondition.none,
    );
  }

  /// Helper for derived classes to implement .equals.
  bool hasSameKeyAndPrecondition(Mutation other) {
    return key == other.key && precondition == other.precondition;
  }

  /// Helper for derived classes to implement .hashCode.
  int keyAndPreconditionHashCode() {
    return key.hashCode * 31 + precondition.hashCode;
  }

  void verifyKeyMatches(MaybeDocument? maybeDoc) {
    if (maybeDoc != null) {
      hardAssert(
        maybeDoc.key == key,
        'Can only apply a mutation to a document with the same key',
      );
    }
  }

  /// Creates a list of 'transform results' (a transform result is a field value representing the
  /// result of applying a transform) for use after a mutation containing transforms has been
  /// acknowledged by the server.
  ///
  /// [baseDoc] is the document the transforms are applied on top of. [serverTransformResults] are
  /// the transform results received by the server.
  List<FieldValue> serverTransformResults(
    MaybeDocument? baseDoc,
    List<FieldValue> serverTransformResults,
  ) {
    final List<FieldValue> transformResults = <FieldValue>[];
    hardAssertLazy(
      fieldTransforms.length == serverTransformResults.length,
      () =>
          'server transform count (${serverTransformResults.length}) should match field transform '
          'count (${fieldTransforms.length})',
    );

    for (int i = 0; i < serverTransformResults.length; i++) {
      final FieldTransform fieldTransform = fieldTransforms[i];
      final TransformOperation transform = fieldTransform.operation;

      FieldValue? previousValue;
      if (baseDoc is Document) {
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults.add(
        transform.applyToRemoteDocument(
          previousValue,
          serverTransformResults[i],
        ),
      );
    }
    return transformResults;
  }

  /// Creates a list of 'transform results' for use when applying a mutation with transforms
  /// locally.
  ///
  /// [localWriteTime] is the local time of the mutation (used to generate [ServerTimestampValue]s).
  /// [maybeDoc] is the current state of the document the transforms apply to. [baseDoc] is the
  /// document prior to applying this mutation batch.
  List<FieldValue> localTransformResults(
    Timestamp localWriteTime,
    MaybeDocument? maybeDoc,
    MaybeDocument? baseDoc,
  ) {
    final List<FieldValue> transformResults = <FieldValue>[];
    for (FieldTransform fieldTransform in fieldTransforms) {
      final TransformOperation transform = fieldTransform.operation;

      FieldValue? previousValue;
      if (maybeDoc is Document) {
        previousValue = maybeDoc.getField(fieldTransform.fieldPath);
      }

      if (previousValue == null && baseDoc is Document) {
        // If the current document does not contain a value for the mutated field, use the value
        // that existed before applying this mutation batch. This solves an edge case where a
        // PatchMutation clears the values in a nested map before the transform is applied.
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults.add(
        transform.applyToLocalView(previousValue, localWriteTime),
      );
    }
    return transformResults;
  }

  /// Sets the [transformResults] on [objectValue], one per entry in [fieldTransforms].
  ObjectValue transformObject(
    ObjectValue objectValue,
    List<FieldValue> transformResults,
  ) {
    hardAssert(
      transformResults.length == fieldTransforms.length,
      'Transform results length mismatch.',
    );

    for (int i = 0; i < fieldTransforms.length; i++) {
      final FieldPath fieldPath = fieldTransforms[i].fieldPath;
      objectValue = objectValue.set(fieldPath, transformResults[i]);
    }
    return objectValue;
  }

  /// If applicable, returns the base value to persist with this mutation. If a base value is
  /// provided, the mutation is always applied to this base value, even if document has already
  /// been updated.
  ///
  /// The base value is a sparse object that consists of only the document fields for which this
  /// mutation contains a non-idempotent transformation (e.g. a numeric increment). The provided
  /// value guarantees consistent behavior for non-idempotent transforms and allow us to return the
  /// same latency-compensated value even if the backend has already applied the mutation. The base
  /// value is null for idempotent mutations, as they can be re-played even if the backend has
  /// already applied them.
  ///
  /// Returns a base value to store along with the mutation, or null for idempotent mutations.
  ObjectValue? extractTransformBaseValue(MaybeDocument? maybeDoc) {
    ObjectValue? baseObject;

    for (FieldTransform transform in fieldTransforms) {
      FieldValue? existingValue;
      if (maybeDoc is Document) {
        existingValue = maybeDoc.getField(transform.fieldPath);
      }

      final FieldValue? coercedValue = transform.operation.computeBaseValue(
        existingValue,
      );
      if (coercedValue != null) {
        baseObject = (baseObject ?? ObjectValue.empty).set(
          transform.fieldPath,
          coercedValue,
        );
      }
    }

    return baseObject;
  }
}
