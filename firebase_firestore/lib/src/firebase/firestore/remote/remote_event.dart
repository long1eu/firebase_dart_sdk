// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/snapshot_version.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/target_change.dart';

/// An event from the [RemoteStore]. It is split into targetChanges (changes to
/// the state or the set of documents in our watched targets) and
/// documentUpdates (changes to the actual documents).
class RemoteEvent {
  const RemoteEvent(
    this.snapshotVersion,
    this.targetChanges,
    this.targetMismatches,
    this.documentUpdates,
    this.resolvedLimboDocuments,
  );

  /// Returns the snapshot version this event brings us up to.
  final SnapshotVersion snapshotVersion;

  /// Returns a map from target to changes to the target.
  final Map<int, TargetChange> targetChanges;

  /// Returns a set of targets that is known to be inconsistent. Listens for
  /// these targets should be re-established without resume tokens.
  final Set<int> targetMismatches;

  /// Returns a set of which documents have changed or been deleted, along with
  /// the doc's new values (if not deleted).
  final Map<DocumentKey, MaybeDocument> documentUpdates;

  /// Returns the set of document updates that are due only to limbo resolution
  /// targets.
  final Set<DocumentKey> resolvedLimboDocuments;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('snapshotVersion', snapshotVersion)
          ..add('targetChanges', targetChanges)
          ..add('targetMismatches', targetMismatches)
          ..add('documentUpdates', documentUpdates)
          ..add('resolvedLimboDocuments', resolvedLimboDocuments))
        .toString();
  }
}
