// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/mutation_result.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/mutation/precondition.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:firebase_firestore/src/firebase/timestamp.dart';

/// Represents a [Mutation] of a document. Different subclasses of Mutation will
/// perform different kinds of changes to a base document. For example, a
/// [SetMutation] replaces the value of a document and a [DeleteMutation]
/// deletes a document.
///
/// * In addition to the value of the document mutations also operate on the
/// version. We preserve the version of the base document only in case of Set or
/// Patch mutation to denote what version of original document we've changed. In
/// case of [DeleteMutation] we always reset the version to 0.
///
/// Here's the expected transition table.
///
///     <table>
///     <td>MUTATION</td><td>APPLIED TO</td><td>RESULTS IN</td>
///     <tr><td>SetMutation</td><td>Document(v3)</td><td>Document(v3)</td></tr>
///     <tr><td>SetMutation</td><td>NoDocument(v3)</td><td>Document(v0)</td></tr>
///     <tr><td>SetMutation</td><td>null</td><td>Document(v0)</td></tr>
///     <tr><td>PatchMutation</td><td>Document(v3)</td><td>Document(v3)</td></tr>
///     <tr><td>PatchMutation</td><td>NoDocument(v3)</td><td>NoDocument(v3)</td></tr>
///     <tr><td>PatchMutation</td><td>null</td><td>null</td></tr>
///     <tr><td>TransformMutation</td><td>Document(v3)</td><td>Document(v3)</td></tr>
///     <tr><td>TransformMutation</td><td>NoDocument(v3)</td><td>NoDocument(v3)</td></tr>
///     <tr><td>TransformMutation</td><td>null</td><td>null</td></tr>
///     <tr><td>DeleteMutation</td><td>Document(v3)</td><td>NoDocument(v0)</td></tr>
///     <tr><td>DeleteMutation</td><td>NoDocument(v3)</td><td>NoDocument(v0)</td></tr>
///     <tr><td>DeleteMutation</td><td>null</td><td>NoDocument(v0)</td></tr>
///     </table>
///
/// * Note that [TransformMutations] don't create [Documents] (in the case of
/// being applied to a [NoDocument]), even though they would on the backend.
/// This is because the client always combines the [TransformMutation] with a
/// [SetMutation] or [PatchMutation] and we only want to apply the transform if
/// the prior mutation resulted in a [Document] (always true for a
/// [SetMutation], but not necessarily for an [PatchMutation]).
abstract class Mutation {
  final DocumentKey key;

  /// The precondition for the mutation.
  final Precondition precondition;

  const Mutation(this.key, this.precondition);

  /// Applies this mutation to the given MaybeDocument for the purposes of
  /// computing a new remote document. Both the input and returned documents can
  /// be null.
  ///
  /// [maybeDoc] is the document to mutate. The input document can be null if
  /// the client has no knowledge of the pre-mutation state of the document.
  ///
  /// [mutationResult] is the result of applying the mutation from the backend.
  ///
  /// Returns the mutated document. The returned document may be null, but only
  /// if maybeDoc was null and the mutation would not create a new document.
  MaybeDocument applyToRemoteDocument(
      MaybeDocument maybeDoc, MutationResult mutationResult);

  /// Applies this mutation to the given MaybeDocument for the purposes of
  /// computing the new local view of a document. Both the input and returned
  /// documents can be null.
  ///
  /// [maybeDoc] is the document to mutate. The input document can be null if
  /// the client has no knowledge of the pre-mutation state of the document.
  ///
  /// [baseDoc] is the state of the document prior to this mutation batch. The
  /// input document can be null if the client has no knowledge of the
  /// pre-mutation state of the document.
  ///
  /// [localWriteTime] is timestamp indicating the local write time of the batch
  /// this mutation is a part of.
  ///
  /// Returns the mutated document. The returned document may be null, but only
  /// if maybeDoc was null and the mutation would not create a new document.
  MaybeDocument applyToLocalView(
      MaybeDocument maybeDoc, MaybeDocument baseDoc, Timestamp localWriteTime);

  /// Helper for derived classes to implement .equals.
  bool hasSameKeyAndPrecondition(Mutation other) {
    return key == other.key && precondition == other.precondition;
  }

  /// Helper for derived classes to implement .hashCode.
  int keyAndPreconditionHashCode() {
    return key.hashCode * 31 + precondition.hashCode;
  }

  /// Helper for derived classes to implement .toString().
  String keyAndPreconditionToString() {
    return 'key: $key, precondition: $precondition';
  }

  void verifyKeyMatches(MaybeDocument maybeDoc) {
    if (maybeDoc != null) {
      Assert.hardAssert(maybeDoc.key == key,
          'Can only apply a mutation to a document with the same key');
    }
  }

  /// Returns the version from the given document for use as the result of a
  /// mutation. Mutations are defined to return the version of the base document
  /// only if it is an existing document. Deleted and unknown documents have a
  /// post-mutation version of [SnapshotVersion.none].
  static SnapshotVersion getPostMutationVersion(MaybeDocument maybeDoc) {
    if (maybeDoc is Document) {
      return maybeDoc.version;
    } else {
      return SnapshotVersion.none;
    }
  }
}
