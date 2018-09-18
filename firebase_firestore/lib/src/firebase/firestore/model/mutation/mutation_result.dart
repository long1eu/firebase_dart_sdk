// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/value/field_value.dart';

/// The result of applying a mutation to the server. This is a model of the
/// [WriteResult] proto message.
///
/// * Note that [MutationResult] does not name which document was mutated.
/// The association is implied positionally: for each entry in the array of
/// [Mutations], there's a corresponding entry in the array of
/// [MutationResults].
class MutationResult {
  /// The version at which the mutation was committed.
  final SnapshotVersion version;

  /// The resulting fields returned from the backend after a [TransformMutation]
  /// has been committed. Contains one [FieldValue] for each [FieldTransform]
  /// that was in the mutation.
  ///
  /// * Will be null if the mutation was not a [TransformMutation].
  final List<FieldValue> transformResults;

  const MutationResult(this.version, this.transformResults);
}
