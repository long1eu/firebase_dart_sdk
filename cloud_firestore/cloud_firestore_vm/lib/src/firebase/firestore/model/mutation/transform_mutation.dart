// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/field_path.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/maybe_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/patch_mutation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/no_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/unknown_document.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/field_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/object_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/value/server_timestamp_value.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/util/assert.dart';
import 'package:cloud_firestore_vm/src/firebase/timestamp.dart';
import 'package:collection/collection.dart';

/// A mutation that modifies specific fields of the document with transform operations. Currently
/// the only supported transform is a server timestamp, but IP Address, increment(n), etc. could be
/// supported in the future.
///
/// It is somewhat similar to a [PatchMutation] in that it patches specific fields and has no effect
/// when applied to null or a [NoDocument] (see comment on [Mutation.applyToRemoteDocument] and
/// [Mutation.applyToLocalView] for rationale).
class TransformMutation extends Mutation {
  // NOTE: We set a precondition of exists: true as a safety-check, since we always combine
  // TransformMutations with a SetMutation or PatchMutation which (if successful) should end up with
  // an existing document.
  TransformMutation(DocumentKey key, this.fieldTransforms)
      : super(key, Precondition(exists: true));

  final List<FieldTransform> fieldTransforms;

  @override
  MaybeDocument applyToRemoteDocument(
      MaybeDocument maybeDoc, MutationResult mutationResult) {
    verifyKeyMatches(maybeDoc);

    hardAssert(mutationResult.transformResults != null,
        'Transform results missing for TransformMutation.');

    if (!precondition.isValidFor(maybeDoc)) {
      // Since the mutation was not rejected, we know that the precondition matched on the backend.
      // We therefore must not have the expected version of the document in our cache and return an
      // [UnknownDocument] with the known [updateTime].
      return UnknownDocument(key, mutationResult.version);
    }

    final Document doc = _requireDocument(maybeDoc);
    final List<FieldValue> transformResults =
        _serverTransformResults(doc, mutationResult.transformResults);
    final ObjectValue newData = _transformObject(doc.data, transformResults);
    return Document(
        key, mutationResult.version, newData, DocumentState.committedMutations);
  }

  @override
  MaybeDocument applyToLocalView(
      MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final Document doc = _requireDocument(maybeDoc);
    final List<FieldValue> transformResults =
        _localTransformResults(localWriteTime, baseDoc);
    final ObjectValue newData = _transformObject(doc.data, transformResults);
    return Document(key, doc.version, newData, DocumentState.localMutations);
  }

  /// Asserts that the given [MaybeDocument] is actually a [Document] and verifies that it matches
  /// the key for this mutation. Since we only support transformations with precondition exists this
  /// method is guaranteed to be safe.
  Document _requireDocument(MaybeDocument maybeDoc) {
    hardAssert(maybeDoc is Document, 'Unknown MaybeDocument type $maybeDoc');
    final Document doc = maybeDoc;
    hardAssert(
        doc.key == key, 'Can only transform a document with the same key');
    return doc;
  }

  /// Creates a list of 'transform results' (a transform result is a field value representing the
  /// result of applying a transform) for use after a [TransformMutation] has been acknowledged by
  /// the server.
  ///
  /// [baseDoc] the document prior to applying this mutation batch.
  /// [serverTransformResults] the transform results received by the server.
  ///
  /// Returns the transform results list.
  List<FieldValue> _serverTransformResults(
      MaybeDocument baseDoc, List<FieldValue> serverTransformResults) {
    final List<FieldValue> transformResults =
        List<FieldValue>(fieldTransforms.length);
    hardAssert(
        fieldTransforms.length == serverTransformResults.length,
        'server transform count (${serverTransformResults.length}) should match field transform '
        'count (${fieldTransforms.length})');

    for (int i = 0; i < serverTransformResults.length; i++) {
      final FieldTransform fieldTransform = fieldTransforms[i];
      final TransformOperation transform = fieldTransform.operation;

      FieldValue previousValue;
      if (baseDoc is Document) {
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults[i] = transform.applyToRemoteDocument(
          previousValue, serverTransformResults[i]);
    }
    return transformResults;
  }

  /// Creates a list of 'transform results' (a transform result is a field value representing the
  /// result of applying a transform) for use when applying a [TransformMutation] locally.
  ///
  /// [localWriteTime] the local time of the transform mutation (used to generate
  /// [ServerTimestampValue]s).
  /// [baseDoc] is the document prior to applying this mutation batch.
  ///
  /// Returns the transform results list.
  List<FieldValue> _localTransformResults(
      Timestamp localWriteTime, MaybeDocument baseDoc) {
    final List<FieldValue> transformResults =
        List<FieldValue>(fieldTransforms.length);
    int i = 0;
    for (FieldTransform fieldTransform in fieldTransforms) {
      final TransformOperation transform = fieldTransform.operation;

      FieldValue previousValue;
      if (baseDoc is Document) {
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults[i] =
          transform.applyToLocalView(previousValue, localWriteTime);
      i++;
    }
    return transformResults;
  }

  ObjectValue _transformObject(
      ObjectValue objectValue, List<FieldValue> transformResults) {
    hardAssert(transformResults.length == fieldTransforms.length,
        'Transform results length mismatch.');

    for (int i = 0; i < fieldTransforms.length; i++) {
      final FieldTransform fieldTransform = fieldTransforms[i];
      final FieldPath fieldPath = fieldTransform.fieldPath;
      objectValue = objectValue.set(fieldPath, transformResults[i]);
    }
    return objectValue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransformMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other) &&
          const ListEquality<FieldTransform>()
              .equals(fieldTransforms, other.fieldTransforms);

  @override
  int get hashCode =>
      const ListEquality<FieldTransform>().hash(fieldTransforms) ^
      keyAndPreconditionHashCode();

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('precondition', precondition)
          ..add('fieldTransforms', fieldTransforms))
        .toString();
  }
}
