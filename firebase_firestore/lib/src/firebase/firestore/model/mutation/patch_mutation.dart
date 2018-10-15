// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/field_path.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/field_mask.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A mutation that modifies fields of the document at the given key with the
/// given values. The values are applied through a field mask:
///
///     <ul>
///       <li>When a field is in both the mask and the values, the corresponding field is updated.
///       <li>When a field is in neither the mask nor the values, the corresponding field is unmodified.
///       <li>When a field is in the mask but not in the values, the corresponding field is deleted.
///       <li>When a field is not in the mask but is in the values, the values map is ignored.
///     </ul>
class PatchMutation extends Mutation {
  /// Returns the fields and associated values to use when patching the
  /// document.
  final ObjectValue value;

  /// Returns the mask to apply to [value], where only fields that are in both
  /// the fieldMask and the value will be updated.
  final FieldMask mask;

  const PatchMutation(
      DocumentKey key, this.value, this.mask, Precondition precondition)
      : super(key, precondition);

  @override
  MaybeDocument applyToRemoteDocument(
      MaybeDocument maybeDoc, MutationResult mutationResult) {
    verifyKeyMatches(maybeDoc);

    Assert.hardAssert(mutationResult.transformResults == null,
        'Transform results received by PatchMutation.');

    // TODO: Relax enforcement of this precondition
    // We shouldn't actually enforce the precondition since it already passed on
    // the backend, but we may not have a local version of the document to
    // patch, so we use the precondition to prevent incorrectly putting a
    // partial document into our cache.
    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final SnapshotVersion version = Mutation.getPostMutationVersion(maybeDoc);
    final ObjectValue newData = patchDocument(maybeDoc);
    return Document(key, version, newData, /* hasLocalMutations= */ false);
  }

  @override
  MaybeDocument applyToLocalView(
      MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final SnapshotVersion version = Mutation.getPostMutationVersion(maybeDoc);
    final ObjectValue newData = patchDocument(maybeDoc);
    return Document(key, version, newData, /* hasLocalMutations= */ true);
  }

  /// Patches the data of document if available or creates a new document. Note
  /// that this does not check whether or not the precondition of this patch
  /// holds.
  ObjectValue patchDocument(MaybeDocument maybeDoc) {
    ObjectValue data;
    if (maybeDoc is Document) {
      data = maybeDoc.data;
    } else {
      data = ObjectValue.empty;
    }
    return patchObject(data);
  }

  ObjectValue patchObject(ObjectValue obj) {
    for (FieldPath path in mask.mask) {
      if (path.isNotEmpty) {
        final FieldValue newValue = value.get(path);
        if (newValue == null) {
          obj = obj.delete(path);
        } else {
          obj = obj.set(path, newValue);
        }
      }
    }
    return obj;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatchMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other) &&
          value == other.value &&
          mask == other.mask;

  @override
  int get hashCode =>
      value.hashCode ^ mask.hashCode ^ keyAndPreconditionHashCode();

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
