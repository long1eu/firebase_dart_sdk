//
//  Generated code. Do not modify.
//  source: firebase/firestore/proto/target.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import '../../../google/firestore/v1/firestore.pb.dart' as $0;
import '../../../google/protobuf/timestamp.pb.dart' as $3;

enum Target_TargetType {
  query, 
  documents, 
  notSet
}

/// A Target is a long-lived data structure representing a resumable listen on a
/// particular user query. While the query describes what to listen to, the
/// Target records data about when the results were last updated and enough
/// information to be able to resume listening later.
class Target extends $pb.GeneratedMessage {
  factory Target({
    $core.int? targetId,
    $3.Timestamp? snapshotVersion,
    $core.List<$core.int>? resumeToken,
    $fixnum.Int64? lastListenSequenceNumber,
    $0.Target_QueryTarget? query,
    $0.Target_DocumentsTarget? documents,
  }) {
    final $result = create();
    if (targetId != null) {
      $result.targetId = targetId;
    }
    if (snapshotVersion != null) {
      $result.snapshotVersion = snapshotVersion;
    }
    if (resumeToken != null) {
      $result.resumeToken = resumeToken;
    }
    if (lastListenSequenceNumber != null) {
      $result.lastListenSequenceNumber = lastListenSequenceNumber;
    }
    if (query != null) {
      $result.query = query;
    }
    if (documents != null) {
      $result.documents = documents;
    }
    return $result;
  }
  Target._() : super();
  factory Target.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Target.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, Target_TargetType> _Target_TargetTypeByTag = {
    5 : Target_TargetType.query,
    6 : Target_TargetType.documents,
    0 : Target_TargetType.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Target', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..oo(0, [5, 6])
    ..a<$core.int>(1, _omitFieldNames ? '' : 'targetId', $pb.PbFieldType.O3)
    ..aOM<$3.Timestamp>(2, _omitFieldNames ? '' : 'snapshotVersion', subBuilder: $3.Timestamp.create)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'resumeToken', $pb.PbFieldType.OY)
    ..aInt64(4, _omitFieldNames ? '' : 'lastListenSequenceNumber')
    ..aOM<$0.Target_QueryTarget>(5, _omitFieldNames ? '' : 'query', subBuilder: $0.Target_QueryTarget.create)
    ..aOM<$0.Target_DocumentsTarget>(6, _omitFieldNames ? '' : 'documents', subBuilder: $0.Target_DocumentsTarget.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Target clone() => Target()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Target copyWith(void Function(Target) updates) => super.copyWith((message) => updates(message as Target)) as Target;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Target create() => Target._();
  Target createEmptyInstance() => create();
  static $pb.PbList<Target> createRepeated() => $pb.PbList<Target>();
  @$core.pragma('dart2js:noInline')
  static Target getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Target>(create);
  static Target? _defaultInstance;

  Target_TargetType whichTargetType() => _Target_TargetTypeByTag[$_whichOneof(0)]!;
  void clearTargetType() => clearField($_whichOneof(0));

  /// An auto-generated sequential numeric identifier for the target. This
  /// serves as the identity of the target, and once assigned never changes.
  @$pb.TagNumber(1)
  $core.int get targetId => $_getIZ(0);
  @$pb.TagNumber(1)
  set targetId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetId() => clearField(1);

  ///  The last snapshot version received from the Watch Service for this target.
  ///
  ///  This is the same value as TargetChange.read_time
  ///  https://github.com/googleapis/googleapis/blob/master/google/firestore/v1/firestore.proto#L735
  @$pb.TagNumber(2)
  $3.Timestamp get snapshotVersion => $_getN(1);
  @$pb.TagNumber(2)
  set snapshotVersion($3.Timestamp v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasSnapshotVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapshotVersion() => clearField(2);
  @$pb.TagNumber(2)
  $3.Timestamp ensureSnapshotVersion() => $_ensure(1);

  ///  An opaque, server-assigned token that allows watching a query to be
  ///  resumed after disconnecting without retransmitting all the data that
  ///  matches the query. The resume token essentially identifies a point in
  ///  time from which the server should resume sending results.
  ///
  ///  This is related to the snapshot_version in that the resume_token
  ///  effectively also encodes that value, but the resume_token is opaque and
  ///  sometimes encodes additional information.
  ///
  ///  A consequence of this is that the resume_token should be used when asking
  ///  the server to reason about where this client is in the watch stream, but
  ///  the client should use the snapshot_version for its own purposes.
  ///
  ///  This is the same value as TargetChange.resume_token
  ///  https://github.com/googleapis/googleapis/blob/master/google/firestore/v1/firestore.proto#L723
  @$pb.TagNumber(3)
  $core.List<$core.int> get resumeToken => $_getN(2);
  @$pb.TagNumber(3)
  set resumeToken($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResumeToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeToken() => clearField(3);

  ///  A sequence number representing the last time this query was listened to,
  ///  used for garbage collection purposes.
  ///
  ///  Conventionally this would be a timestamp value, but device-local clocks
  ///  are unreliable and they must be able to create new listens even while
  ///  disconnected. Instead this should be a monotonically increasing number
  ///  that's incremented on each listen call.
  ///
  ///  This is different from the target_id since the target_id is an immutable
  ///  identifier assigned to the Target on first use while
  ///  last_listen_sequence_number is updated every time the query is listened
  ///  to.
  @$pb.TagNumber(4)
  $fixnum.Int64 get lastListenSequenceNumber => $_getI64(3);
  @$pb.TagNumber(4)
  set lastListenSequenceNumber($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLastListenSequenceNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastListenSequenceNumber() => clearField(4);

  /// A target specified by a query.
  @$pb.TagNumber(5)
  $0.Target_QueryTarget get query => $_getN(4);
  @$pb.TagNumber(5)
  set query($0.Target_QueryTarget v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasQuery() => $_has(4);
  @$pb.TagNumber(5)
  void clearQuery() => clearField(5);
  @$pb.TagNumber(5)
  $0.Target_QueryTarget ensureQuery() => $_ensure(4);

  /// A target specified by a set of document names.
  @$pb.TagNumber(6)
  $0.Target_DocumentsTarget get documents => $_getN(5);
  @$pb.TagNumber(6)
  set documents($0.Target_DocumentsTarget v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasDocuments() => $_has(5);
  @$pb.TagNumber(6)
  void clearDocuments() => clearField(6);
  @$pb.TagNumber(6)
  $0.Target_DocumentsTarget ensureDocuments() => $_ensure(5);
}

/// Global state tracked across all Targets, tracked separately to avoid the
/// need for extra indexes.
class TargetGlobal extends $pb.GeneratedMessage {
  factory TargetGlobal({
    $core.int? highestTargetId,
    $fixnum.Int64? highestListenSequenceNumber,
    $3.Timestamp? lastRemoteSnapshotVersion,
    $core.int? targetCount,
  }) {
    final $result = create();
    if (highestTargetId != null) {
      $result.highestTargetId = highestTargetId;
    }
    if (highestListenSequenceNumber != null) {
      $result.highestListenSequenceNumber = highestListenSequenceNumber;
    }
    if (lastRemoteSnapshotVersion != null) {
      $result.lastRemoteSnapshotVersion = lastRemoteSnapshotVersion;
    }
    if (targetCount != null) {
      $result.targetCount = targetCount;
    }
    return $result;
  }
  TargetGlobal._() : super();
  factory TargetGlobal.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TargetGlobal.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TargetGlobal', package: const $pb.PackageName(_omitMessageNames ? '' : 'firestore.client'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'highestTargetId', $pb.PbFieldType.O3)
    ..aInt64(2, _omitFieldNames ? '' : 'highestListenSequenceNumber')
    ..aOM<$3.Timestamp>(3, _omitFieldNames ? '' : 'lastRemoteSnapshotVersion', subBuilder: $3.Timestamp.create)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'targetCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TargetGlobal clone() => TargetGlobal()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TargetGlobal copyWith(void Function(TargetGlobal) updates) => super.copyWith((message) => updates(message as TargetGlobal)) as TargetGlobal;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TargetGlobal create() => TargetGlobal._();
  TargetGlobal createEmptyInstance() => create();
  static $pb.PbList<TargetGlobal> createRepeated() => $pb.PbList<TargetGlobal>();
  @$core.pragma('dart2js:noInline')
  static TargetGlobal getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TargetGlobal>(create);
  static TargetGlobal? _defaultInstance;

  ///  The highest numbered target id across all Targets.
  ///
  ///  See Target.target_id.
  @$pb.TagNumber(1)
  $core.int get highestTargetId => $_getIZ(0);
  @$pb.TagNumber(1)
  set highestTargetId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasHighestTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHighestTargetId() => clearField(1);

  ///  The highest numbered last_listen_sequence_number across all Targets.
  ///
  ///  See Target.last_listen_sequence_number.
  @$pb.TagNumber(2)
  $fixnum.Int64 get highestListenSequenceNumber => $_getI64(1);
  @$pb.TagNumber(2)
  set highestListenSequenceNumber($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHighestListenSequenceNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearHighestListenSequenceNumber() => clearField(2);

  ///  A global snapshot version representing the last consistent snapshot we
  ///  received from the backend. This is monotonically increasing and any
  ///  snapshots received from the backend prior to this version (e.g. for
  ///  targets resumed with a resume_token) should be suppressed (buffered) until
  ///  the backend has caught up to this snapshot_version again. This prevents
  ///  our cache from ever going backwards in time.
  ///
  ///  This is updated whenever our we get a TargetChange with a read_time and
  ///  empty target_ids.
  @$pb.TagNumber(3)
  $3.Timestamp get lastRemoteSnapshotVersion => $_getN(2);
  @$pb.TagNumber(3)
  set lastRemoteSnapshotVersion($3.Timestamp v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLastRemoteSnapshotVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastRemoteSnapshotVersion() => clearField(3);
  @$pb.TagNumber(3)
  $3.Timestamp ensureLastRemoteSnapshotVersion() => $_ensure(2);

  /// On platforms that need it, holds the number of targets persisted.
  @$pb.TagNumber(4)
  $core.int get targetCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set targetCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTargetCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetCount() => clearField(4);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
