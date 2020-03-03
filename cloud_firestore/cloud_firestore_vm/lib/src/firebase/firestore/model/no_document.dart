// File created by
// Lung Razvan <long1eu>
// on 17/09/2018

import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:meta/meta.dart';

/// Represents that no documents exists for the key at the given version.
class NoDocument extends MaybeDocument {
  const NoDocument(DocumentKey key, SnapshotVersion version, {@required this.hasCommittedMutations})
      : super(key, version);

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
  int get hashCode => key.hashCode ^ version.hashCode ^ (hasCommittedMutations ? 1 : 0);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('key', key)
          ..add('version', version)
          ..add('hasCommittedMutations', hasCommittedMutations))
        .toString();
  }
}
