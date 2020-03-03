// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/object_value.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// A mutation that creates or replaces the document at the given key with the object value
/// contents.
class SetMutation extends Mutation {
  SetMutation(DocumentKey key, this.value, Precondition precondition) : super(key, precondition);

  /// The object value to use when setting the document.
  final ObjectValue value;

  @override
  MaybeDocument applyToRemoteDocument(MaybeDocument maybeDoc, MutationResult mutationResult) {
    verifyKeyMatches(maybeDoc);

    hardAssert(
        mutationResult.transformResults == null, 'Transform results received by SetMutation.');

    // Unlike applyToLocalView, if we're applying a mutation to a remote document the server has
    // accepted the mutation so the precondition must have held.
    final SnapshotVersion version = mutationResult.version;
    return Document(key, version, value, DocumentState.committedMutations);
  }

  @override
  MaybeDocument applyToLocalView(
      MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime) {
    verifyKeyMatches(maybeDoc);

    if (!precondition.isValidFor(maybeDoc)) {
      return maybeDoc;
    }

    final SnapshotVersion version = Mutation.getPostMutationVersion(maybeDoc);
    return Document(key, version, value, DocumentState.localMutations);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetMutation &&
          runtimeType == other.runtimeType &&
          hasSameKeyAndPrecondition(other) &&
          value == other.value;

  @override
  int get hashCode => value.hashCode ^ keyAndPreconditionHashCode();

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('precondition', precondition)
          ..add('value', value))
        .toString();
  }
}
