// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:typed_data';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:collection/collection.dart';

/// An immutable set of metadata that the store will need to keep track of for
/// each target.
class TargetData {
  /// Creates a new TargetData with the given values.
  ///
  /// The [target] being listened to and the [targetId] to which the target corresponds, assigned
  /// by the [LocalStore] for user queries or the [SyncEngine] for limbo queries.
  /// [lastLimboFreeSnapshotVersion] represents the maximum snapshot version at which the associated target
  /// view contained no limbo documents.
  /// [resumeToken] is an opaque, server-assigned token that allows watching a target to be resumed
  /// after disconnecting without retransmitting all the data that matches the target. The resume
  /// token essentially identifies a point in time from which the server should resume sending
  TargetData(
    this.target,
    this.targetId,
    this.sequenceNumber,
    this.purpose, [
    SnapshotVersion snapshotVersion,
    SnapshotVersion lastLimboFreeSnapshotVersion,
    Uint8List resumeToken,
  ])  : assert(target != null),
        snapshotVersion = snapshotVersion ?? SnapshotVersion.none,
        lastLimboFreeSnapshotVersion = lastLimboFreeSnapshotVersion ?? SnapshotVersion.none,
        resumeToken = resumeToken ?? Uint8List(0);

  final Target target;
  final int targetId;
  final int sequenceNumber;
  final QueryPurpose purpose;
  final SnapshotVersion snapshotVersion;
  final SnapshotVersion lastLimboFreeSnapshotVersion;
  final Uint8List resumeToken;

  /// Creates a new query data instance with an updated snapshot version and
  /// resume token.
  TargetData copyWith({
    SnapshotVersion snapshotVersion,
    Uint8List resumeToken,
    int sequenceNumber,
    SnapshotVersion lastLimboFreeSnapshotVersion,
  }) {
    return TargetData(
      target,
      targetId,
      sequenceNumber ?? this.sequenceNumber,
      purpose,
      snapshotVersion ?? this.snapshotVersion,
      lastLimboFreeSnapshotVersion ?? this.lastLimboFreeSnapshotVersion,
      resumeToken ?? this.resumeToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetData &&
          runtimeType == other.runtimeType &&
          target == other.target &&
          targetId == other.targetId &&
          sequenceNumber == other.sequenceNumber &&
          purpose == other.purpose &&
          snapshotVersion == other.snapshotVersion &&
          lastLimboFreeSnapshotVersion == other.lastLimboFreeSnapshotVersion &&
          const DeepCollectionEquality().equals(resumeToken, other.resumeToken);

  @override
  int get hashCode =>
      target.hashCode ^
      targetId.hashCode ^
      sequenceNumber.hashCode ^
      purpose.hashCode ^
      snapshotVersion.hashCode ^
      lastLimboFreeSnapshotVersion.hashCode ^
      const DeepCollectionEquality().hash(resumeToken);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('target', target)
          ..add('targetId', targetId)
          ..add('sequenceNumber', sequenceNumber)
          ..add('purpose', purpose)
          ..add('snapshotVersion', snapshotVersion)
          ..add('lastLimboFreeSnapshotVersion', lastLimboFreeSnapshotVersion)
          ..add('resumeToken', resumeToken))
        .toString();
  }
}
