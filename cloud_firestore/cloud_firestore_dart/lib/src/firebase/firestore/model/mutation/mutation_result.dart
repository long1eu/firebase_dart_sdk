// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/value/field_value.dart';

/// The result of applying a mutation to the server. This is a model of the [WriteResult] proto
/// message.
///
/// Note that [MutationResult] does not name which document was mutated. The association is implied
/// positionally: for each entry in the array of [Mutations], there's a corresponding entry in the
/// array of [MutationResults].
class MutationResult {
  const MutationResult(this.version, [this.transformResults = const <FieldValue>[]]);

  /// The version at which the mutation was committed.
  ///   * For most operations, this is the [updateTime] in the [WriteResult].
  ///   * For deletes, it is the [commitTime] of the [WriteResponse] (because deletes are not stored
  ///   and have no updateTime).
  ///
  /// Note that these versions can be different: No-op writes will not change the updateTime even
  /// though the [commitTime] advances.
  final SnapshotVersion version;

  /// The resulting fields returned from the backend after a mutation containing field transforms
  /// has been committed. Contains one [FieldValue] for each [FieldTransform] that was in the
  /// mutation.
  ///
  /// Will be empty if the mutation did not contain any field transforms.
  final List<FieldValue> transformResults;
}
