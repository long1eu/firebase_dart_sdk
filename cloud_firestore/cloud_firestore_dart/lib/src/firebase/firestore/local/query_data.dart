// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:typed_data';

import 'package:cloud_firestore_dart/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/core/target.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_dart/src/firebase/firestore/model/snapshot_version.dart';
import 'package:collection/collection.dart';
import 'package:firebase_app_dart/internal.dart';

/// An immutable set of metadata that the store will need to keep track of for
/// each query.
class QueryData {
  /// Creates a new QueryData with the given values.
  ///
  /// [LocalStore] assigns a [targetId] that corresponds to the [target] for user
  /// queries or the [SyncEngine] for limbo queries. The [resumeToken] is an
  /// opaque, server-assigned token that allows watching a query to be resumed
  /// after disconnecting without retransmitting all the data that matches the
  /// query. The resume token essentially identifies a point in time from which
  /// the server should resume sending results.
  QueryData(
    this.target,
    this.targetId,
    this.sequenceNumber,
    this.purpose, [
    SnapshotVersion? snapshotVersion,
    Uint8List? resumeToken,
    this.expectedCount,
  ])  : snapshotVersion = snapshotVersion ?? SnapshotVersion.none,
        resumeToken = resumeToken ?? Uint8List(0);

  final Target target;
  final int targetId;
  final int sequenceNumber;
  final QueryPurpose purpose;
  final SnapshotVersion snapshotVersion;
  final Uint8List resumeToken;

  /// The number of documents that last matched the query at the resume token or
  /// read time. Documents are counted only when making a listen request with a
  /// resume token or read time, otherwise it is `null`.
  final int? expectedCount;

  /// Creates a new query data instance with an updated snapshot version and
  /// resume token. The [expectedCount] is reset, as it only belongs to the
  /// resume token it was computed for.
  QueryData copyWith({
    required SnapshotVersion snapshotVersion,
    required Uint8List resumeToken,
    required int sequenceNumber,
  }) {
    return QueryData(
      target,
      targetId,
      sequenceNumber,
      purpose,
      snapshotVersion,
      resumeToken,
    );
  }

  /// Creates a new query data instance with an updated expected count.
  QueryData withExpectedCount(int? expectedCount) {
    return QueryData(
      target,
      targetId,
      sequenceNumber,
      purpose,
      snapshotVersion,
      resumeToken,
      expectedCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryData &&
          runtimeType == other.runtimeType &&
          target == other.target &&
          targetId == other.targetId &&
          sequenceNumber == other.sequenceNumber &&
          purpose == other.purpose &&
          snapshotVersion == other.snapshotVersion &&
          const DeepCollectionEquality().equals(resumeToken, other.resumeToken) &&
          expectedCount == other.expectedCount;

  @override
  int get hashCode =>
      target.hashCode ^
      targetId.hashCode ^
      sequenceNumber.hashCode ^
      purpose.hashCode ^
      snapshotVersion.hashCode ^
      const DeepCollectionEquality().hash(resumeToken) ^
      expectedCount.hashCode;

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('target', target)
          ..add('targetId', targetId)
          ..add('sequenceNumber', sequenceNumber)
          ..add('purpose', purpose)
          ..add('snapshotVersion', snapshotVersion)
          ..add('resumeToken', resumeToken)
          ..add('expectedCount', expectedCount))
        .toString();
  }
}
