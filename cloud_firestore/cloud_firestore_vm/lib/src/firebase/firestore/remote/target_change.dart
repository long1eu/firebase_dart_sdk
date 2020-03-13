// File created by
// Lung Razvan <long1eu>
// on 18/09/2018

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:_firebase_database_collection_vm/_firebase_database_collection_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/document_key.dart';
import 'package:meta/meta.dart';

/// A [TargetChange] specifies the set of changes for a specific target as part of a [RemoteEvent].
/// These changes track which documents are added, modified or removed, as well as the target's
/// resume token and whether the target is marked [current]. The actual changes *to* documents are
/// not part of the [TargetChange] since documents may be part of multiple targets.
class TargetChange {
  const TargetChange(
    this.resumeToken,
    this.addedDocuments,
    this.modifiedDocuments,
    this.removedDocuments, {
    @required this.current,
  });

  /// Returns the opaque, server-assigned token that allows watching a query to be resumed after
  /// disconnecting without retransmitting all the data that matches the query. The resume token
  /// essentially identifies a point in time from which the server should resume sending results.
  final Uint8List resumeToken;

  /// Returns the 'current' (synced) status of this target. Note that 'current' has special meaning
  /// in the RPC protocol that implies that a target is both up-to-date and consistent with the rest
  /// of the watch stream.
  final bool current;

  /// Returns the set of documents that were newly assigned to this target as part of this remote
  /// event.
  final ImmutableSortedSet<DocumentKey> addedDocuments;

  /// Returns the set of documents that were already assigned to this target but received an update
  /// during this remote event.
  final ImmutableSortedSet<DocumentKey> modifiedDocuments;

  /// Returns the set of documents that were removed from this target as part of this remote event.
  final ImmutableSortedSet<DocumentKey> removedDocuments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetChange &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality()
              .equals(resumeToken, other.resumeToken) &&
          current == other.current &&
          addedDocuments == other.addedDocuments &&
          modifiedDocuments == other.modifiedDocuments &&
          removedDocuments == other.removedDocuments;

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(resumeToken) ^
      current.hashCode ^
      addedDocuments.hashCode ^
      modifiedDocuments.hashCode ^
      removedDocuments.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('resumeToken', resumeToken)
          ..add('current', current)
          ..add('addedDocuments', addedDocuments)
          ..add('modifiedDocuments', modifiedDocuments)
          ..add('removedDocuments', removedDocuments))
        .toString();
  }
}
