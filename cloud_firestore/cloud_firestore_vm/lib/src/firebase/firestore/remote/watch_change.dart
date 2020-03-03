// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:firebase_core/firebase_core_vm.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/existence_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:grpc/grpc.dart';

/// The kind of change that happened to the watch target.
enum WatchTargetChangeType { noChange, added, removed, current, reset }

/// A Watch Change is the internal representation of the watcher API protocol buffers. This is an empty abstract class
/// so that all the different kinds of changes can have a common base class. Note that this class is intended to be
/// sealed within this file.
abstract class WatchChange {
  const WatchChange._();
}

/// An [WatchChangeExistenceFilterWatchChange] applies to the targets and is required to verify the current client state
/// against expected state sent from the server.
class WatchChangeExistenceFilterWatchChange extends WatchChange {
  const WatchChangeExistenceFilterWatchChange(this.targetId, this.existenceFilter) : super._();

  final int targetId;

  final ExistenceFilter existenceFilter;
}

/// A document change represents a change document and a list of target ids to which this change applies. If the
/// document has been deleted, the deleted document will be provided.
class WatchChangeDocumentChange extends WatchChange {
  const WatchChangeDocumentChange(this.updatedTargetIds, this.removedTargetIds, this.documentKey, this.newDocument)
      : super._();

  /// The target IDs for which this document should be updated/added. The new document applies to all of these targets.
  // TODO(long1eu): figure out if we can actually use arrays here for efficiency
  final List<int> updatedTargetIds;

  /// The new document is removed from all of these targets. The target IDs for which this document is no longer
  /// relevant
  final List<int> removedTargetIds;

  /// The key of the document for this change.
  final DocumentKey documentKey;

  /// The new document or DeletedDocument if it was deleted. Is null if the document went out of view without the server
  /// sending a new document.
  final MaybeDocument newDocument;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchChangeDocumentChange &&
          runtimeType == other.runtimeType &&
          const ListEquality<int>().equals(updatedTargetIds, other.updatedTargetIds) &&
          const ListEquality<int>().equals(removedTargetIds, other.removedTargetIds) &&
          documentKey == other.documentKey &&
          newDocument == other.newDocument;

  @override
  int get hashCode =>
      const ListEquality<int>().hash(updatedTargetIds) ^
      const ListEquality<int>().hash(removedTargetIds) ^
      documentKey.hashCode ^
      newDocument.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('updatedTargetIds', updatedTargetIds)
          ..add('removedTargetIds', removedTargetIds)
          ..add('documentKey', documentKey)
          ..add('newDocument', newDocument))
        .toString();
  }
}

/// The state of a target has changed. This can mean removal, addition, current or reset.
class WatchChangeWatchTargetChange extends WatchChange {
  WatchChangeWatchTargetChange(
    this.changeType,
    this.targetIds, [
    Uint8List resumeToken,
    GrpcError cause,
  ])  : resumeToken = resumeToken ?? Uint8List(0),
        // We can get a cause that is considered ok, but everywhere we assume that any non-null cause is an error.
        cause = cause != null && cause.code != StatusCode.ok ? cause : null,
        super._() {
    // cause != null implies removal
    hardAssert(cause == null || changeType == WatchTargetChangeType.removed,
        'Got cause for a target change that was not a removal');
  }

  /// What kind of change occurred to the watch target.
  final WatchTargetChangeType changeType;

  /// The list of targets this change applies to
  final List<int> targetIds;

  /// Returns the opaque, server-assigned token that allows watching a query to be resumed after disconnecting without
  /// retransmitting all the data that matches the query. The resume token essentially identifies a point in time from
  /// which the server should resume sending results.
  final Uint8List resumeToken;

  /// The cause, only valid if changeType == Removal
  final GrpcError cause;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchChangeWatchTargetChange &&
          runtimeType == other.runtimeType &&
          changeType == other.changeType &&
          const ListEquality<int>().equals(targetIds, other.targetIds) &&
          const ListEquality<int>().equals(resumeToken, other.resumeToken) &&
          cause == other.cause;

  @override
  int get hashCode =>
      changeType.hashCode ^
      const ListEquality<int>().hash(targetIds) ^
      const ListEquality<int>().hash(resumeToken) ^
      cause.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('changeType', changeType)
          ..add('targetIds', targetIds)
          ..add('resumeToken', resumeToken)
          ..add('cause', cause))
        .toString();
  }
}
