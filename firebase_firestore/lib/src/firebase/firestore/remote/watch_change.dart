// File created by
// Lung Razvan <long1eu>
// on 24/09/2018

import 'dart:typed_data';

import 'package:firebase_common/firebase_common.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/document_key.dart';
import 'package:firebase_firestore/src/firebase/firestore/model/maybe_document.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/existence_filter.dart';
import 'package:firebase_firestore/src/firebase/firestore/remote/watch_stream.dart';
import 'package:firebase_firestore/src/firebase/firestore/util/assert.dart';
import 'package:grpc/grpc.dart';

/// The kind of change that happened to the watch target.
enum WatchTargetChangeType { noChange, added, removed, current, reset }

/// A Watch Change is the internal representation of the watcher API protocol
/// buffers. This is an empty abstract class so that all the different kinds of
/// changes can have a common base class. Note that this class is intended to be
/// sealed within this file.
abstract class WatchChange {
  const WatchChange._();
}

/// An [WatchChangeExistenceFilterWatchChange] applies to the targets and is
/// required to verify the current client state against expected state sent from
/// the server.
class WatchChangeExistenceFilterWatchChange extends WatchChange {
  final int targetId;

  final ExistenceFilter existenceFilter;

  const WatchChangeExistenceFilterWatchChange(
      this.targetId, this.existenceFilter)
      : super._();
}

/// A document change represents a change document and a list of target ids to
/// which this change applies. If the document has been deleted, the deleted
/// document will be provided.
class WatchChangeDocumentChange extends WatchChange {
  // TODO: figure out if we can actually use arrays here for efficiency
  /// The target IDs for which this document should be updated/added. The new
  /// document applies to all of these targets.
  final List<int> updatedTargetIds;

  /// The new document is removed from all of these targets. The target IDs
  /// for which this document is no longer relevant
  final List<int> removedTargetIds;

  /// The key of the document for this change.
  final DocumentKey documentKey;

  /// The new document or DeletedDocument if it was deleted. Is null if the
  /// document went out of view without the server sending a new document.
  final MaybeDocument newDocument;

  const WatchChangeDocumentChange(this.updatedTargetIds, this.removedTargetIds,
      this.documentKey, this.newDocument)
      : super._();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchChangeDocumentChange &&
          runtimeType == other.runtimeType &&
          updatedTargetIds == other.updatedTargetIds &&
          removedTargetIds == other.removedTargetIds &&
          documentKey == other.documentKey &&
          newDocument == other.newDocument;

  @override
  int get hashCode =>
      updatedTargetIds.hashCode ^
      removedTargetIds.hashCode ^
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

/// The state of a target has changed. This can mean removal, addition, current
/// or reset.
class WatchChangeWatchTargetChange extends WatchChange {
  /// What kind of change occurred to the watch target.
  final WatchTargetChangeType changeType;

  /// The list of targets this change applies to
  final List<int> targetIds;

  /// Returns the opaque, server-assigned token that allows watching a query to
  /// be resumed after disconnecting without retransmitting all the data that
  /// matches the query. The resume token essentially identifies a point in time
  /// from which the server should resume sending results.
  final Uint8List resumeToken;

  /// The cause, only valid if changeType == Removal
  final GrpcError cause;

  WatchChangeWatchTargetChange(
    this.changeType,
    this.targetIds, [
    Uint8List resumeToken,
    GrpcError cause,
  ])  : resumeToken = resumeToken ?? WatchStream.emptyResumeToken,
        // We can get a cause that is considered ok, but everywhere we assume
        // that any non-null cause is an error.
        this.cause =
            cause != null && cause.code != StatusCode.ok ? cause : null,
        super._() {
    // cause != null implies removal
    Assert.hardAssert(
        cause == null || changeType == WatchTargetChangeType.removed,
        'Got cause for a target change that was not a removal');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchChangeWatchTargetChange &&
          runtimeType == other.runtimeType &&
          changeType == other.changeType &&
          targetIds == other.targetIds &&
          resumeToken == other.resumeToken &&
          cause == other.cause;

  @override
  int get hashCode =>
      changeType.hashCode ^
      targetIds.hashCode ^
      resumeToken.hashCode ^
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
