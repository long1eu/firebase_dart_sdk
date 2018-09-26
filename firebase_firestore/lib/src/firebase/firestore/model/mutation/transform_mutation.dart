// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_transform.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/transform_operation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A mutation that modifies specific fields of the document with transform
/// operations. Currently the only supported transform is a server timestamp,
/// but IP Address, increment(n), etc. could be supported in the future.
///
/// * It is somewhat similar to a [PatchMutation] in that it patches specific
/// fields and has no effect when applied to null or a [NoDocument] (see comment
/// on [Mutation.applyTo] for rationale).
class TransformMutation extends Mutation {
  final List<FieldTransform> fieldTransforms;

  // NOTE: We set a precondition of exists: true as a safety-check, since we
  // always combine TransformMutations with a SetMutation or PatchMutation which
  // (if successful) should end up with an existing document.
  TransformMutation(DocumentKey key, this.fieldTransforms)
      : super(key, Precondition.fromExists(true));

  @override
  MaybeDocument applyToRemoteDocument(
      MaybeDocument maybeDoc, MutationResult mutationResult) {
    verifyKeyMatches(maybeDoc);

    Assert.hardAssert(mutationResult.transformResults != null,
        'Transform results missing for TransformMutation.');

    // TODO: Relax enforcement of this precondition
    // We shouldn't actually enforce the precondition since it already passed on
    // the backend, but we may not have a local version of the document to
    // patch, so we use the precondition to prevent incorrectly putting a
    // partial document into our cache.
    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final Document doc = _requireDocument(maybeDoc);
    final List<FieldValue> transformResults =
        _serverTransformResults(doc, mutationResult.transformResults);
    final ObjectValue newData = _transformObject(doc.data, transformResults);
    return Document(key, doc.version, newData, /* hasLocalMutations= */ false);
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
    return Document(key, doc.version, newData, /* hasLocalMutations= */ true);
  }

  /// Asserts that the given [MaybeDocument] is actually a [Document] and
  /// verifies that it matches the key for this mutation. Since we only support
  /// transformations with precondition exists this method is guaranteed to be
  /// safe.
  Document _requireDocument(MaybeDocument maybeDoc) {
    Assert.hardAssert(
        maybeDoc is Document, 'Unknown MaybeDocument type $maybeDoc');
    final Document doc = maybeDoc as Document;
    Assert.hardAssert(
        doc.key == key, 'Can only transform a document with the same key');
    return doc;
  }

  /// Creates a list of "transform results" (a transform result is a field value
  /// representing the result of applying a transform) for use after a
  /// [TransformMutation] has been acknowledged by the server.
  ///
  /// [baseDoc] the document prior to applying this mutation batch.
  /// [serverTransformResults] the transform results received by the server.
  /// Returns the transform results list.
  List<FieldValue> _serverTransformResults(
      MaybeDocument baseDoc, List<FieldValue> serverTransformResults) {
    final List<FieldValue> transformResults =
        List<FieldValue>(fieldTransforms.length);
    Assert.hardAssert(fieldTransforms.length == serverTransformResults.length,
        'server transform count (${serverTransformResults.length}) should match field transform count (${fieldTransforms.length})');

    for (int i = 0; i < serverTransformResults.length; i++) {
      final FieldTransform fieldTransform = fieldTransforms[i];
      final TransformOperation transform = fieldTransform.operation;

      FieldValue previousValue;
      if (baseDoc is Document) {
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults.add(transform.applyToRemoteDocument(
          previousValue, serverTransformResults[i]));
    }
    return transformResults;
  }

  /// Creates a list of "transform results" (a transform result is a field value
  /// representing the result of applying a transform) for use when applying a
  /// [TransformMutation] locally.
  ///
  /// [localWriteTime] the local time of the transform mutation (used to
  /// generate [ServerTimestampValues]).
  /// [baseDoc] The document prior to applying this mutation batch.
  /// Returns the transform results list.
  List<FieldValue> _localTransformResults(
      Timestamp localWriteTime, MaybeDocument baseDoc) {
    final List<FieldValue> transformResults =
        List<FieldValue>(fieldTransforms.length);
    for (FieldTransform fieldTransform in fieldTransforms) {
      final TransformOperation transform = fieldTransform.operation;

      FieldValue previousValue;
      if (baseDoc is Document) {
        previousValue = baseDoc.getField(fieldTransform.fieldPath);
      }

      transformResults
          .add(transform.applyToLocalView(previousValue, localWriteTime));
    }
    return transformResults;
  }

  ObjectValue _transformObject(
      ObjectValue objectValue, List<FieldValue> transformResults) {
    Assert.hardAssert(transformResults.length == fieldTransforms.length,
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
          fieldTransforms == other.fieldTransforms;

  @override
  int get hashCode => fieldTransforms.hashCode ^ keyAndPreconditionHashCode();

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('keyAndPrecondition', keyAndPreconditionToString())
          ..add('fieldTransforms', fieldTransforms))
        .toString();
  }
}
