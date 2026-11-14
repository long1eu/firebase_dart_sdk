// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:cloud_firestore_dart/src/firebase/firestore/model/maybe_document.dart';

/// Represents that no documents exists for the key at the given version.
class NoDocument extends MaybeDocument {
  const NoDocument(
    super.key,
    super.version, {
    required this.hasCommittedMutations,
  });

  final bool hasCommittedMutations;

  @override
  bool get hasPendingWrites => hasCommittedMutations;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoDocument &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          version == other.version &&
          hasCommittedMutations == other.hasCommittedMutations;

  @override
  int get hashCode =>
      key.hashCode ^ version.hashCode ^ (hasCommittedMutations ? 1 : 0);

  @override
  String toString() =>
      'NoDocument{key=$key, version=$version, hasCommittedMutations=$hasCommittedMutations}';
}
