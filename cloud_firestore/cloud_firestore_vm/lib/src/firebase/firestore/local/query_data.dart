// File created by
// Lung Razvan <long1eu>
// on 20/09/2018

import 'dart:typed_data';

import 'package:_firebase_internal_vm/_firebase_internal_vm.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/query.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/core/sync_engine.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/local/query_purpose.dart';
import 'package:cloud_firestore_vm/src/firebase/firestore/model/snapshot_version.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// An immutable set of metadata that the store will need to keep track of for
/// each query.
class QueryData {
  /// Creates a new QueryData with the given values.
  ///
  /// [LocalStore] assigns a [targetId] that corresponds to the [query] for user
  /// queries or the [SyncEngine] for limbo queries. The [resumeToken] is an
  /// opaque, server-assigned token that allows watching a query to be resumed
  /// after disconnecting without retransmitting all the data that matches the
  /// query. The resume token essentially identifies a point in time from which
  /// the server should resume sending results.
  QueryData(
    this.query,
    this.targetId,
    this.sequenceNumber,
    this.purpose, [
    SnapshotVersion snapshotVersion,
    Uint8List resumeToken,
  ])  : assert(query != null),
        snapshotVersion = snapshotVersion ?? SnapshotVersion.none,
        resumeToken = resumeToken ?? Uint8List(0);

  final Query query;
  final int targetId;
  final int sequenceNumber;
  final QueryPurpose purpose;
  final SnapshotVersion snapshotVersion;
  final Uint8List resumeToken;

  /// Creates a new query data instance with an updated snapshot version and
  /// resume token.
  QueryData copyWith({
    @required SnapshotVersion snapshotVersion,
    @required Uint8List resumeToken,
    @required int sequenceNumber,
  }) {
    assert(sequenceNumber != null);
    return QueryData(
      query,
      targetId,
      sequenceNumber,
      purpose,
      snapshotVersion,
      resumeToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryData &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          targetId == other.targetId &&
          sequenceNumber == other.sequenceNumber &&
          purpose == other.purpose &&
          snapshotVersion == other.snapshotVersion &&
          const DeepCollectionEquality().equals(resumeToken, other.resumeToken);

  @override
  int get hashCode =>
      query.hashCode ^
      targetId.hashCode ^
      sequenceNumber.hashCode ^
      purpose.hashCode ^
      snapshotVersion.hashCode ^
      const DeepCollectionEquality().hash(resumeToken);

  @override
  String toString() {
    return (ToStringHelper(runtimeType)
          ..add('query', query)
          ..add('targetId', targetId)
          ..add('sequenceNumber', sequenceNumber)
          ..add('purpose', purpose)
          ..add('snapshotVersion', snapshotVersion)
          ..add('resumeToken', resumeToken))
        .toString();
  }
}
